#!/usr/bin/env python3
"""provision_load_ues.py — alta/baja de abonados de carga en PyHSS (SQLite).

Se ejecuta DENTRO del contenedor mims3_pyhss_hss (stdin):
  docker exec -i <pyhss_hss> python3 - add 50 < provision_load_ues.py   # imprime "msisdn,ki"
  docker exec -i <pyhss_hss> python3 - del 50 < provision_load_ues.py

Abonados: IMSI 0010188880000NN, MSISDN 00101880NN (NN = 01..N), iFC maqueta_ifc.xml.
Mismo UPSERT que la UI (interfaz/app.py, /api/config/provision). La Ki es la
contraseña Digest del perfil no-3GPP: se genera al azar y solo se devuelve por stdout.
"""
import secrets, sqlite3, sys

ACTION, N = sys.argv[1], int(sys.argv[2])
DOMAIN = "ims.mnc001.mcc001.3gppnetwork.org"
OPC = "61f0f589e23b2bd9c35fe9f2d09db0c1"
c = sqlite3.connect("/var/lib/pyhss/hss.db")
apn_id = None
if ACTION == "add":
    c.execute("INSERT OR IGNORE INTO apn (apn, ip_version, apn_ambr_dl, apn_ambr_ul, charging_characteristics) "
              "VALUES ('internet', 0, 999999, 999999, '0800')")
    apn_id = c.execute("SELECT apn_id FROM apn WHERE apn='internet'").fetchone()[0]
for i in range(1, N + 1):
    imsi, msisdn = f"0010188880000{i:02d}", f"00101880{i:02d}"
    c.execute("DELETE FROM ims_subscriber WHERE imsi=? OR msisdn=?", (imsi, msisdn))
    c.execute("DELETE FROM subscriber WHERE imsi=?", (imsi,))
    c.execute("DELETE FROM auc WHERE imsi=?", (imsi,))
    if ACTION != "add":
        continue
    ki = secrets.token_hex(16)
    c.execute("INSERT INTO auc (ki, opc, amf, sqn, imsi, algo) VALUES (?, ?, '8000', 7091, ?, '3')", (ki, OPC, imsi))
    auc_id = c.execute("SELECT auc_id FROM auc WHERE imsi=?", (imsi,)).fetchone()[0]
    c.execute("INSERT INTO subscriber (imsi, enabled, auc_id, default_apn, apn_list, msisdn) VALUES (?, 1, ?, ?, 'internet', ?)",
              (imsi, auc_id, apn_id, msisdn))
    c.execute("INSERT INTO ims_subscriber (imsi,msisdn,msisdn_list,ifc_path,scscf,scscf_realm) VALUES (?,?,?,?,?,?)",
              (imsi, msisdn, msisdn, "maqueta_ifc.xml", "sip:scscf." + DOMAIN, DOMAIN))
    print(f"{msisdn},{ki}")
c.commit()
print(f"# {ACTION} {N}: ims_subscriber total = {c.execute('SELECT COUNT(*) FROM ims_subscriber').fetchone()[0]}", file=sys.stderr)
