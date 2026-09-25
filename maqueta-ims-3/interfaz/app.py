#!/usr/bin/env python3
"""Interfaz de operación de la maqueta Core IMS.

Backend Flask que usa el socket de Docker para:
  - estado de los contenedores / DNS / listeners SIP
  - prueba E2E (registro IMS + llamada al AS con IVR)
  - acciones (registrar UEs, llamada de prueba, detener)
  - configuración de suscriptores (lectura + provisionado en PyHSS)
  - consulta de logs de los nodos
"""
import io
import json
import math
import os
import re
import struct
import tarfile
import time
import wave

import docker
import requests
from flask import Flask, Response, jsonify, request, send_from_directory

DOMAIN = os.environ.get("IMS_DOMAIN", "ims.mnc001.mcc001.3gppnetwork.org")
PCSCF_IP = os.environ.get("PCSCF_IP", "172.32.0.8")
PYHSS_IP = os.environ.get("PYHSS_IP", "172.32.0.5")
PYHSS_API = f"http://{PYHSS_IP}:8080"

SOFTPHONE = "mims3_softphone"
FREESWITCH = "mims3_freeswitch"
ASFRONT = "mims3_asfront"
PCSCF = "mims3_pcscf"
PYHSS_HSS = "mims3_pyhss_hss"

VM_MAILBOX = "0100003"
VMS_DIR = "/var/lib/freeswitch/storage/vms"
# Silencio inicial que el AS reproduce antes de empezar a grabar (Answer ->
# Sleep ~1s -> grabación) ≈ 1-2 s desde CONFIRMED. El padding coloca el
# contenido justo cuando arranca la grabación del mensaje.
PROMPT_PAD_S = 2

CONTAINERS = [
    "mims3_dns", "mims3_mysql", "mims3_redis", "mims3_pyhss_api",
    "mims3_pyhss_hss", "mims3_pyhss_diameter", "mims3_icscf",
    "mims3_scscf", "mims3_pcscf", "mims3_rtpengine", "mims3_asfront",
    "mims3_freeswitch", "mims3_softphone", "mims3_ui",
]

LISTENERS = [  # (contenedor, puerto, comando_para_comprobar, patrón)
    ("mims3_scscf", "6060", "ss -lun", ":6060 "),
    ("mims3_icscf", "4060", "ss -lun", ":4060 "),
    ("mims3_pcscf", "5060", "ss -lun", ":5060 "),
    ("mims3_asfront", "5060", "ss -lun", ":5060 "),
    ("mims3_freeswitch", "5060", "ss -lun", ":5060 "),
]

BASE_ARGS = f" --realm {DOMAIN} --no-tcp --null-audio --log-level 4 "

DEFAULT_UES = {
    "1": {"imsi": "001011234567890", "msisdn": "0010100001",
          "display": "0010100001", "ki": "8baf473f2f8fd09487cccbd7097c6862",
          "port": "5061", "log": "pj1.log"},
    "2": {"imsi": "001011234567891", "msisdn": "0010100002",
          "display": "0010100002", "ki": "2a6ab8297e0d15c7a12eef0d8a12b143",
          "port": "5062", "log": "pj2.log"},
}

CONFIG_DIR = "/var/lib/ims-ui"
CONFIG_FILE = os.path.join(CONFIG_DIR, "config.json")

user = os.environ.get("USER", "root")
if user == "root":
    try:
        client = docker.from_env()
    except Exception:
        client = None
else:
    client = None

app = Flask(__name__)


# ---------- helpers ----------
def docker_ok():
    return client is not None


def sh(ct, cmd, timeout=15):
    """Ejecuta un comando dentro de un contenedor y devuelve (exit_code, salida)."""
    try:
        r = client.containers.get(ct).exec_run(["sh", "-c", cmd])
        return r.exit_code, r.output.decode(errors="replace")
    except Exception as e:  # noqa: BLE001
        return 1, f"ERROR: {e}"


def wait_for(ct, log, pattern, timeout_s):
    t0 = time.time()
    while time.time() - t0 < timeout_s:
        rc, out = sh(ct, f"grep -a '{pattern}' /tmp/{log}")
        if rc == 0:
            return True, out.strip().splitlines()[-1]
        time.sleep(1)
    return False, ""


def registered(log):
    """Detecta registro exitoso en /tmp/<log>: llegada del 200/REGISTER autenticado + Service-Route."""
    rc, _ = sh(SOFTPHONE, f"grep -a 'Response msg 200/REGISTER' /tmp/{log} && grep -a 'Service-Route' /tmp/{log}")
    return rc == 0


