#!/usr/bin/env python3
"""loadgen.py — generador de carga SIP/RTP para la maqueta IMS en DEV (Swarm).

Cada UE virtual es un abonado de carga (perfil no-3GPP, SIP Digest MD5 por TCP)
que entra por el P-CSCF externo, igual que un softphone por VPN:
  REGISTER (401 -> 200) -> bucle de llamadas INVITE -> 200 -> ACK -> RTP PCMU
  durante HOLD s (tono, tramas de 20 ms) -> BYE -> pausa -> ... -> baja.

Uso:
  loadgen.py --proxy 192.168.5.231 --ues ues.csv --concurrency 20 \
             --dest 0100002 --hold 30 --duration 120 --out resultados.jsonl
  loadgen.py --register-only ...   (ráfaga de registros, sin llamadas)

ues.csv: líneas "msisdn,password" (la contraseña Digest es la Ki en PyHSS).
Salida: un JSON por evento (register / call) con tiempos y contadores RTP.
"""
import argparse, hashlib, json, math, random, re, socket, struct, sys, threading, time

DOM = "ims.mnc001.mcc001.3gppnetwork.org"


def ulaw(x):
    x = max(-32635, min(32635, int(x))); sign = 0x80 if x < 0 else 0; x = abs(x) + 132
    exp = max(0, min(7, int(math.log2(x)) - 7 if x > 255 else 0))
    return ~(sign | (exp << 4) | ((x >> (exp + 3)) & 0x0F)) & 0xFF


# 50 tramas de tono de 440 Hz precalculadas (1 s): el bucle RTP solo empaqueta
FRAMES = [bytes(ulaw(9000 * math.sin(2 * math.pi * 440 * (n * 160 + i) / 8000)) for i in range(160))
          for n in range(50)]


