#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# Sonda "UE IMS" que completa la autenticación 3GPP Digest-AKAv1-MD5
# (TS 33.203) contra la maqueta, demostrando de extremo a extremo:
#   - P-CSCF -> I-CSCF -> S-CSCF route REGISTER
#   - Cx MAR/MAA con vectores AKA reales (RAND||AUTN) generados por PyHSS
#   - respuesta Digest RFC 3310 (AKAv1-MD5) calculada con las claves USIM
#     (K, OPc, AMF) mediante Milenage f2 (XRES)
#   - identidades IMS correctas: IMPU = sip:<MSISDN>@dominio (From/To),
#     IMPI = <IMSI>@dominio (username de Authorization)
#   - cabeceras Gm: Security-Client (ipsec-3gpp), Contact con
#     +g.3gpp.icsi-ref / +g.3gpp.smsip, P-Access-Network-Info
#
# Uso (dentro de mims3_pyhss_hss, que incluye la lib milenage):
#   python3 /scripts/ue_aka_probe.py
import sys
import os
import socket
import base64
import hashlib
import random
import re
import argparse

sys.path.insert(0, "/opt/pyhss/lib")  # Milenage (S6a_crypt)
from milenage import Milenage  # noqa: E402


def md5hex(b: bytes) -> str:
    return hashlib.md5(b).hexdigest()


def rndhex(n: int = 8) -> str:
    return "".join(random.choice("0123456789abcdef") for _ in range(n))


def aka_auth(nonce_b64: str, impi: str, realm: str, uri: str, k: bytes,
             opc: bytes) -> tuple:
    """Calcula la respuesta Digest-AKAv1-MD5 (RFC 3310 / TS 33.203)."""
    challenge = base64.b64decode(nonce_b64)
    rand = challenge[:16]
    # el UE (USIM) obtiene RES=f2(K, RAND, OPc); el XRES del HSS usa el mismo f2
    res = Milenage.f2(k, rand, opc)
    nc = "00000001"
    cnonce = rndhex(16)
    ha1 = md5hex((impi + ":" + realm + ":").encode() + res)
    ha2 = md5hex(("REGISTER" + ":" + uri).encode())
    resp = md5hex((ha1 + ":" + nonce_b64 + ":" + nc + ":" + cnonce +
                   ":auth:" + ha2).encode())
    return resp, cnonce, nc


def wait_response(sock: socket.socket, timeout: float = 6.0):
    sock.settimeout(timeout)
    buf = b""
    while True:
        try:
            data, _ = sock.recvfrom(65535)
        except socket.timeout:
            break
        buf += data
        if b"\r\n\r\n" in buf:
            head, _, _ = buf.partition(b"\r\n\r\n")
            first = head.split(b"\r\n", 1)[0]
            status = re.match(rb"SIP/2.0 (\d{3})", first)
            if status and status.group(1) != b"100":
                break
    return buf