def ue_call(ue, dest, log="pjC.log"):
    """Llamada determinista: pjsua registra; un escritor retrasado por el pipe ordena
    la llamada ('m') en cuanto el REGISTER recibe 200 OK. Si la URI se pasa al
    arrancar, pjsua llama antes de registrar y el S-CSCF responde 403
    'You must register first with a S-CSCF'. La consola de pjsua solo procesa
    comandos vía pipe (no vía FIFO), y el 'sleep' evita el hangup por EOF."""
    c = load_config()[ue]
    kill_sip()
    launcher = (f"( until grep -aq 'Response msg 200/REGISTER' /tmp/{log} "
                f"2>/dev/null; do sleep 0.2; done; echo m; sleep 0.5; "
                f"echo 'sip:{dest}@{DOMAIN}'; sleep 20 ) | "
                f"pjsua --id sip:{c['imsi']}@{DOMAIN} --registrar sip:{DOMAIN}:5060"
                f"{BASE_ARGS}--username {c['imsi']} --password {c['ki']}"
                f" --local-port {c['port']} "
                f"--outbound=sip:{PCSCF_IP}:5060\\;lr "
                f"> /tmp/{log} 2>&1 &")
    sh(SOFTPHONE, f"rm -f /tmp/{log}; {launcher}")
    confirmed, _ = wait_for(SOFTPHONE, log, "Call 0 state changed to CONFIRMED", 25)
    rc, out = sh(SOFTPHONE, f"grep -aq 'Response msg 200/REGISTER' /tmp/{log}")
    reg_ok = rc == 0
    kill_sip()
    return reg_ok, confirmed


def launch_pjsua(ue, extra=""):
    c = DEFAULT_UES[ue]
    # IMPORTANTE: tail -f /dev/null mantiene el stdin abierto; si pjsua recibe EOF
    # (comando lanzado con & sin redirección) cuelga la llamada en curso.
    cmd = (f"tail -f /dev/null | pjsua --id sip:{c['imsi']}@{DOMAIN} --registrar sip:{DOMAIN}:5060"
           f"{BASE_ARGS}--username {c['imsi']} --password {c['ki']}"
           f" --local-port {c['port']} {extra} > /tmp/{c['log']} 2>&1 &")
    sh(SOFTPHONE, "pkill -9 -f pjsua; sleep 1", timeout=10)
    return sh(SOFTPHONE, cmd, timeout=10)


def kill_sip():
    sh(SOFTPHONE, "pkill -9 -f pjsua", timeout=10)


# ---------- helpers VMS ----------
def vms_count(mailbox=VM_MAILBOX):
    """Número de mensajes de voz (msg*.wav) en la bandeja INBOX del buzón."""
    rc, out = sh(FREESWITCH,
                 f"ls {VMS_DIR}/{mailbox}/INBOX/msg*.wav 2>/dev/null | wc -l")
    try:
        return int(out.strip() or 0)
    except ValueError:
        return 0


def vms_messages(mailbox=VM_MAILBOX):
    """Lista de mensajes (msg*.wav) con metadatos para el reproductor.

    Con `format=wav` las grabaciones son PCM16 lineal a 8 kHz mono: la duración
    aproximada es ≈ bytes/16000. El listado se parsea de `ls -l
    --time-style=+%Y-%m-%dT%H:%M:%S`."""
    rc, out = sh(FREESWITCH,
                 f"ls -l --time-style=+%Y-%m-%dT%H:%M:%S "
                 f"{VMS_DIR}/{mailbox}/INBOX/msg*.wav 2>/dev/null")
    messages = []
    for line in out.splitlines():
        parts = line.split()
        if len(parts) < 7:
            continue
        try:
            size = int(parts[4])
        except ValueError:
            continue
        name = parts[-1].rsplit("/", 1)[-1]
        if not name.lower().endswith(".wav"):
            continue
        # PCM16 lineal 8 kHz mono: 16000 bytes/s + cabecera ~44
        messages.append({
            "name": name,
            "size": size,
            "modified": parts[5],
            "duration_s": round(max(size - 44, 0) / 16000),
        })
    messages.sort(key=lambda it: it["modified"], reverse=True)
    return messages


def vms_read_file(mailbox, msg):
    """Devuelve los bytes del audio de un mensaje (o None si no existe)."""
    path = f"{VMS_DIR}/{mailbox}/INBOX/{msg}"
    try:
        r = client.containers.get(FREESWITCH).exec_run(["cat", path])
        return r.output if r.exit_code == 0 else None
    except Exception:  # noqa: BLE001
        return None