class UE:
    def __init__(self, proxy, user, pwd, log):
        self.proxy, self.user, self.pwd, self.log = proxy, user, pwd, log
        self.impi = f"{user}@{DOM}"
        self.buf = b""

    # ---------- transporte ----------
    def connect(self):
        self.s = socket.create_connection((self.proxy, 5060), timeout=15)
        self.lip, self.lport = self.s.getsockname()
        self.callid, self.tag = f"{random.getrandbits(48):x}@{self.lip}", f"{random.getrandbits(32):x}"

    def recv_msg(self):
        while True:
            m = self.buf.find(b"\r\n\r\n")
            if m >= 0:
                head = self.buf[:m + 4].decode(errors="replace")
                cl = int(re.search(r"Content-Length: *(\d+)", head, re.I).group(1))
                if len(self.buf) >= m + 4 + cl:
                    body = self.buf[m + 4:m + 4 + cl].decode(errors="replace")
                    self.buf = self.buf[m + 4 + cl:]
                    return head, body
            d = self.s.recv(65535)
            if not d:
                raise ConnectionError("TCP cerrado por el servidor")
            self.buf += d

    def final(self, method):
        """Primera respuesta final a `method`; responde 200 a peticiones entrantes (OPTIONS/NOTIFY)."""
        while True:
            h, b = self.recv_msg()
            if h.startswith("SIP/2.0"):
                if re.search(rf"^CSeq: *\d+ {method}", h, re.M | re.I) and not h.startswith("SIP/2.0 1"):
                    return h, b
            else:
                self.reply_200(h)

    def reply_200(self, h):
        hs = [l for l in h.split("\r\n") if re.match(r"(Via|From|To|Call-ID|CSeq):", l, re.I)]
        self.s.sendall(("SIP/2.0 200 OK\r\n" + "\r\n".join(hs) + "\r\nContent-Length: 0\r\n\r\n").encode())

    def via(self):
        return f"Via: SIP/2.0/TCP {self.lip}:{self.lport};rport;branch=z9hG4bK{random.getrandbits(40):x}\r\n"

    def auth(self, head, method, uri):
        p = dict(re.findall(r'(\w+)="?([^",\r]*)"?', re.search(r"WWW-Authenticate: *Digest (.*)", head, re.I).group(1)))
        ha1 = hashlib.md5(f"{self.impi}:{p['realm']}:{self.pwd}".encode()).hexdigest()
        ha2 = hashlib.md5(f"{method}:{uri}".encode()).hexdigest()
        cn = f"{random.getrandbits(32):08x}"
        r = hashlib.md5(f"{ha1}:{p['nonce']}:00000001:{cn}:auth:{ha2}".encode()).hexdigest()
        return (f'Authorization: Digest username="{self.impi}", realm="{p["realm"]}", nonce="{p["nonce"]}", '
                f'uri="{uri}", response="{r}", algorithm=MD5, qop=auth, nc=00000001, cnonce="{cn}"\r\n')

    # ---------- registro ----------
    def register(self, expires=600):
        t0 = time.time(); self.cseq = getattr(self, "cseq", 0)
        def send(auth=""):
            self.cseq += 1
            self.s.sendall((f"REGISTER sip:{DOM} SIP/2.0\r\n{self.via()}Max-Forwards: 70\r\n"
                            f"From: <sip:{self.user}@{DOM}>;tag={self.tag}\r\nTo: <sip:{self.user}@{DOM}>\r\n"
                            f"Call-ID: {self.callid}\r\nCSeq: {self.cseq} REGISTER\r\n"
                            f"Contact: <sip:{self.user}@{self.lip}:{self.lport};transport=tcp>\r\nExpires: {expires}\r\n"
                            f"{auth}Content-Length: 0\r\n\r\n").encode())
            return self.final("REGISTER")[0]
        h = send()
        if h.startswith("SIP/2.0 401"):
            h = send(self.auth(h, "REGISTER", f"sip:{DOM}"))
        code = int(h.split()[1])
        if expires:
            self.log({"ev": "register", "ue": self.user, "code": code, "ms": round((time.time() - t0) * 1000, 1)})
        return code == 200

    # ---------- llamada ----------
    def call(self, dest, hold):
        rtp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); rtp.bind(("0.0.0.0", 0)); rtp.setblocking(False)
        rpl = rtp.getsockname()[1]
        icid, itag, ruri = f"c{random.getrandbits(40):x}-{self.callid}", f"i{random.getrandbits(32):x}", f"sip:{dest}@{DOM}"
        sdp = (f"v=0\r\no=- 1 1 IN IP4 {self.lip}\r\ns=-\r\nc=IN IP4 {self.lip}\r\nt=0 0\r\n"
               f"m=audio {rpl} RTP/AVP 0 101\r\na=rtpmap:0 PCMU/8000\r\na=rtpmap:101 telephone-event/8000\r\na=sendrecv\r\n")
        ev = {"ev": "call", "ue": self.user, "dest": dest}
        t0 = time.time()
        self.s.sendall((f"INVITE {ruri} SIP/2.0\r\n{self.via()}Max-Forwards: 70\r\nFrom: <sip:{self.user}@{DOM}>;tag={itag}\r\n"
                        f"To: <{ruri}>\r\nCall-ID: {icid}\r\nCSeq: 1 INVITE\r\n"
                        f"Contact: <sip:{self.user}@{self.lip}:{self.lport};transport=tcp>\r\n"
                        f"Route: <sip:{self.proxy}:5060;transport=tcp;lr>\r\nContent-Type: application/sdp\r\n"
                        f"Content-Length: {len(sdp)}\r\n\r\n{sdp}").encode())
        h, body = self.final("INVITE")
        ev["code"] = int(h.split()[1]); ev["setup_ms"] = round((time.time() - t0) * 1000, 1)
        if ev["code"] != 200:
            rtp.close(); self.log(ev); return False
        rip = re.search(r"c=IN IP4 ([\d.]+)", body).group(1); rp = int(re.search(r"m=audio (\d+)", body).group(1))
        ev["media"] = f"{rip}:{rp}"
        totag = re.search(r"^To:.*?(;tag=[^;\r\n]+)", h, re.M | re.I).group(1)
        rr = ",".join(x.strip() for x in re.findall(r"^Record-Route: *(.*)$", h, re.M | re.I))
        route = "".join(f"Route: {r.strip()}\r\n" for r in reversed(rr.split(","))) if rr else ""
        contact = re.search(r"^Contact: *<([^>]+)>", h, re.M | re.I).group(1)

        def indialog(method, cseq):
            self.s.sendall((f"{method} {contact} SIP/2.0\r\n{self.via()}Max-Forwards: 70\r\n"
                            f"From: <sip:{self.user}@{DOM}>;tag={itag}\r\nTo: <{ruri}>{totag}\r\nCall-ID: {icid}\r\n"
                            f"CSeq: {cseq} {method}\r\n{route}Content-Length: 0\r\n\r\n").encode())
        indialog("ACK", "1")
        seq, ts, ssrc, sent, got, n = random.getrandbits(16), 0, random.getrandbits(32), 0, 0, 0
        first_rx = None; t1 = time.time()
        while time.time() - t1 < hold:
            rtp.sendto(struct.pack("!BBHII", 0x80, 0, seq & 0xFFFF, ts & 0xFFFFFFFF, ssrc) + FRAMES[n % 50], (rip, rp))
            seq += 1; ts += 160; n += 1; sent += 1
            try:
                while True:
                    rtp.recvfrom(2048); got += 1
                    if first_rx is None:
                        first_rx = round((time.time() - t1) * 1000, 1)
            except (BlockingIOError, ConnectionRefusedError):
                pass
            time.sleep(max(0, t1 + n * 0.02 - time.time()))
        indialog("BYE", "2")
        try:
            hb, _ = self.final("BYE"); ev["bye"] = int(hb.split()[1])
        except Exception as e:  # noqa: BLE001
            ev["bye"] = f"error: {e}"
        rtp.close()
        ev.update(rtp_tx=sent, rtp_rx=got, rx_first_ms=first_rx,
                  rx_ratio=round(got / sent, 3) if sent else 0)
        self.log(ev)
        return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--proxy", required=True); ap.add_argument("--ues", required=True)
    ap.add_argument("--concurrency", type=int, default=10); ap.add_argument("--dest", default="0100002")
    ap.add_argument("--hold", type=float, default=30); ap.add_argument("--duration", type=float, default=120)
    ap.add_argument("--gap", type=float, default=2); ap.add_argument("--out", required=True)
    ap.add_argument("--register-only", action="store_true"); ap.add_argument("--label", default="")
    a = ap.parse_args()
    ues = [l.strip().split(",") for l in open(a.ues) if l.strip()][:a.concurrency]
    lock, out = threading.Lock(), open(a.out, "a")

    def log(ev):
        ev["t"] = round(time.time(), 3); ev["label"] = a.label
        with lock:
            out.write(json.dumps(ev) + "\n"); out.flush()

    stop_at = time.time() + a.duration

    def worker(i, user, pwd):
        time.sleep(i * 0.2)  # rampa: 5 UEs nuevos por segundo
        ue = UE(a.proxy, user, pwd, log)
        try:
            ue.connect()
            if not ue.register() or a.register_only:
                return
            while time.time() < stop_at:
                ue.call(a.dest, a.hold)
                time.sleep(a.gap)
        except Exception as e:  # noqa: BLE001
            log({"ev": "error", "ue": user, "error": repr(e)[:200]})
        finally:
            try:
                ue.register(expires=0); ue.s.close()
            except Exception:  # noqa: BLE001
                pass

    th = [threading.Thread(target=worker, args=(i, u, p), daemon=True) for i, (u, p) in enumerate(ues)]
    [t.start() for t in th]; [t.join(a.duration + a.hold + 60) for t in th]
    out.close()


if __name__ == "__main__":
    sys.exit(main())
