#!/bin/bash
# bench_maqueta.sh — Pruebas de rendimiento y recursos para comparar maquetas IMS.
# Mide, de forma determinista y sobre la MISMA lógica para las maquetas:
#   - Tiempo de registro IMS (401 -> 200 OK + Service-Route)
#   - Tiempo de establecimiento de llamada UE -> AS (INVITE -> CONFIRMED)
#   - Cancel/colgado y grabación VMS (incluye latencia hasta grabar el msg)
#   - Recursos (CPU/MEM idle y bajo llamada) de los contenedores clave
#
# Uso:  bash scripts/bench_maqueta.sh <mims | mims2 | mims3>
# Salida: bloques "METRIC <clave>=<valor>" lista para volcar a CSV, más echo de estado.
#
# El script es CONTENIDO-DIRIGIDO: usa el mismo test funcional de la maqueta
# (test_maqueta.sh) para verificar PASS/FAIL, y añade mediciones de tiempo y
# recursos sobre esa misma ejecución.

set -u

MAQUETA="${1:-mims3}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
cd "$ROOT" || exit 2

DOMAIN="ims.mnc001.mcc001.3gppnetwork.org"
UE1_IMSI="001011234567890"; UE1_KI="8baf473f2f8fd09487cccbd7097c6862"
UE2_IMSI="001011234567891"; UE2_KI="2a6ab8297e0d15c7a12eef0d8a12b143"

case "$MAQUETA" in
  mims)  PREFIX="mims";  PCSCF_IP="172.30.0.8" ;;
  mims2) PREFIX="mims2"; PCSCF_IP="172.31.0.8" ;;
  mims3) PREFIX="mims3"; PCSCF_IP="172.32.0.8" ;;
  *) echo "Uso: $0 <mims|mims2|mims3>"; exit 2 ;;
esac

SOFTPHONE="${PREFIX}_softphone"
PCSCF="${PREFIX}_pcscf"
AS_CTN="${PREFIX}_freeswitch"
ASFRONT="${PREFIX}_asfront"
if [ "$MAQUETA" = "mims" ] || [ "$MAQUETA" = "mims2" ]; then
  AS_CTN="${PREFIX}_asterisk"
fi
VMS_DIR="/var/spool/asterisk/voicemail/default/0100003/INBOX"
if [ "$MAQUETA" = "mims3" ]; then
  VMS_DIR="/var/lib/freeswitch/storage/vms/0100003/INBOX"
fi
BASE="--realm ${DOMAIN} --no-tcp --null-audio --log-level 4"

OUT="${SCRIPT_DIR}/bench_${MAQUETA}.txt"
: > "$OUT"

metric(){ printf "%-40s %s\n" "METRIC $1" "$2" | tee -a "$OUT"; }
say(){ echo "[ $1 ]"; }

kill_sip(){ docker exec "$SOFTPHONE" sh -c 'pkill -9 -f pjsua; true' 2>/dev/null; }
wait_pj(){ # $1=timeout  $2=log  $3=patron
  local t="$1" i=0
  while [ "$i" -lt "$t" ]; do
    if docker exec "$SOFTPHONE" sh -c "grep -aq '$3' /tmp/$2" 2>/dev/null; then return 0; fi
    sleep 1; i=$((i+1))
  done
  return 1
}
# mide el instante de la PRIMERA coincidencia del patrón en una línea que tenga
# timestamp (formato pjsua: "HH:MM:SS.fff ..."). El patrón debe matchear una
# línea temporizada (p.ej. "Response msg 401/REGISTER", "Making call to",
# "registration success", no el body del SIP).
ts_of(){ # $1=log  $2=patron  -> devuelve milisegundo del día (ms) o vacío
  docker exec "$SOFTPHONE" sh -c "grep -a -m1 '$2' /tmp/$1" 2>/dev/null \
    | grep -oE '[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}' | head -1 \
    | awk -F'[:.]' '{print $1*3600000+$2*60000+$3*1000+$4}'
}
# Cap de log completo para poder re-parsarlo si hace falta
NOW(){ date +%s; }

# Genera el tono PCM 8 kHz (45 s) en /tmp del HOST (python disponible) y lo
# inyecta en el softphone. Necesario para que el AS tenga audio real que grabar.
gen_tone(){ # $1=tiempo_seg
  python3 - "$1" <<'PYEOF'
import struct, math, wave, sys
SR=8000; DUR=int(sys.argv[1])
frames=bytearray()
for i in range(SR*DUR):
    t=i/SR
    v=int(9000*math.sin(2*math.pi*420*t)*(0.9 if int(t*2)%2 else 0.35))
    frames+=struct.pack('<h',v)
with wave.open('/tmp/left_msg_tone.wav','wb') as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(bytes(frames))
PYEOF
  docker cp /tmp/left_msg_tone.wav "$SOFTPHONE":/tmp/left_msg.wav 2>/dev/null
}