def inject_wav(name, data):
    """Inyecta un WAV (bytes) en /tmp/<name> dentro del softphone (put_archive).

    Reutilizado por ensure_tone() (tono determinista) y por el alta de un mensaje
    grabado/exportado desde la web (POST /api/vms/audio)."""
    tf = io.BytesIO()
    with tarfile.open(fileobj=tf, mode="w") as tar:
        ti = tarfile.TarInfo(name)
        ti.size = len(data)
        tar.addfile(ti, io.BytesIO(data))
    tf.seek(0)
    try:
        client.containers.get(SOFTPHONE).put_archive("/tmp", tf)
        return True
    except Exception:  # noqa: BLE001
        return False


def pad_wav_start(data, pad_s):
    """Antepone <pad_s> s de silencio (PCM16 8 kHz mono) a un WAV para que el
    mensaje no se pierda mientras el AS reproduce los prompts antes de grabar.
    Devuelve los bytes del WAV ajustado."""
    try:
        with wave.open(io.BytesIO(data), "rb") as w:
            frames = w.readframes(w.getnframes())
            nch = w.getnchannels()
            rate = w.getframerate()
    except Exception:  # noqa: BLE001
        return data
    out = io.BytesIO()
    with wave.open(out, "wb") as w:
        w.setnchannels(nch)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(b"\x00\x00" * (pad_s * rate))
        w.writeframes(frames)
    return out.getvalue()


def ensure_tone():
    """Garantiza /tmp/left_msg.wav (tono de 45 s, 8 kHz) dentro del softphone.

    La grabación necesita audio RTP real; con --null-audio pjsua no genera sonido
    y la app VoiceMail aborta ('Recording was 0 seconds long'). El archivo se
    genera en memoria y se inyecta con put_archive (el softphone no tiene python).
    Se regenera si falta o si su tamaño no corresponde a 45 s (720044 B): evita
    que un mensaje web sobrescrito contamine el test determinado."""
    if sh(SOFTPHONE, "test -f /tmp/left_msg.wav")[0] == 0 and \
            sh(SOFTPHONE, "test $(wc -c < /tmp/left_msg.wav) -eq 720044")[0] == 0:
        return True
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(8000)
        raw = bytearray()
        for i in range(8000 * 45):
            t = i / 8000
            v = int(9000 * math.sin(2 * math.pi * 420 * t) *
                    (0.9 if int(t * 2) % 2 else 0.35))
            raw += struct.pack("<h", v)
        w.writeframes(bytes(raw))
        data = buf.getvalue()
    return inject_wav("left_msg.wav", data)


def vms_call(ue="1", mailbox=VM_MAILBOX, log="pjV.log", say_ms=None):
    """Prueba E2E de buzón: registra el UE y llama a <mailbox>@dominio con audio
    real (tono). Devuelve (llamada_confirmada, mensaje_guardado, antes, después).

    `say_ms` (duración del wav web, en ms) recorta el tiempo de grabación:
    con el tono fijo se graban ~14 s; con un mensaje web se cuelga dur+6 s
    (los prompts `vm-*` consumen ~4 s antes de empezar a grabar)."""
    c = load_config()[ue]
    before = vms_count(mailbox)
    kill_sip()
    # El mensaje web vive en /tmp/web_msg.wav (no toca el tono left_msg.wav),
    # así la prueba E2E determinista sigue usando siempre el tono de 45 s.
    play = "/tmp/web_msg.wav" if say_ms else "/tmp/left_msg.wav"
    if not say_ms:
        ensure_tone()
    # s hablando antes de colgar: determinista 18; web = padding(≈10s de prompts)
    # + duración + holgura
    talk = round(say_ms / 1000) + PROMPT_PAD_S + 3 if say_ms else 18
    launcher = (f"( until grep -aq 'Response msg 200/REGISTER' /tmp/{log} "
                f"2>/dev/null; do sleep 0.2; done; echo m; sleep 0.7; "
                f"echo 'sip:{mailbox}@{DOMAIN}'; sleep {talk}; echo h; sleep 4 ) | "
                f"pjsua --id sip:{c['imsi']}@{DOMAIN} --registrar sip:{DOMAIN}:5060"
                f"{BASE_ARGS}--username {c['imsi']} --password {c['ki']}"
                f" --local-port {c['port']} "
                f"--play-file {play} --auto-play "
                f"--outbound=sip:{PCSCF_IP}:5060\\;lr "
                f"> /tmp/{log} 2>&1 &")
    sh(SOFTPHONE, f"rm -f /tmp/{log}; {launcher}")
    confirmed, _ = wait_for(SOFTPHONE, log, "Call 0 state changed to CONFIRMED", 25)
    # La secuencia del pipe (saludo -> grabación -> h) continúa sola: se espera a
    # que la app guarde el mensaje en la bandeja.
    after = before
    t0 = time.time()
    while after == before and time.time() - t0 < 60:
        time.sleep(3)
        after = vms_count(mailbox)
    kill_sip()
    return confirmed, after > before, before, after


