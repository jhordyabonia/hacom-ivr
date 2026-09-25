#!/bin/bash
# Provisionamiento de suscriptores UE1/UE2 en PyHSS (SQLite).
# Espera a que PyHSS haya creado su BD (/var/lib/pyhss/hss.db) y aplica el
# mismo UPSERT idempotente que usa la UI (endpoint POST /api/config/provision):
#   apn + auc + subscriber + ims_subscriber + scscf, todo en SQLite.
# Uso:  bash scripts/provision_hss.sh [http://host:port]   (default: local UI 8090)

cd "$(dirname "$0")"
UI="${1:-http://127.0.0.1:8090}"

echo "Esperando al backend de la UI ($UI)..."
for _ in $(seq 1 60); do
  curl -s -o /dev/null "$UI/api/config" && break
  sleep 3
done

echo "Provisionando UE1/UE2 en PyHSS (SQLite)..."
curl -s -X POST "$UI/api/config/provision" | python3 -c "
import sys, json
d = json.load(sys.stdin)
for r in d.get('results', []):
    mark = 'OK ' if r['ok'] else 'ERR'
    print(f\"  [{mark}] {r['tag']:5s} {r['label']}  ({r['detail']})\")
sys.exit(0 if d.get('ok') else 1)
"
echo "OK. Suscriptores en PyHSS (SQLite):"
docker exec mims3_pyhss_hss sh -c "python3 -c \"
import sqlite3
c = sqlite3.connect('/var/lib/pyhss/hss.db')
for r in c.execute('SELECT imsi, msisdn, ifc_path, scscf FROM ims_subscriber'):
    print('  ', r)
\""