def build_register(cseq: int, branch: str, call_id: str, from_tag: str,
                   impu: str, contact_uri: str, security_client: str,
                   auth: str = "", preauth: str = ""):
    lines = [
        "REGISTER " + uri + " SIP/2.0",
        "Via: SIP/2.0/UDP %s:%d;rport;branch=%s" % (my_ip, my_port, branch),
        "Max-Forwards: 70",
        "From: <%s>;tag=%s" % (impu, from_tag),
        "To: <%s>" % impu,
        "Call-ID: %s" % call_id,
        "CSeq: %d REGISTER" % cseq,
        "Contact: %s;+g.3gpp.icsi-ref=\"urn%%3Aurn-7%%3A3gpp-service.ims.icsi.mmtel\";+g.3gpp.smsip" % contact_uri,
        "Expires: 3600",
        "Security-Client: %s" % security_client,
        "P-Access-Network-Info: 3GPP-E-UTRAN-FDD; utran-cell-id-3gpp=0020100000f101",
    ]
    if auth:
        lines.insert(7, "Authorization: Digest " + auth)
    elif preauth:
        # TS 24.229 §5.1.1.1.2: el primer REGISTER lleva el IMPI (identidad
        # privada) en un Authorization "pre-auth" para que el I-CSCF pueda
        # resolver el UAR por IMSI (no por la identidad pública).
        lines.insert(7, "Authorization: Digest " + preauth)
    lines += ["Content-Length: 0", "", ""]
    return "\r\n".join(lines)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--contact-ip", default=None)
    ap.add_argument("--imsi", default="001011234567890")
    ap.add_argument("--msisdn", default="0010100001")
    ap.add_argument("--ki", default="8baf473f2f8fd09487cccbd7097c6862")
    ap.add_argument("--opc", default="61f0f589e23b2bd9c35fe9f2d09db0c1")
    ap.add_argument("--domain", default="ims.mnc001.mcc001.3gppnetwork.org")
    ap.add_argument("--pcscf", default="172.32.0.8")
    args = ap.parse_args()

    domain = args.domain
    pcscf = args.pcscf
    uri = "sip:%s:5060" % domain
    impi = "%s@%s" % (args.imsi, domain)
    impu = "sip:%s@%s" % (args.msisdn, domain)
    ki = bytes.fromhex(args.ki)
    opc = bytes.fromhex(args.opc)

    so = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    so.setblocking(True)
    my_port = 15060
    so.bind(("0.0.0.0", my_port))
    my_ip = (args.contact_ip or
             socket.gethostbyname(socket.gethostname()).split()[0])
    branch = "z9hG4bK-aka-" + rndhex(12)
    call_id = "aka-%s@%s" % (rndhex(8), my_ip)
    from_tag = rndhex(10)
    sc = ("ipsec-3gpp; alg=hmac-sha-1-96; spi-c=23456789; spi-s=12345678; "
          "port-c=%d; port-s=%d" % (my_port, my_port))

    contact = "<sip:%s@%s:%d>" % (args.msisdn, my_ip, my_port)

    preauth = ('username="%s", realm="%s", nonce="", uri="%s", response=""' % (
        impi, domain, uri))
    print("== 1er REGISTER (pre-auth con IMPI) ->", uri)
    so.sendto(build_register(1, branch, call_id, from_tag, impu, contact, sc,
                            preauth=preauth).encode(), (pcscf, 5060))
    buf = wait_response(so)
    head = buf.decode(errors="replace")
    print(head.split("\r\n\r\n")[0])
    m = re.search(r'nonce="([^"]+)"', head)
    realm = re.search(r'realm="([^"]+)"', head)
    if not m:
        print("ERROR: sin nonce AKA en el 401")
        sys.exit(1)
    nonce_b64 = m.group(1)
    realm = realm.group(1) if realm else domain
    print("\n## nonce = RAND||AUTN (base64) =", nonce_b64)
    chal = base64.b64decode(nonce_b64)
    print("## RAND + AUTN (%d bytes) -> calculando RES via Milenage f2..." % len(chal))

    resp, cnonce, nc = aka_auth(nonce_b64, impi, realm, uri, ki, opc)
    auth = ('username="%s", realm="%s", nonce="%s", uri="%s", '
            'response="%s", algorithm=AKAv1-MD5, cnonce="%s", qop=auth, '
            'nc=%s' % (impi, realm, nonce_b64, uri, resp, cnonce, nc))
    print("\n== 2o REGISTER (con respuesta Digest-AKAv1-MD5)")
    branch2 = "z9hG4bK-aka-" + rndhex(12)
    so.sendto(build_register(2, branch2, call_id, from_tag, impu, contact, sc, auth).encode(),
              (pcscf, 5060))
    buf = wait_response(so)
    print(buf.decode(errors="replace").split("\r\n\r\n")[0])
    if b"200 OK" in buf:
        print("\nRESULTADO: AUTHENTICACION AKAv1-MD5 COMPLETADA (200 OK)")
        sys.exit(0)
    else:
        print("\nRESULTADO: FALLO, revisar logs P/S-CSCF")
        sys.exit(1)