def load_config():
    cfg = dict(DEFAULT_UES)
    try:
        with open(CONFIG_FILE) as f:
            saved = json.load(f)
        for k in saved:
            if k in cfg:
                cfg[k].update(saved[k])
    except (OSError, ValueError, json.JSONDecodeError):  # noqa: S110
        pass
    return cfg


def save_config(cfg):
    os.makedirs(CONFIG_DIR, mode=0o755, exist_ok=True)
    try:
        with open(CONFIG_FILE, "w") as f:
            json.dump(cfg, f, indent=2)
        return True
    except OSError:
        return False


def result(ok, name, detail=""):
    return {"status": "PASS" if ok else "FAIL", "name": name, "detail": detail}


# ---------- endpoints ----------
@app.get("/")
def index():
    return send_from_directory("static", "index.html")


@app.get("/health")
def health():
    return jsonify({"ok": docker_ok()}), (200 if docker_ok() else 503)


@app.get("/api/status")
def api_status():
    data = {"domain": DOMAIN, "containers": [], "dns": None, "listeners": []}
    if not docker_ok():
        return jsonify({"error": "Socket de Docker no disponible"}), 503
    for name in CONTAINERS:
        try:
            c = client.containers.get(name)
            state = c.attrs.get("State", {})
            data["containers"].append({
                "name": name,
                "running": state.get("Running", False),
                "status": c.status,
                "started": state.get("StartedAt", ""),
                "image": c.image.tags[0] if c.image.tags else "",
            })
        except Exception:  # noqa: BLE001
            data["containers"].append({"name": name, "running": False, "status": "not found"})
    rc, out = sh(SOFTPHONE, f"getent ahostsv4 {DOMAIN}")
    data["dns"] = {
        "domain": DOMAIN,
        "ip": out.splitlines()[0].split()[0] if rc == 0 and out.strip() else None,
        "expected": PCSCF_IP,
    }
    for name, port, cmd, pat in LISTENERS:
        rc, out = sh(name, cmd)
        data["listeners"].append({
            "container": name, "port": port, "up": rc == 0 and pat in out,
        })
    return jsonify(data)


@app.post("/api/test")
def api_test():
    if not docker_ok():
        return jsonify({"error": "Socket de Docker no disponible"}), 503
    results = []

    # 1. contenedores
    up = 0
    for name in CONTAINERS:
        try:
            if client.containers.get(name).attrs["State"]["Running"]:
                up += 1
        except Exception:  # noqa: BLE001
            pass
    results.append(result(up == len(CONTAINERS), "Contenedores arriba",
                          f"{up}/{len(CONTAINERS)}"))

    # 2. DNS
    rc, out = sh(SOFTPHONE, f"getent ahostsv4 {DOMAIN}")
    try:
        ip = out.splitlines()[0].split()[0]
    except IndexError:
        ip = None
    results.append(result(rc == 0 and ip == PCSCF_IP, "Resolución DNS",
                          f"{DOMAIN} -> {ip} (esperado {PCSCF_IP})"))

    # 3. listeners SIP/UDP
    for name, port, cmd, pat in LISTENERS:
        rc, out = sh(name, cmd)
        results.append(result(rc == 0 and pat in out, f"Listener {name}:{port}", f"via {cmd.split()[0]}"))

    # 4. registro IMS
    kill_sip()
    ues = load_config()
    for ue, tag in (("1", "UE1"), ("2", "UE2")):
        launch_pjsua(ue)
        ok, _ = wait_for(SOFTPHONE, ues[ue]["log"],
                         "Response msg 200/REGISTER", 20)
        ok = ok and sh(SOFTPHONE, f"grep -a 'Response msg 200/REGISTER' /tmp/{ues[ue]['log']}")[0] == 0
        if tag == "UE1":
            rc, out = sh(SOFTPHONE, f"grep -a '401 Unauthorized - Challenging the UE' /tmp/{ues['1']['log']} && grep -a 'Service-Route' /tmp/{ues['1']['log']}")
            ok = ok and rc == 0
            det = "401 -> 200 OK + Service-Route" if ok else "fallo (revisar paso_a_paso §15)"
        else:
            det = "200 OK" if ok else "fallo (revisar paso_a_paso §15)"
        results.append(result(ok, f"Registro IMS {tag}", det))
    kill_sip()