echo "################ BENCH maqueta: $MAQUETA ################"
docker ps --format "{{.Names}}" | sort > /tmp/bench_containers_${MAQUETA}.txt
: > /tmp/bench_stats_call_${MAQUETA}.txt
: > /tmp/bench_stats_idle_${MAQUETA}.txt

# ---------- 1. Funcional (test oficial de la maqueta) ----------
say "PASO A/1 — Test funcional oficial (test_maqueta.sh)"
T0=$(NOW)
bash scripts/test_maqueta.sh > "${OUT%.txt}_func.txt" 2>&1
RC=$?
T_FUNC=$(( $(NOW)-T0 ))
PASS_FUNC=$(grep -c "\[PASS\]" "${OUT%.txt}_func.txt")
FAIL_FUNC=$(grep -c "\[FAIL\]" "${OUT%.txt}_func.txt")
metric "funcional_rc" "$RC"
metric "funcional_pass" "$PASS_FUNC"
metric "funcional_fail" "$FAIL_FUNC"
metric "funcional_duracion_s" "$T_FUNC"

# ---------- 2. Registro IMS (latencia 401 -> 200) ----------
say "PASO A/2 — Registro IMS UE1 (latencia)"
kill_sip
docker exec "$SOFTPHONE" sh -c "rm -f /tmp/pjB.log"
T_START=$(NOW)
docker exec -d "$SOFTPHONE" sh -c "pjsua --id sip:$UE1_IMSI@$DOMAIN --registrar sip:$DOMAIN:5060 $BASE --username $UE1_IMSI --password $UE1_KI --local-port 5061 > /tmp/pjB.log 2>&1"
wait_pj 20 pjB.log "registration success, status=200"; RC_REG=$?
T_200=$(ts_of pjB.log "registration success, status=200")
T_401=$(ts_of pjB.log "Response msg 401/REGISTER")
docker exec "$SOFTPHONE" sh -c "grep -aq 'Service-Route' /tmp/pjB.log"; RC_SR=$?
metric "registro_ok" "$([ "$RC_REG" -eq 0 ] && [ "$RC_SR" -eq 0 ] && echo 1 || echo 0)"
if [ -n "$T_401" ] && [ -n "$T_200" ] && [ "$T_200" -gt "$T_401" ]; then
  metric "registro_latencia_401_200_ms" "$(( T_200-T_401 ))"
else
  metric "registro_latencia_401_200_ms" "n/a"
fi
kill_sip; sleep 1

# ---------- 3. Llamada UE1 -> 0100002 (IVR) con recursos bajo llamada ----------
say "PASO A/3 — Llamada UE1 -> IVR (0100002) + recursos bajo llamada"
docker exec "$SOFTPHONE" sh -c "rm -f /tmp/pjC.log"
docker exec -d "$SOFTPHONE" sh -c "( until grep -aq 'Response msg 200/REGISTER' /tmp/pjC.log 2>/dev/null; do sleep 0.2; done; echo m; sleep 0.5; echo 'sip:0100002@$DOMAIN'; sleep 20 ) | pjsua --id sip:$UE1_IMSI@$DOMAIN --registrar sip:$DOMAIN:5060 $BASE --username $UE1_IMSI --password $UE1_KI --local-port 5061 --outbound=sip:$PCSCF_IP:5060\;lr > /tmp/pjC.log 2>&1 &"
wait_pj 25 pjC.log "Making call with acc"; T_INV=$(ts_of pjC.log "Making call with acc")
wait_pj 30 pjC.log "Call 0 state changed to CONFIRMED"; RC_CALL=$?
T_CFM=$(ts_of pjC.log "Call 0 state changed to CONFIRMED")
if [ -n "$T_INV" ] && [ -n "$T_CFM" ] && [ "$T_CFM" -gt "$T_INV" ]; then
  metric "llamada_setup_invite_confirmed_ms" "$(( T_CFM-T_INV ))"
else
  metric "llamada_setup_invite_confirmed_ms" "n/a"
fi
metric "llamada_confirmada" "$([ "$RC_CALL" -eq 0 ] && echo 1 || echo 0)"

# Recursos CPU/MEM bajo llamada (con la llamada activa: pjsua sigue 20s)
STAT_CTN=("${PREFIX}_scscf" "${PREFIX}_pcscf" "${PREFIX}_icscf" "$AS_CTN")
if [ "$MAQUETA" = "mims3" ] && [ -n "$(docker ps --format '{{.Names}}' | grep -x "$ASFRONT")" ]; then
  STAT_CTN+=("$ASFRONT")
