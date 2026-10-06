#!/bin/bash
# capture_iteration.sh — Ejecuta el E2E bajo captura y deja los artefactos de la iteración.
# Uso: bash scripts/capture_iteration.sh <dir_salida>
# Captura: tcpdump -i any -s0 -w maqueta_ims.pcap   (en contenedor --net=host, sin sudo)
# Filtro:  tshark -r maqueta_ims.pcap -Y sip -w maqueta_ims_sip_only.pcap
#          (+ heurística ESP-NULL para ver el SIP protegido por IPsec)
# Análisis: scripts/check_3gpp.py -> check_3gpp.md
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$(mkdir -p "$1" && cd "$1" && pwd)"
CAP="mims3_tcpdump"

docker rm -f "$CAP" >/dev/null 2>&1
docker run -d --name "$CAP" --net=host --cap-add=NET_RAW --cap-add=NET_ADMIN \
  -v "$OUT":/cap --entrypoint tcpdump mims3_kamailio -i any -s0 -U -w /cap/maqueta_ims.pcap >/dev/null
sleep 2
bash "$SCRIPT_DIR/test_maqueta.sh" > "$OUT/test_maqueta.log" 2>&1; RC=$?
sleep 2
docker stop -t 2 "$CAP" >/dev/null; docker rm "$CAP" >/dev/null
# Con IPsec activo la señalización de Gm viaja dentro de ESP (cifrado NULL, solo
# integridad): sin la heurística ESP-NULL tshark no ve el SIP protegido.
# (tshark se alimenta por stdin: el pcap lo escribe root en un fuseblk.)
# Los puertos SIP del core 4060 (I-CSCF) y 6060 (S-CSCF) caen en el rango que
# Wireshark asigna a X11 (6000-6063) cuando van por TCP: se fuerza "decode as SIP".
tshark -o esp.enable_null_encryption_decode_heuristic:TRUE \
  -d tcp.port==6060,sip -d tcp.port==4060,sip -r - -Y sip -w - \
  < "$OUT/maqueta_ims.pcap" > "$OUT/maqueta_ims_sip_only.pcap"
python3 "$SCRIPT_DIR/check_3gpp.py" "$OUT/maqueta_ims_sip_only.pcap" > "$OUT/check_3gpp.md"; RC3=$?
grep -E '^\s*\[(PASS|FAIL)\]|^PASS:' "$OUT/test_maqueta.log"
tail -n 30 "$OUT/check_3gpp.md"
echo "E2E rc=$RC  3GPP rc=$RC3"
exit $(( RC | RC3 ))