# 5. llamada al AS
    before = time.time()
    reg_ok, ok = ue_call("1", "0100002")
    results.append(result(ok, "Llamada UE1 -> AS (CONFIRMED)",
                          "registro previo " + ("OK" if reg_ok else "fallido") +
                          " · INVITE -> 100 -> 200 OK -> ACK" if ok else "no se confirmó el diálogo"))
    time.sleep(2)
    astdout = client.containers.get(FREESWITCH).logs(since=int(before)).decode(errors="replace")
    pcout = client.containers.get(PCSCF).logs(since=int(before)).decode(errors="replace")
    lab = f"durante los últimos {(time.time()-before):.0f}s"
    results.append(result("ivr_bienvenida.wav" in astdout,
                          "FreeSWITCH reproduce IVR", lab))
    results.append(result("RTPEngine engaged for Application Server" in pcout,
                          "RTPEngine engaged (P-CSCF)", lab))
    kill_sip()

    # 6. VMS: el UE1 deja un mensaje de voz en el buzón (iFC nuevo -> 0100003)
    vms_conf, vms_saved, vms_before, vms_after = vms_call("1", VM_MAILBOX)
    results.append(result(vms_conf, "VMS: llamada UE1 -> buzón (CONFIRMED)",
                          f"{VM_MAILBOX}@{DOMAIN} vía iFC"))
    results.append(result(vms_saved, "VMS: mensaje grabado en INBOX",
                          f"mensajes msg*.wav: {vms_before} -> {vms_after}"))
    kill_sip()

    ok_all = all(r["status"] == "PASS" for r in results)
    return jsonify({"results": results, "ok": ok_all})


@app.get("/api/config")
def api_config():
    return jsonify({"ues": load_config(), "domain": DOMAIN,
                    "ifc": {"file": "maqueta_ifc.xml",
                            "rule": f"INVITE + SessionCase 0 -> sip:asfront.{DOMAIN}:5060"},
                    "source": "entorno .env (persistido en config.json)"})


@app.post("/api/config")
def api_config_update():
    try:
        cfg = load_config()
        body = request.get_json(force=True)
        for k, v in body.items():
            if k in cfg:
                cfg[k].update({kk: str(vv) for kk, vv in v.items()})
        save_config(cfg)
        return jsonify({"ok": True, "ues": cfg})
    except Exception as e:  # noqa: BLE001
        return jsonify({"ok": False, "error": str(e)}), 400


