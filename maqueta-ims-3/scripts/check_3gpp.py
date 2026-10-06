#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""check_3gpp.py — Verificador de cumplimiento 3GPP sobre una captura SIP.

Uso:  python3 scripts/check_3gpp.py maqueta_ims_sip_only.pcap [--json out.json]

Lee la captura (pcap o pcapng, Linux cooked SLL/SLL2 o Ethernet) sin depender de
los campos de tshark: reconstruye IPv4/UDP/TCP y desencapsula ESP con cifrado
NULL (RFC 2410), verificando el ICV HMAC-SHA-1-96 con la IK obtenida por
Milenage a partir del reto AKA capturado (TS 33.203 §7, TS 35.206).

Reglas (cada una cita su especificación) agrupadas en:
  G  — SIP básico (RFC 3261)
  A  — Autenticación IMS-AKA (TS 33.203 §6, RFC 3310, TS 24.229 §5.1.1.2/§5.4.1.2)
  S  — Acuerdo de seguridad e IPsec en Gm (RFC 3329, TS 33.203 §7, TS 24.229 §5.2.2)
  R  — Registro e identidades (TS 24.229 §5.1.1, TS 23.003 §13)
  C  — Establecimiento de sesión (TS 24.229 §5.1.2A/§5.2.6/§5.4.3, TS 24.173, TS 26.114)
  M  — MWI (TS 24.606, RFC 3842)