fi
docker stats --no-stream --format "{{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" "${STAT_CTN[@]}" 2>/dev/null \
  > /tmp/bench_stats_call_${MAQUETA}.txt
while IFS=$'\t' read -r name cpu mem; do
  [ -z "$name" ] && continue
  metric "cpu_call_$(basename "$name")_pct" "$cpu"
  metric "mem_call_$(basename "$name")_mb" "$(echo "$mem" | awk '{print $1}')"
done < /tmp/bench_stats_call_${MAQUETA}.txt

# IVR efectivamente reproducido en el AS (1=encontrado, 0=no)
IVR_PAT="Playing 'ivr_bienvenida.slin'"
[ "$MAQUETA" = "mims3" ] && IVR_PAT="ivr_bienvenida.wav"
docker logs --since 60s "$AS_CTN" 2>&1 | grep -q "$IVR_PAT"
metric "ivr_reproducido" "$([ $? -eq 0 ] && echo 1 || echo 0)"
# RTPEngine engaged (P-CSCF)
docker logs --since 60s "$PCSCF" 2>&1 | grep -q "RTPEngine engaged for Application Server"
metric "rtpengine_engaged" "$([ $? -eq 0 ] && echo 1 || echo 0)"
# AS FRONTERA (mims3): relay ISC->FreeSWITCH realizado
if [ "$MAQUETA" = "mims3" ]; then
  docker logs --since 60s "$ASFRONT" 2>&1 | grep -q "AS-Front: re-origina a FreeSWITCH"
  metric "asfront_relay_isc" "$([ $? -eq 0 ] && echo 1 || echo 0)"
fi
kill_sip; sleep 1

# ---------- 4. Recursos idle (tras estabilizar) ----------
say "PASO A/4 — Recursos idle"
sleep 10
: > /tmp/bench_stats_idle_${MAQUETA}.txt
for c in "${STAT_CTN[@]}"; do
  docker stats --no-stream --format "{{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" "$c" 2>/dev/null >> /tmp/bench_stats_idle_${MAQUETA}.txt
done
while IFS=$'\t' read -r name cpu mem; do
  [ -z "$name" ] && continue
  metric "cpu_idle_$(basename "$name")_pct" "$cpu"
  metric "mem_idle_$(basename "$name")_mb" "$(echo "$mem" | awk '{print $1}')"
done < /tmp/bench_stats_idle_${MAQUETA}.txt

# ---------- 5. VMS (buzón 0100003): latencia hasta grabar referencia ----------
say "PASO A/5 — VMS UE1 -> buzón 0100003 (latencia hasta grabar)"
gen_tone 45
docker exec "$AS_CTN" sh -c "rm -f ${VMS_DIR}/msg*.* 2>/dev/null; true"
kill_sip
T0=$(NOW)
docker exec -d "$SOFTPHONE" sh -c "rm -f /tmp/pjV.log; ( until grep -aq 'Response msg 200/REGISTER' /tmp/pjV.log 2>/dev/null; do sleep 0.2; done; echo m; sleep 0.7; echo 'sip:0100003@$DOMAIN'; sleep 18; echo h; sleep 4 ) | pjsua --id sip:$UE1_IMSI@$DOMAIN --registrar sip:$DOMAIN:5060 $BASE --username $UE1_IMSI --password $UE1_KI --local-port 5061 --play-file /tmp/left_msg.wav --auto-play --outbound=sip:$PCSCF_IP:5060\;lr > /tmp/pjV.log 2>&1 &"
wait_pj 25 pjV.log "Call 0 state changed to CONFIRMED"; RVC=$?
V_AFTER=0; i=0
while [ "$V_AFTER" -eq 0 ] && [ "$i" -lt 50 ]; do
  sleep 3
  V_AFTER=$(docker exec "$AS_CTN" sh -c "ls ${VMS_DIR}/msg*.wav 2>/dev/null | wc -l")
  i=$((i+1))
done
T_VMS=$(( $(NOW)-T0 ))
metric "vms_confirmada" "$([ "$RVC" -eq 0 ] && echo 1 || echo 0)"
metric "vms_mensaje_grabado" "$([ "$V_AFTER" -gt 0 ] && echo 1 || echo 0)"
metric "vms_tiempo_hasta_grabar_s" "$([ "$V_AFTER" -gt 0 ] && echo "$T_VMS" || echo n/a)"
kill_sip; sleep 1

echo "################ RESULTADO BENCH $MAQUETA ################"
echo "Escrito en: $OUT"
echo "(ver también $(basename ${OUT%.txt})_func.txt para el detalle del test funcional)"
exit 0