@app.post("/api/config/provision")
def api_config_provision():
    """Provisiona los suscriptores UE1/UE2 en PyHSS (API REST + scscf en SQLite)."""
    cfg = load_config()
    out = []
    opc = "61f0f589e23b2bd9c35fe9f2d09db0c1"
    for ue, tag in (("1", "UE1"), ("2", "UE2")):
        c = cfg[ue]
        steps = [
            ("auc  (vector de autenticación)  → PyHSS API", "/auc/",
             {"ki": c["ki"], "opc": opc, "amf": "8000", "sqn": 7091}),
            ("subscriber  (EPS)  → PyHSS API", "/subscriber/",
             {"imsi": c["imsi"], "msisdn": c["msisdn"], "apn_list": ["internet"]}),
            ("ims_subscriber  (IMS + iFC)  → PyHSS API", "/ims_subscriber/",
             {"imsi": c["imsi"], "msisdn": c["msisdn"],
              "msisdn_list": c["msisdn"], "ifc_path": "maqueta_ifc.xml"}),
        ]
        for label, path, payload in steps:
            if label.startswith("ims_subscriber"):
                # El endpoint PUT de PyHSS no admite actualizar un suscriptor existente
                # (falla con UNIQUE) y su borrado usa la PK numérica (no msisdn).
                # Se hace un UPSERT directo en la BD (idempotente).
                continue
            try:
                r = requests.put(PYHSS_API + path, json=payload, timeout=10)
                detail = f"HTTP {r.status_code}" if r.ok else f"HTTP {r.status_code}: {r.text[:150]}"
                out.append({"tag": tag, "label": label, "ok": r.ok, "detail": detail})
            except Exception as e:  # noqa: BLE001
                out.append({"tag": tag, "label": label, "ok": False, "detail": f"ERROR: {e}"})
        # UPSERT de apn + auc + subscriber + ims_subscriber + scscf en SQLite
        # (idempotente). La API REST de PyHSS falla para subscriber con SQLite
        # ("type 'list' is not supported" en apn_list), así que se escribe la
        # lógica de provisión directamente en la BD (equivalente al antiguo
        # provision_hss.sql pero dirigido a la UI vía POST /api/config/provision).
        rc, sout = sh(PYHSS_HSS, """python3 <<'PYEOF'
import sqlite3
c = sqlite3.connect('/var/lib/pyhss/hss.db')
imsi, msisdn, ki = '%IMSI%', '%MSISDN%', '%KI%'

# APN por defecto (requerido por subscriber.default_apn)
c.execute("INSERT OR IGNORE INTO apn (apn, ip_version, apn_ambr_dl, apn_ambr_ul, charging_characteristics) VALUES ('internet', 0, 999999, 999999, '0800')")
apn_id = c.execute("SELECT apn_id FROM apn WHERE apn='internet'").fetchone()[0]

# auC (vector AKA: Ki + OPC + AMF + SQN. sqn/opc erróneos => PyHSS no puede
# generar vectores AKA y el S-CSCF respondía 504 en lugar de 401 AKAv1-MD5)
c.execute("DELETE FROM auc WHERE imsi=?", (imsi,))
c.execute("INSERT INTO auc (ki, opc, amf, sqn, imsi, algo) VALUES (?, ?, '8000', 7091, ?, '3')", (ki, '%OPC%', imsi))
auc_id = c.execute("SELECT auc_id FROM auc WHERE imsi=?", (imsi,)).fetchone()[0]

# subscriber (EPS)
c.execute("DELETE FROM subscriber WHERE imsi=?", (imsi,))
c.execute("INSERT INTO subscriber (imsi, enabled, auc_id, default_apn, apn_list, msisdn) VALUES (?, 1, ?, ?, 'internet', ?)",
          (imsi, auc_id, apn_id, msisdn))

# ims_subscriber (IMS + iFC)
scscf = 'sip:scscf.%DOMAIN%'; realm = '%DOMAIN%'
c.execute("DELETE FROM ims_subscriber WHERE imsi=? OR msisdn=?", (imsi, msisdn))
c.execute("INSERT INTO ims_subscriber (imsi,msisdn,msisdn_list,ifc_path,scscf,scscf_realm) VALUES (?,?,?,?,?,?)",
          (imsi, msisdn, msisdn, 'maqueta_ifc.xml', scscf, realm))
c.commit()
print('OK')
PYEOF
""".replace("%IMSI%", c["imsi"]).replace("%MSISDN%", c["msisdn"]).replace("%DOMAIN%", DOMAIN).replace("%KI%", c["ki"]).replace("%OPC%", opc))
        out.append({"tag": tag, "label": "ims_subscriber  (IMS + iFC)  → SQLite (UPSERT)",
                    "ok": rc == 0 and "OK" in sout, "detail": sout.strip() or "error"})
        rc, sout = sh(PYHSS_HSS, """python3 <<'PYEOF'
import sqlite3
c = sqlite3.connect('/var/lib/pyhss/hss.db')
scscf = 'sip:scscf.%DOMAIN%'; realm = '%DOMAIN%'
c.execute("UPDATE ims_subscriber SET scscf=?, scscf_realm=? WHERE imsi='%IMSI%'", (scscf, realm))
c.commit(); print('OK')
PYEOF
""".replace("%IMSI%", c["imsi"]).replace("%DOMAIN%", DOMAIN))
        out.append({"tag": tag, "label": "scscf asignado (SQLite)",
                    "ok": rc == 0 and "OK" in sout, "detail": sout.strip() or "error"})
    ok = all(r["ok"] for r in out)
    return jsonify({"ok": ok, "results": out})