Salida: informe Markdown en stdout; código 0 si todas las reglas aplicables pasan.
"""
import argparse
import base64
import hashlib
import hmac
import json
import os
import re
import struct
import sys
from collections import defaultdict

from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

NODES = {
    "172.32.0.10": "UE", "172.32.0.8": "P-CSCF", "172.32.0.6": "I-CSCF",
    "172.32.0.7": "S-CSCF", "172.32.0.16": "AS-Front", "172.32.0.15": "FreeSWITCH",
}
OPC_DEFAULT = "61f0f589e23b2bd9c35fe9f2d09db0c1"
COMPACT = {"v": "via", "f": "from", "t": "to", "i": "call-id", "m": "contact",
           "l": "content-length", "c": "content-type", "k": "supported",
           "e": "content-encoding", "s": "subject", "o": "event", "u": "allow-events"}


# --------------------------------------------------------------- Milenage ---
def _aes(k, x):
    e = Cipher(algorithms.AES(k), modes.ECB()).encryptor()
    return e.update(x) + e.finalize()


def _xor(a, b):
    return bytes(i ^ j for i, j in zip(a, b))


def _rot(x, nbytes):
    return x[nbytes:] + x[:nbytes]


def milenage(k, opc, rand, sqn=None, amf=None):
    """Devuelve dict con RES, CK, IK, AK y (si sqn/amf) MAC-A (TS 35.206)."""
    temp = _aes(k, _xor(rand, opc))
    c = [bytes(15) + bytes([n]) for n in (0, 1, 2, 4, 8)]
    out2 = _xor(_aes(k, _xor(_rot(_xor(temp, opc), 0), c[1])), opc)
    out3 = _xor(_aes(k, _xor(_rot(_xor(temp, opc), 4), c[2])), opc)
    out4 = _xor(_aes(k, _xor(_rot(_xor(temp, opc), 8), c[3])), opc)
    r = {"RES": out2[8:16], "AK": out2[0:6], "CK": out3, "IK": out4}
    if sqn is not None:
        in1 = sqn + amf + sqn + amf
        out1 = _xor(_aes(k, _xor(temp, _rot(_xor(in1, opc), 8))), opc)
        r["MAC"] = out1[0:8]
    return r


# ------------------------------------------------------------ lectura pcap ---
def read_frames(path):
    """Itera (ts, linktype, bytes) para pcap y pcapng."""
    with open(path, "rb") as f:
        data = f.read()
    magic = data[:4]
    if magic in (b"\xd4\xc3\xb2\xa1", b"\x4d\x3c\xb2\xa1", b"\xa1\xb2\xc3\xd4", b"\xa1\xb2\x3c\x4d"):
        le = magic in (b"\xd4\xc3\xb2\xa1", b"\x4d\x3c\xb2\xa1")
        nano = magic in (b"\x4d\x3c\xb2\xa1", b"\xa1\xb2\x3c\x4d")
        e = "<" if le else ">"
        linktype = struct.unpack(e + "I", data[20:24])[0]
        off = 24
        while off + 16 <= len(data):
            sec, frac, incl, _ = struct.unpack(e + "IIII", data[off:off + 16])
            off += 16
            yield sec + frac / (1e9 if nano else 1e6), linktype, data[off:off + incl]
            off += incl
    elif magic == b"\x0a\x0d\x0d\x0a":
        off = 0
        e = "<"
        ifaces = []
        while off + 12 <= len(data):
            btype = struct.unpack(e + "I", data[off:off + 4])[0]
            if btype == 0x0A0D0D0A:
                e = "<" if data[off + 8:off + 12] == b"\x4d\x3c\x2b\x1a" else ">"
                ifaces = []
            blen = struct.unpack(e + "I", data[off + 4:off + 8])[0]
            body = data[off + 8:off + blen - 4]
            if btype == 1:
                ifaces.append(struct.unpack(e + "H", body[:2])[0])
            elif btype == 6:
                iid, th, tl, cap, _ = struct.unpack(e + "IIIII", body[:20])
                ts = ((th << 32) | tl) / 1e6
                yield ts, ifaces[iid] if iid < len(ifaces) else 1, body[20:20 + cap]
            off += blen
    else:
        raise SystemExit("formato de captura no reconocido: %s" % path)


def l3(linktype, frame):
    if linktype == 276:            # LINUX_SLL2
        proto, hdr = struct.unpack(">H", frame[:2])[0], 20
    elif linktype == 113:          # LINUX_SLL
        proto, hdr = struct.unpack(">H", frame[14:16])[0], 16
    elif linktype == 1:            # Ethernet
        proto, hdr = struct.unpack(">H", frame[12:14])[0], 14
    elif linktype in (101, 228):   # raw IPv4
        return frame
    else:
        return None
    return frame[hdr:] if proto == 0x0800 else None


# ------------------------------------------------------------- modelo SIP ---
class Msg:
    def __init__(self, n, ts, src, sport, dst, dport, proto, raw, esp=None):
        self.n, self.ts, self.src, self.sport = n, ts, src, sport
        self.dst, self.dport, self.proto, self.raw = dst, dport, proto, raw
        self.esp = esp                      # dict spi/seq/icv/auth o None
        head, _, self.body = raw.partition("\r\n\r\n")
        lines = re.split(r"\r\n(?![ \t])", head)
        self.first = lines[0]
        self.headers = []
        for ln in lines[1:]:
            if ":" in ln:
                name, val = ln.split(":", 1)
                name = name.strip().lower()
                self.headers.append((COMPACT.get(name, name), val.strip()))
        m = re.match(r"SIP/2\.0 (\d{3})", self.first)
        self.status = int(m.group(1)) if m else None
        self.method = None if m else self.first.split(" ", 1)[0]
        self.ruri = None if m else self.first.split(" ")[1]
        cseq = self.h("cseq") or "0 X"
        self.cseq_method = cseq.split()[-1]

    def h(self, name):
        name = name.lower()
        for k, v in self.headers:
            if k == name:
                return v
        return None

    def hall(self, name):
        name = name.lower()
        return [v for k, v in self.headers if k == name]

    @property
    def hop(self):
        return "%s→%s" % (NODES.get(self.src, self.src), NODES.get(self.dst, self.dst))

    def is_gm(self):
        return {NODES.get(self.src), NODES.get(self.dst)} == {"UE", "P-CSCF"}

    def from_ue(self):
        return NODES.get(self.src) == "UE"

    def to_ue(self):
        return NODES.get(self.dst) == "UE"

    def ref(self):
        return "#%d %s %s" % (self.n, self.hop, self.first[:60])


def split_sip(buf):
    """Separa mensajes SIP concatenados (TCP) usando Content-Length."""
    out = []
    while buf:
        i = buf.find("\r\n\r\n")
        if i < 0:
            break
        head = buf[:i]
        m = re.search(r"\r\n(?:content-length|l)[ \t]*:[ \t]*(\d+)", head, re.I)
        clen = int(m.group(1)) if m else 0
        end = i + 4 + clen
        out.append(buf[:end])
        buf = buf[end:].lstrip("\r\n")
    return out


def parse_capture(path):
    msgs, seen, n = [], {}, 0
    esp_raw = []
    for ts, lt, frame in read_frames(path):
        ip = l3(lt, frame)
        if not ip or len(ip) < 20 or ip[0] >> 4 != 4:
            continue
        ihl = (ip[0] & 15) * 4
        tot = struct.unpack(">H", ip[2:4])[0]
        proto = ip[9]
        src = ".".join(map(str, ip[12:16]))
        dst = ".".join(map(str, ip[16:20]))
        frag = struct.unpack(">H", ip[6:8])[0]
        if frag & 0x3FFF:
            continue                             # fragmento IP: no esperado (MTU 9000)
        pl = ip[ihl:tot]
        esp = None
        if proto == 50 and len(pl) > 8 + 12:
            spi, seq = struct.unpack(">II", pl[:8])
            icv = pl[-12:]
            inner = pl[8:-12]
            padlen, nexth = inner[-2], inner[-1]
            esp = {"spi": spi, "seq": seq, "icv": icv, "authdata": pl[:-12], "auth": None}
            pl = inner[:-(padlen + 2)]
            proto = nexth
        if proto == 17 and len(pl) >= 8:
            sport, dport = struct.unpack(">HH", pl[:4])
            payload = pl[8:]
            tp = "udp"
        elif proto == 6 and len(pl) >= 20:
            sport, dport = struct.unpack(">HH", pl[:4])
            payload = pl[(pl[12] >> 4) * 4:]
            tp = "tcp"
        else:
            continue
        if not payload:
            continue
        key = (src, sport, dst, dport, hashlib.md5(payload).hexdigest())
        if key in seen and ts - seen[key] < 0.010:
            continue                             # duplicado de -i any (veth/bridge)
        seen[key] = ts
        text = payload.decode("utf-8", "replace")
        parts = split_sip(text) if tp == "tcp" else [text]
        for p in parts:
            if not re.match(r"^([A-Z]+ \S+ SIP/2\.0|SIP/2\.0 \d{3})", p):
                continue
            n += 1
            m = Msg(n, ts, src, sport, dst, dport, tp, p, esp)
            msgs.append(m)
            if esp:
                esp_raw.append(m)
    return msgs


# ------------------------------------------------------------- utilidades ---
def dparams(value):
    """Parámetros de una cabecera Digest (Authorization/WWW-Authenticate)."""
    v = re.sub(r"^\s*Digest\s+", "", value, flags=re.I)
    out = {}
    for m in re.finditer(r'([\w-]+)\s*=\s*("([^"]*)"|[^,\s]+)', v):
        out[m.group(1).lower()] = m.group(3) if m.group(3) is not None else m.group(2)
    return out


def secparams(value):
    """Mecanismos sec-agree (RFC 3329) -> lista de dict."""
    res = []
    for mech in value.split(","):
        parts = [p.strip() for p in mech.split(";")]
        d = {"mech": parts[0]}
        for p in parts[1:]:
            if "=" in p:
                k, v = p.split("=", 1)
                d[k.strip().lower()] = v.strip()
        res.append(d)
    return res


def load_subscribers():
    env = {}
    p = os.path.join(ROOT, ".env")
    if os.path.exists(p):
        for ln in open(p):
            if "=" in ln and not ln.startswith("#"):
                k, v = ln.strip().split("=", 1)
                env[k] = v
    subs = {}
    for i in (1, 2):
        imsi, ki = env.get("UE%d_IMSI" % i), env.get("UE%d_KI" % i)
        if imsi and ki:
            subs[imsi] = {"k": bytes.fromhex(ki), "opc": bytes.fromhex(OPC_DEFAULT)}
    return subs


class Report:
    def __init__(self):
        self.rules = []

    def add(self, rid, ref, desc, ok, evid, na=False):
        self.rules.append({"id": rid, "ref": ref, "desc": desc,
                           "result": "N/A" if na else ("PASS" if ok else "FAIL"),
                           "evidence": evid})


def check(msgs, subs):
    R = Report()
    gm = [m for m in msgs if m.is_gm()]
    regs_ue = [m for m in gm if m.from_ue() and m.method == "REGISTER"]
    # REGISTER "inicial" = Authorization con response vacío (TS 24.229 §5.1.1.2.1),
    # vaya en claro (primer registro) o por una SA ya existente (re-registro).
    # REGISTER "autenticado" = respuesta AKA al reto; siempre debe ir por la SA.
    def _resp(m):
        return dparams(m.h("authorization") or "").get("response")
    initial_regs = [m for m in regs_ue if _resp(m) == ""]
    prot_regs = [m for m in regs_ue if _resp(m)]
    unprot_regs = [m for m in regs_ue if not m.esp]
    r401_gm = [m for m in gm if m.to_ue() and m.status == 401 and m.cseq_method == "REGISTER"]
    r401_mw = [m for m in msgs if m.status == 401 and m.cseq_method == "REGISTER"
               and NODES.get(m.dst) == "P-CSCF"]
    r200_gm = [m for m in gm if m.to_ue() and m.status == 200 and m.cseq_method == "REGISTER"]
    regs_mw = [m for m in msgs if m.method == "REGISTER" and NODES.get(m.src) == "P-CSCF"]

    # ---------------------------------------------------------------- G ---
    bad = []
    for m in msgs:
        need = ["via", "from", "to", "call-id", "cseq"] + (["max-forwards"] if m.method else [])
        miss = [h for h in need if not m.h(h)]
        br = re.search(r"branch=([^;,\s]+)", m.h("via") or "")
        if miss or not br or not br.group(1).startswith("z9hG4bK"):
            bad.append("%s falta %s" % (m.ref(), miss or "branch z9hG4bK"))
    R.add("G1", "RFC 3261 §8.1.1/§20", "Cabeceras obligatorias y branch z9hG4bK en todos los mensajes",
          not bad, bad[:5] or ["%d mensajes verificados" % len(msgs)])
    bad = []
    for m in msgs:
        cl = m.h("content-length")
        if cl is not None and int(cl) != len(m.body.encode("utf-8", "replace")):
            bad.append("%s Content-Length=%s cuerpo=%d" % (m.ref(), cl, len(m.body)))
    R.add("G2", "RFC 3261 §18.3/§20.14", "Mensajes completos (Content-Length = cuerpo, sin fragmentación IP)",
          not bad, bad[:5] or ["%d mensajes íntegros" % len(msgs)])

    # ---------------------------------------------------------------- A ---
    # A1: REGISTER inicial con Authorization (IMPI) y response vacío
    bad, ok_n = [], 0
    for m in initial_regs:
        a = m.h("authorization")
        d = dparams(a) if a else {}
        if not a or not re.match(r"^\d{14,15}@ims\.mnc\d{3}\.mcc\d{3}\.3gppnetwork\.org$", d.get("username", "")) \
                or d.get("nonce", None) != "" or d.get("response", None) != "" or not d.get("realm") or not d.get("uri"):
            bad.append("%s Authorization=%s" % (m.ref(), a))
        else:
            ok_n += 1
    R.add("A1", "TS 24.229 §5.1.1.2.1 / TS 23.003 §13.3",
          "REGISTER inicial: Authorization con IMPI (IMSI@dominio), realm, uri, nonce=\"\" y response=\"\"",
          bool(initial_regs) and not bad, bad[:5] or ["%d REGISTER iniciales conformes" % ok_n])
    # A2: 401 hacia el UE con AKAv1-MD5, sin ck/ik
    bad = []
    for m in r401_gm:
        wa = m.h("www-authenticate") or ""
        d = dparams(wa)
        try:
            nb = base64.b64decode(d.get("nonce", ""))
        except Exception:
            nb = b""
        if d.get("algorithm") != "AKAv1-MD5" or len(nb) < 32 or "auth" not in d.get("qop", "") \
                or "ck" in d or "ik" in d:
            bad.append("%s WWW-Authenticate=%s" % (m.ref(), wa[:120]))
    R.add("A2", "TS 33.203 §6.1 / RFC 3310 §3.1 / TS 24.229 §5.2.2.1",
          "401 al UE: algorithm=AKAv1-MD5, nonce=base64(RAND‖AUTN), qop=auth, sin ck/ik",
          bool(r401_gm) and not bad, bad[:5] or ["%d retos AKA conformes" % len(r401_gm)])
    # A3: el S-CSCF entrega ck/ik al P-CSCF (Mw)
    bad = [m.ref() for m in r401_mw if not ("ck=" in (m.h("www-authenticate") or "") and "ik=" in (m.h("www-authenticate") or ""))]
    R.add("A3", "TS 24.229 §5.4.1.2.1 / TS 33.203 §7.2",
          "401 en Mw (S/I-CSCF→P-CSCF) transporta ck/ik para establecer las SA",
          bool(r401_mw) and not bad, bad[:5] or ["%d retos en Mw con ck/ik" % len(r401_mw)])
    # A4: ningún reto Digest-MD5 (autenticación no-3GPP)
    md5 = [m.ref() for m in msgs if m.status in (401, 407)
           and dparams(m.h("www-authenticate") or m.h("proxy-authenticate") or "").get("algorithm", "MD5").upper() == "MD5"]
    R.add("A4", "TS 33.203 §6.1", "Ningún reto con Digest-MD5 (solo IMS-AKA)", not md5,
          md5[:5] or ["0 retos MD5"])
    # A5: respuesta AKA del REGISTER protegido verificada criptográficamente (RES = f2(K,RAND))
    #     y AUTN válido (MAC-A = f1) con las claves de prueba de la USIM.
    bad, good = [], []
    chal_by_callid = {}
    for m in r401_gm:
        chal_by_callid.setdefault(m.h("call-id"), []).append(m)
    for m in prot_regs:
        d = dparams(m.h("authorization") or "")
        imsi = d.get("username", "").split("@")[0]
        sub = subs.get(imsi)
        if not sub:
            bad.append("%s IMPI %s sin claves de prueba" % (m.ref(), d.get("username")))
            continue
        try:
            nb = base64.b64decode(d.get("nonce", ""))
        except Exception:
            nb = b""
        rand, autn = nb[:16], nb[16:32]
        mv = milenage(sub["k"], sub["opc"], rand)
        sqn = _xor(autn[:6], mv["AK"])
        mv = milenage(sub["k"], sub["opc"], rand, sqn, autn[6:8])
        ha1 = hashlib.md5(("%s:%s:" % (d.get("username"), d.get("realm"))).encode() + mv["RES"]).hexdigest()
        ha2 = hashlib.md5(("REGISTER:%s" % d.get("uri")).encode()).hexdigest()
        exp = hashlib.md5(("%s:%s:%s:%s:%s:%s" % (ha1, d.get("nonce"), d.get("nc"), d.get("cnonce"),
                                                  d.get("qop"), ha2)).encode()).hexdigest()
        if d.get("algorithm") != "AKAv1-MD5" or d.get("response") != exp or autn[8:16] != mv["MAC"]:
            bad.append("%s response=%s esperado=%s MAC-ok=%s" % (m.ref(), d.get("response"), exp, autn[8:16] == mv["MAC"]))
        else:
            good.append("%s RES ok, AUTN MAC-A ok (SQN=%s)" % (m.ref(), sqn.hex()))
            m.aka = mv
    R.add("A5", "TS 33.203 §6.1 / TS 35.206 / RFC 3310 §3.4",
          "Respuesta Digest-AKAv1-MD5 = f(RES) y AUTN (MAC-A) verificados con Milenage",
          bool(prot_regs) and not bad, bad[:5] or good[:6])
    # A6: integrity-protected en el REGISTER reenviado por el P-CSCF
    bad = []
    by_tx = {(m.h("call-id"), m.h("cseq")): m for m in regs_ue}
    for m in regs_mw:
        a = m.h("authorization") or ""
        ip = dparams(a).get("integrity-protected")
        ue_req = by_tx.get((m.h("call-id"), m.h("cseq")))
        if ue_req is None:
            continue
        expected = "yes" if ue_req.esp else "no"
        if ip != expected:
            bad.append("%s integrity-protected=%s (esperado %s)" % (m.ref(), ip, expected))
    R.add("A6", "TS 24.229 §5.2.2.1 / TS 33.203 §6.1",
          "P-CSCF marca integrity-protected=\"no\" (inicial) / \"yes\" (por la SA) hacia el S-CSCF",
          bool(regs_mw) and not bad, bad[:5] or ["%d REGISTER en Mw conformes" % len(regs_mw)])

    # ---------------------------------------------------------------- S ---
    bad = []
    for m in regs_ue:
        sc = m.h("security-client") or ""
        mechs = [x for x in secparams(sc) if x["mech"] == "ipsec-3gpp"]
        req = (m.h("require") or "") + "," + (m.h("proxy-require") or "")
        if not mechs or not all(k in mechs[0] for k in ("alg", "spi-c", "spi-s", "port-c", "port-s")) \
                or req.count("sec-agree") < 2:
            bad.append("%s Security-Client=%s Require/Proxy-Require=%s" % (m.ref(), sc, req))
        elif mechs[0]["port-c"] == mechs[0]["port-s"]:
            bad.append("%s port-c = port-s" % m.ref())
    R.add("S1", "RFC 3329 §2.3.1 / TS 33.203 §7.1 / TS 24.229 §5.1.1.2.1",
          "REGISTER del UE: Security-Client ipsec-3gpp (alg, spi-c≠, spi-s, port-c≠port-s) + Require/Proxy-Require: sec-agree",
          bool(regs_ue) and not bad, bad[:5] or ["%d REGISTER con sec-agree" % len(regs_ue)])
    bad = []
    for m in r401_gm:
        ss = m.h("security-server") or ""
        mechs = [x for x in secparams(ss) if x["mech"] == "ipsec-3gpp"]
        if not mechs or not all(k in mechs[0] for k in ("q", "alg", "spi-c", "spi-s", "port-c", "port-s")):
            bad.append("%s Security-Server=%s" % (m.ref(), ss))
    R.add("S2", "RFC 3329 §2.3.1 / TS 33.203 §7.1",
          "401 al UE con Security-Server ipsec-3gpp (q, alg, spi-c, spi-s, port-c, port-s) propios del P-CSCF",
          bool(r401_gm) and not bad, bad[:5] or ["%d Security-Server conformes" % len(r401_gm)])
    # S3: REGISTER protegido -> Security-Verify == Security-Server del 401 previo, por la SA
    bad, good = [], []
    for m in prot_regs:
        prev = [c for c in r401_gm if c.ts < m.ts and c.h("call-id") == m.h("call-id")]
        sv = secparams(m.h("security-verify") or "")
        match = None
        for c in reversed(prev):
            ss = secparams(c.h("security-server") or "")
            if ss and sv and ss[0].get("port-s") and \
                    all(ss[0].get(k) == sv[0].get(k) for k in ("spi-c", "spi-s", "port-c", "port-s", "alg")):
                match = (c, ss[0])
                break
        if not match:
            bad.append("%s Security-Verify sin Security-Server coincidente" % m.ref())
            continue
        ss = match[1]
        if not m.esp or str(m.dport) != ss.get("port-s") or \
                not str(ss.get("spi-s", "")).isdigit() or m.esp["spi"] != int(ss["spi-s"]):
            bad.append("%s no viaja por la SA (dport=%s spi=%s; esperado %s/%s)" % (
                m.ref(), m.dport, m.esp and m.esp["spi"], ss.get("port-s"), ss.get("spi-s")))
        else:
            good.append("%s ESP spi=%d → P-CSCF:%s" % (m.ref(), m.esp["spi"], ss["port-s"]))
    R.add("S3", "RFC 3329 §2.3.1 / TS 33.203 §7.2 / TS 24.229 §5.1.1.2.1",
          "2º REGISTER: Security-Verify = Security-Server y enviado por la SA (ESP, port-s/spi-s del P-CSCF)",
          bool(prot_regs) and not bad, bad[:5] or good[:6])
    # S4: todo el tráfico Gm posterior a la SA viaja en ESP (salvo el REGISTER inicial y su 100/401)
    bad = []
    for m in gm:
        # Solo el REGISTER inicial sin SA (sin Security-Verify) y sus 100/401 van en claro.
        unprot_ok = (m.method == "REGISTER" and not m.h("security-verify") and _resp(m) == "") or \
                    (m.status in (100, 401) and m.cseq_method == "REGISTER" and
                     any(r.h("call-id") == m.h("call-id") and r.h("cseq") == m.h("cseq") and not r.esp
                         and not r.h("security-verify") for r in regs_ue))
        if not m.esp and not unprot_ok:
            bad.append(m.ref())
    R.add("S4", "TS 33.203 §7.3 / TS 24.229 §5.1.1.2.2",
          "Tras el acuerdo, todo mensaje SIP en Gm viaja protegido por IPsec ESP",
          bool(gm) and not bad, bad[:6] or ["%d mensajes Gm; %d en ESP" % (len(gm), sum(1 for m in gm if m.esp))])
    # S5: ICV ESP (HMAC-SHA-1-96 con IK‖0^32) válido en los mensajes protegidos
    iks = list({m.aka["IK"] for m in prot_regs if getattr(m, "aka", None)})
    bad, ok_n = [], 0
    for m in gm:
        if not m.esp:
            continue
        valid = any(hmac.new(ik + bytes(4), m.esp["authdata"], hashlib.sha1).digest()[:12] == m.esp["icv"] for ik in iks)
        if valid:
            ok_n += 1
        else:
            bad.append("%s spi=%d" % (m.ref(), m.esp["spi"]))
    R.add("S5", "TS 33.203 §7.1 / RFC 2404 / RFC 4303",
          "Integridad ESP verificada: ICV HMAC-SHA-1-96 con IK derivada por Milenage",
          ok_n > 0 and not bad, bad[:5] or ["%d paquetes ESP con ICV válido (%d IK distintas)" % (ok_n, len(iks))])
    # S6: el P-CSCF no propaga sec-agree al core y no lo añade en respuestas 2xx
    bad = []
    for m in msgs:
        if not m.is_gm() and (m.h("security-client") or m.h("security-verify") or m.h("security-server")
                              or "sec-agree" in (m.h("require") or "") + (m.h("proxy-require") or "")):
            bad.append(m.ref())
        if m.is_gm() and m.status and 200 <= m.status < 300 and (m.h("security-verify") or m.h("security-server")):
            bad.append("%s (2xx con cabeceras sec-agree)" % m.ref())
    R.add("S6", "TS 24.229 §5.2.2.1 / RFC 3329 §2.3.1",
          "Cabeceras sec-agree solo en Gm (P-CSCF las retira hacia el core) y nunca en 2xx",
          not bad, bad[:5] or ["sin fugas de cabeceras sec-agree"])

    # ---------------------------------------------------------------- R ---
    bad = []
    dom = re.compile(r"^sip:ims\.mnc\d{3}\.mcc\d{3}\.3gppnetwork\.org$")
    for m in regs_ue:
        to = re.search(r"<([^>]+)>", m.h("to") or "")
        fr = re.search(r"<([^>]+)>", m.h("from") or "")
        if not dom.match(m.ruri or "") or not to or not fr or to.group(1) != fr.group(1) \
                or not re.match(r"^sip:\d+@ims\.", to.group(1)):
            bad.append("%s R-URI=%s To=%s" % (m.ref(), m.ruri, m.h("to")))
    R.add("R1", "TS 24.229 §5.1.1.2.1 / TS 23.003 §13.4",
          "REGISTER: R-URI = dominio de red local; From = To = IMPU sip:<MSISDN>@dominio",
          bool(regs_ue) and not bad, bad[:5] or ["%d REGISTER conformes" % len(regs_ue)])
    bad = []
    for m in regs_ue:
        ct = m.h("contact") or ""
        sc = secparams(m.h("security-client") or "")
        port_s = sc[0].get("port-s") if sc else None
        uri_port = re.search(r"<sip:[^@>]+@[\d.]+:(\d+)", ct)
        if '+g.3gpp.icsi-ref="urn%3Aurn-7%3A3gpp-service.ims.icsi.mmtel"' not in ct or "+g.3gpp.smsip" not in ct \
                or not uri_port or (port_s and uri_port.group(1) != port_s):
            bad.append("%s Contact=%s" % (m.ref(), ct))
    R.add("R2", "TS 24.229 §5.1.1.2.1 / RFC 3840 §9 / TS 24.173 §5.2",
          "Contact: puerto protegido port-s, +g.3gpp.icsi-ref (MMTEL, entre comillas) y +g.3gpp.smsip",
          bool(regs_ue) and not bad, bad[:5] or ["%d Contact conformes" % len(regs_ue)])
    bad = []
    for m in [x for x in gm if x.from_ue() and x.method and x.method not in ("ACK", "CANCEL")]:
        pani = m.h("p-access-network-info") or ""
        if not re.match(r"^3GPP-E-UTRAN-FDD;\s*utran-cell-id-3gpp=[0-9A-Fa-f]{15,16}$", pani):
            bad.append("%s PANI=%s" % (m.ref(), pani or "—"))
    R.add("R3", "TS 24.229 §5.1.1.2.1 / §7.2A.4",
          "P-Access-Network-Info del UE (E-UTRAN, utran-cell-id-3gpp) en toda petición salvo ACK/CANCEL",
          not bad, bad[:5] or ["PANI presente y bien formado"])
    bad = []
    for m in regs_mw:
        if not re.search(r"<sip:[^>]*pcscf[^>]*;lr>", m.h("path") or "") or "path" not in (m.h("require") or "") \
                or not m.h("p-visited-network-id"):
            bad.append("%s Path=%s Require=%s" % (m.ref(), m.h("path"), m.h("require")))
    R.add("R4", "TS 24.229 §5.2.2.1 / RFC 3327",
          "REGISTER en Mw: Path del P-CSCF, Require: path y P-Visited-Network-ID",
          bool(regs_mw) and not bad, bad[:5] or ["%d REGISTER en Mw conformes" % len(regs_mw)])
    bad = []
    for m in r200_gm:
        if re.search(r"expires=0\b", m.h("contact") or "") or (m.h("expires") or "").strip() == "0":
            continue                                  # 200 a des-registro (TS 24.229 §5.4.1.4)
        exp = m.h("contact") and ("expires=" in m.h("contact"))
        if m.h("contact") is None or not m.h("service-route") or not m.h("p-associated-uri") or not m.h("path") \
                or (not exp and "expires=0" not in (m.h("contact") or "")):
            if m.h("contact") is None and m.h("p-associated-uri"):
                continue                              # 200 a des-registro sin contactos
            bad.append("%s SR=%s PAU=%s" % (m.ref(), m.h("service-route"), m.h("p-associated-uri")))
    R.add("R5", "TS 24.229 §5.4.1.2.2 / RFC 3608 / RFC 3455",
          "200 OK del REGISTER: Service-Route, P-Associated-URI, Path y Contact con expires",
          bool(r200_gm) and not bad, bad[:5] or ["%d 200 OK conformes" % len(r200_gm)])

    # ---------------------------------------------------------------- C ---
    inv_ue = [m for m in gm if m.from_ue() and m.method == "INVITE" and ";tag=" not in (m.h("to") or "")]
    bad = []
    for m in inv_ue:
        miss = []
        ct = m.h("contact") or ""
        if '+g.3gpp.icsi-ref="urn%3Aurn-7%3A3gpp-service.ims.icsi.mmtel"' not in ct:
            miss.append("Contact icsi-ref")
        if "3gpp-service.ims.icsi.mmtel" not in (m.h("accept-contact") or ""):
            miss.append("Accept-Contact")
        if (m.h("p-preferred-service") or "") != "urn:urn-7:3gpp-service.ims.icsi.mmtel":
            miss.append("P-Preferred-Service")
        ppi = m.h("p-preferred-identity")
        frm = re.search(r"sip:[^>;]+", m.h("from") or "")
        if ppi and frm and frm.group(0) not in ppi:
            miss.append("P-Preferred-Identity≠From")
        routes = ",".join(m.hall("route"))
        if "orig@scscf" not in routes:
            miss.append("Route con Service-Route")
        if miss:
            bad.append("%s falta %s" % (m.ref(), ", ".join(miss)))
    R.add("C1", "TS 24.229 §5.1.2A.1.1 / TS 24.173 §5.1 / RFC 3841",
          "INVITE inicial del UE: Route (P-CSCF + Service-Route), Contact/Accept-Contact y P-Preferred-Service MMTEL",
          bool(inv_ue) and not bad, bad[:5] or ["%d INVITE iniciales conformes" % len(inv_ue)])
    bad = []
    for m in inv_ue:
        sdp = m.body
        if "AMR" not in sdp or "telephone-event" not in sdp:
            bad.append("%s SDP sin AMR/telephone-event" % m.ref())
        elif not re.search(r"a=rtpmap:\d+ AMR-WB/16000", sdp) or not re.search(r"a=rtpmap:\d+ AMR/8000", sdp):
            bad.append("%s SDP sin AMR-WB/16000 + AMR/8000" % m.ref())
    R.add("C2", "TS 26.114 §5.2.1.2 / §6.2.2",
          "Oferta SDP del UE (MTSI) incluye AMR-WB/16000, AMR/8000 y telephone-event",
          bool(inv_ue) and not bad, bad[:5] or ["%d ofertas SDP con AMR/AMR-WB" % len(inv_ue)])
    inv_mw = [m for m in msgs if m.method == "INVITE" and NODES.get(m.src) == "P-CSCF" and not m.is_gm()
              and ";tag=" not in (m.h("to") or "")]
    bad = []
    for m in inv_mw:
        miss = [h for h in ("p-asserted-identity", "p-charging-vector", "record-route") if not m.h(h)]
        if m.h("p-preferred-identity"):
            miss.append("P-Preferred-Identity no retirada")
        if "icid-value" not in (m.h("p-charging-vector") or ""):
            miss.append("icid-value")
        if miss:
            bad.append("%s %s" % (m.ref(), ", ".join(miss)))
    R.add("C3", "TS 24.229 §5.2.6.3.3 / §5.2.7 / RFC 3325 / RFC 7315",
          "INVITE P-CSCF→core: P-Asserted-Identity (sin PPI), P-Charging-Vector icid-value y Record-Route",
          bool(inv_mw) and not bad, bad[:5] or ["%d INVITE en Mw conformes" % len(inv_mw)])
    isc = [m for m in msgs if m.method in ("INVITE", "SUBSCRIBE") and NODES.get(m.src) == "S-CSCF"
           and NODES.get(m.dst) == "AS-Front" and ";tag=" not in (m.h("to") or "")]
    bad = []
    for m in isc:
        routes = ",".join(m.hall("route"))
        if not m.h("p-asserted-identity") or not m.h("p-served-user") or "asfront" not in routes or "scscf" not in routes:
            bad.append("%s PAI=%s PSU=%s Route=%s" % (m.ref(), m.h("p-asserted-identity"), m.h("p-served-user"), routes))
    R.add("C4", "TS 24.229 §5.4.3.2 / §5.4.3.3 / RFC 5502",
          "ISC (S-CSCF→AS): Route = AS + S-CSCF (ODI), P-Asserted-Identity y P-Served-User",
          bool(isc) and not bad, bad[:5] or ["%d peticiones ISC conformes" % len(isc)])
    term = [m for m in msgs if m.method == "INVITE" and NODES.get(m.src) == "S-CSCF" and NODES.get(m.dst) == "AS-Front"
            and "sescase=term" in (m.h("p-served-user") or "") and "regstate=unreg" in (m.h("p-served-user") or "")]
    R.add("C5", "TS 23.218 §6 / TS 29.228 Anexo B (SessionCase 2) / TS 24.604",
          "Llamada a usuario no registrado desviada por iFC terminating-unregistered al AS de buzón",
          bool(term), [t.ref() + " P-Served-User=" + (t.h("p-served-user") or "") for t in term[:3]] or ["sin INVITE terminating-unregistered hacia el AS"])

    # ---------------------------------------------------------------- M ---
    subs_ue = [m for m in gm if m.from_ue() and m.method == "SUBSCRIBE" and "message-summary" in (m.h("event") or "")]
    bad = []
    for m in subs_ue:
        to = re.search(r"sip:[^>;]+", m.h("to") or "")
        if not m.h("expires") or not to or not (m.ruri or "").startswith(to.group(0)):
            bad.append("%s R-URI=%s To=%s Expires=%s" % (m.ref(), m.ruri, m.h("to"), m.h("expires")))
    R.add("M1", "TS 24.606 §4.5.2 / RFC 3842 §3",
          "SUBSCRIBE del UE: Event: message-summary al propio IMPU con Expires",
          bool(subs_ue) and not bad, bad[:5] or ["%d SUBSCRIBE MWI conformes" % len(subs_ue)])
    sub_isc = [m for m in isc if m.method == "SUBSCRIBE"]
    R.add("M2", "TS 24.606 §4.5.2 / TS 29.228 Anexo B",
          "SUBSCRIBE MWI enrutado por iFC (ISC) al AS de buzón",
          bool(sub_isc), [m.ref() for m in sub_isc[:3]] or ["sin SUBSCRIBE en ISC"])
    nots = [m for m in gm if m.to_ue() and m.method == "NOTIFY" and "message-summary" in (m.h("event") or "")]
    bad = []
    for m in nots:
        if not m.h("subscription-state") or "application/simple-message-summary" not in (m.h("content-type") or "") \
                or not re.search(r"Messages-Waiting:\s*(yes|no)", m.body, re.I) or ";tag=" not in (m.h("to") or ""):
            bad.append(m.ref())
    waiting = sorted({re.search(r"Messages-Waiting:\s*(\w+)", m.body, re.I).group(1).lower()
                      for m in nots if re.search(r"Messages-Waiting:\s*(\w+)", m.body, re.I)})
    R.add("M3", "TS 24.606 §4.5.2 / RFC 3842 §5 / RFC 6665",
          "NOTIFY message-summary al UE dentro del diálogo (Subscription-State, simple-message-summary)",
          bool(nots) and not bad and "yes" in waiting, bad[:5] or ["%d NOTIFY MWI; Messages-Waiting=%s" % (len(nots), "/".join(waiting))])
    return R


def render(R, msgs, path):
    total = [r for r in R.rules if r["result"] != "N/A"]
    passed = [r for r in total if r["result"] == "PASS"]
    pct = 100.0 * len(passed) / len(total) if total else 0.0
    gm = [m for m in msgs if m.is_gm()]
    out = []
    out.append("# Verificación 3GPP — %s\n" % os.path.basename(path))
    out.append("| Métrica | Valor |\n|---|---|")
    out.append("| Mensajes SIP (deduplicados) | %d |" % len(msgs))
    out.append("| Mensajes en Gm (UE↔P-CSCF) | %d (ESP: %d) |" % (len(gm), sum(1 for m in gm if m.esp)))
    out.append("| Métodos | %s |" % ", ".join("%s=%d" % kv for kv in sorted(
        defaultdict(int, {k: sum(1 for m in msgs if m.method == k) for k in {m.method for m in msgs if m.method}}).items())))
    out.append("| Reglas aplicables | %d |" % len(total))
    out.append("| **Cumplimiento** | **%d/%d (%.1f %%)** |\n" % (len(passed), len(total), pct))
    out.append("| Regla | Especificación | Verificación | Resultado | Evidencia |\n|---|---|---|---|---|")
    for r in R.rules:
        ev = "<br>".join(str(e).replace("|", "\\|") for e in r["evidence"][:4])
        out.append("| %s | %s | %s | **%s** | %s |" % (r["id"], r["ref"], r["desc"], r["result"], ev))
    out.append("\nESTADO: %s" % ("CUMPLE 100 %" if len(passed) == len(total) else "NO CUMPLE"))
    return "\n".join(out), len(passed) == len(total)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("pcap")
    ap.add_argument("--json")
    a = ap.parse_args()
    msgs = parse_capture(a.pcap)
    R = check(msgs, load_subscribers())
    text, ok = render(R, msgs, a.pcap)
    print(text)
    if a.json:
        with open(a.json, "w") as f:
            json.dump(R.rules, f, indent=2, ensure_ascii=False)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