@app.post("/api/actions/register")
def api_register():
    ue = request.get_json(force=True).get("ue", "1")
    c = load_config()[ue]
    launch_pjsua(ue)
    ok, _ = wait_for(SOFTPHONE, c["log"], "Response msg 200/REGISTER", 20)
    rc, out = sh(SOFTPHONE, f"cat /tmp/{c['log']}")
    lines = [ln for ln in out.splitlines()
             if any(k in ln for k in ("401 Unauthorized", "200/REGISTER",
                                      "Service-Route", "500 Server", "403 Forbidden", "404"))]
    ok = ok and sh(SOFTPHONE, f"grep -a 'Service-Route' /tmp/{c['log']}")[0] == 0
    return jsonify({"ok": ok, "ue": ue, "lines": lines[-12:]})


@app.post("/api/actions/call")
def api_call():
    body = request.get_json(force=True) if request.data else {}
    dest = body.get("dest", "0100002")
    ue = body.get("ue", "1")
    reg_ok, ok = ue_call(ue, dest)
    rc, out = sh(SOFTPHONE, "cat /tmp/pjC.log")
    lines = [ln for ln in out.splitlines()
             if any(k in ln for k in ("Making call", "Call 0 state", "200 OK", "SIP/2.0 401", "200/REGISTER"))]
    return jsonify({"ok": ok and reg_ok, "dest": dest, "ue": ue,
                    "registro": reg_ok, "lines": lines[-12:]})


@app.post("/api/actions/stop")
def api_stop():
    kill_sip()
    return jsonify({"ok": True, "detail": "Procesos pjsua detenidos"})


@app.get("/api/vms")
def api_vms():
    """Estado de los buzones, lista de mensajes y disponibilidad de prompts."""
    mailboxes = []
    for mb in ("0100002", "0100003"):
        cnt = vms_count(mb)
        mp = vms_messages(mb)
        mailboxes.append({"mailbox": mb, "messages": cnt,
                          "last": mp[0]["name"] if mp else None, "list": mp})
    rc, out = sh(FREESWITCH, "ls /mnt/freeswitch/ivr_bienvenida.wav 2>/dev/null")
    return jsonify({"mailboxes": mailboxes, "prompts": rc == 0})


@app.get("/api/vms/media")
def api_vms_media():
    """Streaming del audio de un mensaje (reproductor en la pestaña VMS)."""
    mailbox = request.args.get("mailbox", VM_MAILBOX)
    msg = os.path.basename(request.args.get("msg", ""))
    if not re.fullmatch(r"msg\d+\.wav", msg.lower()):
        return jsonify({"error": "mensaje inválido"}), 400
    data = vms_read_file(mailbox, msg)
    if data is None:
        return jsonify({"error": "mensaje no encontrado"}), 404
    return Response(data, mimetype="audio/wav",
                    headers={"Content-Disposition": f'inline; filename="{msg}"',
                             "Accept-Ranges": "bytes",
                             "Cache-Control": "no-store"})


@app.post("/api/actions/vms")
def api_vms_action():
    body = request.get_json(force=True) if request.data else {}
    ue = body.get("ue", "1")
    mailbox = body.get("dest", VM_MAILBOX)
    confirmed, saved, before, after = vms_call(ue, mailbox)
    rc, out = sh(SOFTPHONE, "cat /tmp/pjV.log")
    lines = [ln for ln in out.splitlines()
             if any(k in ln for k in ("Making call", "Call 0 state",
                                      "200 OK", "200/REGISTER"))]
    return jsonify({"ok": confirmed and saved, "dest": mailbox, "ue": ue,
                    "confirmed": confirmed, "messages_before": before,
                    "messages_after": after, "lines": lines[-10:]})


@app.post("/api/vms/audio")
def api_vms_audio():
    """Recibe un WAV PCM16 8 kHz grabado/subido desde la web y lo graba en el buzón.

    El navegador convierte la grabación/archivo a PCM16 mono 8 kHz. El servidor
    valida la cabecera, lo inyecta como /tmp/left_msg.wav en el softphone y llama
    a <dest>@dominio como ya hace la prueba determinista.
    """
    up = request.files.get("audio")
    if not up:
        return jsonify({"error": "campo 'audio' (multipart) requerido"}), 400
    data = up.read()
    if len(data) > 2 * 1024 * 1024:
        return jsonify({"error": "audio > 2 MB"}), 413
    if not (data[:4] == b"RIFF" and data[8:12] == b"WAVE"):
        return jsonify({"error": "solo WAV PCM16 mono 8 kHz (el navegador lo convierte)"}), 400
    dur = (len(data) - 44) / 16000
    if dur < 1.5 or dur > 120:
        return jsonify({"error": f"duración {dur:.1f}s fuera de rango (1.5–120s)"}), 400
    # El mensaje web vive en /tmp/web_msg.wav; el tono determinista (left_msg.wav)
    # queda intacto para que /api/test siga siendo reproducible.
    # El AS tarda ~4 s (prompts vm-*) antes de empezar a grabar: se antepone ese
    # silencio para que el audio del usuario llegue justo cuando graba.
    data = pad_wav_start(data, PROMPT_PAD_S)
    if not inject_wav("web_msg.wav", data):
        return jsonify({"error": "no se pudo inyectar el audio en el softphone"}), 500
    body = request.form.to_dict()
    ue = body.get("ue", "1")
    mailbox = body.get("dest", VM_MAILBOX)
    confirmed, saved, before, after = vms_call(ue, mailbox, say_ms=round(dur * 1000))
    rc, out = sh(SOFTPHONE, "cat /tmp/pjV.log")
    lines = [ln for ln in out.splitlines()
             if any(k in ln for k in ("Making call", "Call 0 state",
                                      "200 OK", "200/REGISTER"))]
    return jsonify({"ok": confirmed and saved, "dest": mailbox, "ue": ue,
                    "duration_s": round(dur, 1), "confirmed": confirmed,
                    "messages_before": before, "messages_after": after,
                    "lines": lines[-10:]})


@app.get("/api/logs")
def api_logs():
    name = request.args.get("name", PCSCF)
    tail = int(request.args.get("tail", "80"))
    try:
        out = client.containers.get(name).logs(tail=tail).decode(errors="replace")
        return jsonify({"name": name, "logs": out.splitlines()})
    except Exception as e:  # noqa: BLE001
        return jsonify({"error": str(e)}), 500


# ---------- FEAT-01b: contraseña/PIN de servicio (self-care IVR) ----------
MYSQL = "mims3_mysql"


def pin_query(sql):
    """SQL → (ok, salida). MySQL root no tiene password (mysql_init.sh)."""
    rc, out = sh(MYSQL, f"mysql -u root -N -B -e \"{sql}\"")
    return rc == 0, out


@app.get("/api/pin")
def api_pin_list():
    ok, out = pin_query("SELECT msisdn, pin, updated_at FROM vas.subscriber_pin ORDER BY msisdn")
    rows = []
    for ln in out.splitlines():
        parts = ln.split("\t")
        if len(parts) == 3:
            rows.append({"msisdn": parts[0], "pin": parts[1], "updated_at": parts[2]})
    return jsonify({"ok": ok, "source": "mysql:vas.subscriber_pin", "pins": rows})


@app.post("/api/pin/change")
def api_pin_change():
    """Persiste el nuevo PIN del suscriptor (lo llama el IVR vía wget)."""
    body = request.get_json(force=True) if request.data else {}
    caller = str(body.get("caller", "")).strip()
    pin = str(body.get("pin", "")).strip()
    if not re.fullmatch(r"\d{4,8}", pin):
        return jsonify({"ok": False, "error": "pin debe ser 4–8 dígitos"}), 400
    if not re.fullmatch(r"\d{4,16}", caller):
        return jsonify({"ok": False, "error": "caller inválido"}), 400
    sql = (f"INSERT INTO vas.subscriber_pin (msisdn, pin) VALUES ('{caller}', '{pin}') "
           f"ON DUPLICATE KEY UPDATE pin = '{pin}', updated_at = NOW()")
    rc, out = pin_query(sql)
    if not rc:
        return jsonify({"ok": False, "error": out.strip() or "db error"}), 500
    return jsonify({"ok": True, "caller": caller, "pin": pin})


@app.get("/pin")
def pin_view():
    """Vista HTML read-only de los PIN de servicio (persistencia visible)."""
    ok, out = pin_query("SELECT msisdn, pin, updated_at FROM vas.subscriber_pin ORDER BY msisdn")
    rows = ""
    style = "<meta charset='utf-8'><h2>VAS — Contraseñas de servicio (FEAT-01b)</h2>"
    if ok:
        for ln in out.splitlines():
            p = ln.split("\t")
            if len(p) == 3:
                rows += (f"<tr><td>{p[0]}</td><td>{p[1]}</td><td>{p[2]}</td></tr>")
        html = (style + "<table border='1' cellpadding='6' style='border-collapse:collapse'>"
                "<tr><th>MSISDN</th><th>PIN</th><th>Actualizado</th></tr>" + rows + "</table>")
    else:
        html = style + f"<p>Error consultando BD: {out}</p>"
    return f"<html><body style='font-family:monospace'>{html}</body></html>"


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8888, debug=False)