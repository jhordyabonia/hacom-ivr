#!/bin/bash
# test_maqueta.sh — Prueba simple y verificable de la maqueta Core IMS
# Valida: contenedores, DNS, listeners SIP, registro IMS de 2 UEs,
# llamada UE->AS (iFC) con reproducción de IVR en FreeSWITCH (AS aplicación)
# y buzón de voz (VMS: el UE deja un mensaje en el buzón 0100003).
# Uso:  bash scripts/test_maqueta.sh   (salida exit 0 si todo pasa)

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
cd "$ROOT" || exit 2

DOMAIN="ims.mnc001.mcc001.3gppnetwork.org"
UE1_IMSI="001011234567890"; UE1_MSISDN="0010100001"; UE1_KI="8baf473f2f8fd09487cccbd7097c6862"
UE2_IMSI="001011234567891"; UE2_MSISDN="0010100002"; UE2_KI="2a6ab8297e0d15c7a12eef0d8a12b143"
# Conformidad TS 24.229/TS 23.003 (incumplimiento #4 del diagnóstico):
# la URI de registro (IMPU) es sip:<MSISDN>@dominio en From/To, y el IMPI
# (identidad privada) viaja en --username (IMSI@dominio) del Authorization.
SOFTPHONE="mims3_softphone"
FREESWITCH="mims3_freeswitch"
ASFRONT="mims3_asfront"
PCSCF="mims3_pcscf"
PCSCF_IP="172.32.0.8"
FS_IP="172.32.0.15"
VMS_DIR="/var/lib/freeswitch/storage/vms/0100003/INBOX"
BASE="--realm ${DOMAIN} --no-tcp --null-audio --log-level 4"

PASS=0; FAIL=0
say()    { echo "[ $1 ]"; }
report() { # $1=0/1  $2=operacion  $3=detalle
  if [ "$1" -eq 0 ]; then PASS=$((PASS+1)); printf "  [PASS] %s  (%s)\n" "$2" "$3";
  else FAIL=$((FAIL+1)); printf "  [FAIL] %s  (%s)\n" "$2" "$3"; fi
}
kill_sip() { docker exec "$SOFTPHONE" sh -c 'pkill -9 -f pjsua; true' 2>/dev/null; }
wait_pj() { # $1=timeout_s  $2=log  $3=patron ; cuando el patrón aparece en /tmp/$2
  local t="$1"; local i=0
  while [ "$i" -lt "$t" ]; do
    if docker exec "$SOFTPHONE" sh -c "grep -aq \"$3\" /tmp/$2" 2>/dev/null; then return 0; fi
    sleep 1; i=$((i+1))
  done
  return 1
}

echo "=================== Test maqueta Core IMS (maqueta-ims-3) ==================="
echo "Dominio: $DOMAIN"

say "PASO 1/6 — Contenedores arriba"
CONTAINERS="mims3_dns mims3_mysql mims3_redis mims3_pyhss_api mims3_pyhss_hss mims3_pyhss_diameter mims3_icscf mims3_scscf mims3_pcscf mims3_rtpengine mims3_asfront mims3_freeswitch mims3_softphone mims3_ui"
N_TOTAL=$(echo $CONTAINERS | wc -w); N_UP=0
for c in $CONTAINERS; do
  if [ "$(docker inspect -f '{{.State.Running}}' "$c" 2>/dev/null)" = "true" ]; then N_UP=$((N_UP+1));
  else echo "  [FAIL] contenedor $c no está arriba"; FAIL=$((FAIL+1)); fi
done
if [ "$N_UP" = "$N_TOTAL" ]; then PASS=$((PASS+1)); fi
printf "  [%s] contenedores arriba (%s/%s)\n" "$([ "$N_UP" = "$N_TOTAL" ] && echo PASS || echo FAIL)" "$N_UP" "$N_TOTAL"

say "PASO 2/6 — DNS (A del dominio -> P-CSCF)"
R=$(docker exec "$SOFTPHONE" getent ahostsv4 "$DOMAIN" 2>/dev/null | awk 'NR==1{print $1}')
report "$([ "$R" = "$PCSCF_IP" ] && echo 0 || echo 1)" "resolución DNS ahostsv4" "$DOMAIN -> ${R:-N/A} (esperado $PCSCF_IP)"

say "PASO 3/6 — Listeners SIP/UDP de los nodos"
for pair in "mims3_scscf:6060" "mims3_icscf:4060" "mims3_pcscf:5060" "mims3_asfront:5060" "mims3_freeswitch:5060"; do
  name="${pair%%:*}"; port="${pair##*:}"
  if docker exec "$name" sh -c "ss -lun 2>/dev/null | grep -q ':$port ' || netstat -lun 2>/dev/null | grep -q ':$port '" 2>/dev/null; then
    PASS=$((PASS+1)); printf "  [PASS] listener SIP/UDP %s:%s\n" "$name" "$port"
  else
    FAIL=$((FAIL+1)); printf "  [FAIL] listener SIP/UDP %s:%s\n" "$name" "$port"
  fi
done

say "PASO 4/6 — Registro IMS de UE1 (401 -> 200 OK + Service-Route)"
kill_sip
docker exec -d "$SOFTPHONE" sh -c "pjsua --id sip:$UE1_MSISDN@$DOMAIN --registrar sip:$DOMAIN:5060 $BASE --username $UE1_MSISDN --password $UE1_KI --local-port 5061 > /tmp/pj1.log 2>&1"
wait_pj 15 pj1.log "registration success, status=200"; R1=$?
docker exec "$SOFTPHONE" sh -c "grep -aq '401 Unauthorized - Challenging the UE' /tmp/pj1.log && grep -aq 'Service-Route' /tmp/pj1.log"; R1B=$?
report "$([ $R1 -eq 0 ] && [ $R1B -eq 0 ] && echo 0 || echo 1)" "registro UE1 (200 OK + 401 + Service-Route)" "IMSI $UE1_IMSI"
kill_sip; sleep 1

say "PASO 5/6 — Llamada UE1 -> AS (iFC -> IVR en FreeSWITCH)"
# Determinista: pjsua registra; un escritor retrasado por el pipe ordena la llamada
# ('m') al ver 200 OK del REGISTER. Si la URI se pasa al arrancar, pjsua llama antes
# de registrar y el S-CSCF responde 403 "You must register first with a S-CSCF".
# Paises: la consola de pjsua solo lee comandos vía pipe y el 'sleep' evita el
# hangup por cierre del stdin (prueba previa daba 487 Session already DISCONNECTED).
docker exec -d "$SOFTPHONE" sh -c "rm -f /tmp/pjC.log; ( until grep -aq 'Response msg 200/REGISTER' /tmp/pjC.log 2>/dev/null; do sleep 0.2; done; echo m; sleep 0.5; echo 'sip:0100002@$DOMAIN'; sleep 20 ) | pjsua --id sip:$UE1_MSISDN@$DOMAIN --registrar sip:$DOMAIN:5060 $BASE --username $UE1_MSISDN --password $UE1_KI --local-port 5061 --outbound=sip:$PCSCF_IP:5060\;lr > /tmp/pjC.log 2>&1 &"
wait_pj 25 pjC.log "Call 0 state changed to CONFIRMED"; RC=$?
docker logs --since 25s "$FREESWITCH" 2>&1 | grep -q "ivr_bienvenida.wav"; RA=$?
docker logs --since 25s "$ASFRONT" 2>&1 | grep -q "AS-Front: re-origina a FreeSWITCH"; RAS=$?
docker logs --since 25s "$PCSCF" 2>&1 | grep -q "RTPEngine engaged for Application Server"; RRT=$?
report "$([ $RC -eq 0 ] && echo 0 || echo 1)" "llamada UE1 CONFIRMED" "INVITE -> 200 OK -> ACK"
report "$([ $RA -eq 0 ] && echo 0 || echo 1)" "FreeSWITCH reproduce IVR" "playback ivr_bienvenida.wav"
report "$([ $RAS -eq 0 ] && echo 0 || echo 1)" "AS Frontera relay ISC -> FS" "log AS-Front re-origina"
report "$([ $RRT -eq 0 ] && echo 0 || echo 1)" "RTPEngine engaged (P-CSCF)" "medios reemplazados por RTPEngine"
kill_sip; sleep 1

say "PASO 5b/6 — FEAT-01: menú DTMF del IVR (país CL, dígito 1 = saldo)"
# El IVR (0100002) ejecuta la opción 1 (playback de saldo.wav) al recibir el DTMF.
# En pjsua '#' abre la edición interactiva de dígitos ("DTMF strings to send") y la
# siguiente línea '1' envía el RFC 2833 1. Consumido por play_and_get_digits
# (session:execute) y persistido en flows/cl.json -> action=playback.
IVR_N0=$(docker exec "$FREESWITCH" sh -c "wc -l < /mnt/freeswitch/logs/ivr_cdr.jsonl 2>/dev/null || echo 0")
docker exec -d "$SOFTPHONE" sh -c "rm -f /tmp/pjF.log; ( until grep -aq 'Response msg 200/REGISTER' /tmp/pjF.log 2>/dev/null; do sleep 0.2; done; echo m; sleep 0.7; echo 'sip:0100002@$DOMAIN'; sleep 5; printf '#\n1\n'; sleep 10 ) | pjsua --id sip:$UE1_MSISDN@$DOMAIN --registrar sip:$DOMAIN:5060 $BASE --username $UE1_MSISDN --password $UE1_KI --local-port 5061 --outbound=sip:$PCSCF_IP:5060\;lr > /tmp/pjF.log 2>&1 &"
wait_pj 25 pjF.log "Call 0 state changed to CONFIRMED"; RF=$?
# La acción se registra ~5s después del CONFIRMED (cuando llega el RFC 2833): se espera.
IVR_ACTION=""; IVR_JSONL=""
i=0
while [ "$i" -lt 20 ]; do
  sleep 1; i=$((i+1))
  [ -z "$IVR_ACTION" ] && IVR_ACTION=$(docker logs --since 45s "$FREESWITCH" 2>&1 | grep -aoE "IVR_ACTION flow=bienvenida_cl caller=0010100001 digit=1 action=playback" | head -1)
  if [ -z "$IVR_JSONL" ]; then
    IVR_JSONL=$(docker exec "$FREESWITCH" sh -c "tail -n +$((IVR_N0+1)) /mnt/freeswitch/logs/ivr_cdr.jsonl 2>/dev/null" | grep -a '"digit":"1","action":"playback"' | head -1)
  fi
  [ -n "$IVR_ACTION" ] && [ -n "$IVR_JSONL" ] && break
done
report "$([ "$RF" -eq 0 ] && [ -n "$IVR_ACTION" ] && echo 0 || echo 1)" "FEAT-01: menú DTMF (opción 1)" "$([ -n "$IVR_ACTION" ] && echo 'IVR_ACTION digit=1 action=playback' || echo 'DTMF no ejecutó acción')"
report "$([ -n "$IVR_JSONL" ] && echo 0 || echo 1)" "FEAT-01: CDR de opción persistido" "$([ -n "$IVR_JSONL" ] && echo 'ivr_cdr.jsonl digit=1 action=playback' || echo 'sin fila nueva digit=1')"
kill_sip; sleep 1

say "PASO 6/6 — VMS: el UE1 deja un mensaje en el buzón 0100003 (iFC)"
# El AS necesita audio real para la grabación (con --null-audio pjsua no genera
# RTP y la app abandona: "Recording was 0 seconds long"). Se genera un tono de
# 45 s y se inyecta en el softphone vía cp.
python3 - <<'PYEOF'
import struct, math, wave
SR=8000
frames=bytearray()
for i in range(SR*45):
    t=i/SR
    v=int(9000*math.sin(2*math.pi*420*t)*(0.9 if int(t*2)%2 else 0.35))
    frames+=struct.pack('<h',v)
with wave.open('/tmp/left_msg_tone.wav','wb') as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(bytes(frames))
PYEOF
docker cp /tmp/left_msg_tone.wav "$SOFTPHONE":/tmp/left_msg.wav 2>/dev/null
docker exec "$FREESWITCH" sh -c "rm -f ${VMS_DIR}/msg*.* 2>/dev/null; true"
kill_sip
docker exec -d "$SOFTPHONE" sh -c "rm -f /tmp/pjV.log; ( until grep -aq 'Response msg 200/REGISTER' /tmp/pjV.log 2>/dev/null; do sleep 0.2; done; echo m; sleep 0.7; echo 'sip:0100003@$DOMAIN'; sleep 18; echo h; sleep 4 ) | pjsua --id sip:$UE1_MSISDN@$DOMAIN --registrar sip:$DOMAIN:5060 $BASE --username $UE1_MSISDN --password $UE1_KI --local-port 5061 --play-file /tmp/left_msg.wav --auto-play --outbound=sip:$PCSCF_IP:5060\;lr > /tmp/pjV.log 2>&1 &"
wait_pj 25 pjV.log "Call 0 state changed to CONFIRMED"; RVC=$?
V_AFTER=0; i=0
while [ "$V_AFTER" -eq 0 ] && [ "$i" -lt 50 ]; do
  sleep 3
  V_AFTER=$(docker exec "$FREESWITCH" sh -c "ls ${VMS_DIR}/msg*.wav 2>/dev/null | wc -l")
  i=$((i+1))
done
report "$([ $RVC -eq 0 ] && echo 0 || echo 1)" "VMS: llamada UE1 -> buzón (CONFIRMED)" "UE1 -> 0100003 vía iFC"
report "$([ "$V_AFTER" -gt 0 ] && echo 0 || echo 1)" "VMS: mensaje grabado en INBOX" "msg*.wav: 0 -> ${V_AFTER:-0} (Buzón 0100003)"
kill_sip; sleep 1

say "PASO 6b/6 — FEAT-02: VMS completo (mod_voicemail + MWI + recuperación)"
# FEAT-02: VMS completo. El UE1 llama al UE2 (no registrado) → el mensaje se
# graba en el buzón del MSISDN de UE2 (mod_voicemail) y se genera un MWI
# (NOTIFY message-summary) que se entrega al UE2 cuando se registra.
# Luego, el UE2 llama a 0100004 (recuperación) → autentica con PIN y
# escucha/borra el mensaje.
VM2_DIR="/var/lib/freeswitch/storage/voicemail/default/ims.mnc001.mcc001.3gppnetwork.org/0010100002"
docker exec "$FREESWITCH" sh -c "rm -rf ${VM2_DIR} 2>/dev/null; true"
kill_sip
# 1. Desregistrar UE2 (REGISTER con Expires: 0 + Digest AKA)
python3 "$SCRIPT_DIR/deregister_ue2.py" || echo "  [WARN] deregister_ue2.py falló (continúa)"
sleep 3
# 2. Llamar de UE1 a UE2 (no registrado) → mensaje al buzón de UE2
docker exec -d "$SOFTPHONE" sh -c "rm -f /tmp/pjV2.log; ( until grep -aq 'Response msg 200/REGISTER' /tmp/pjV2.log 2>/dev/null; do sleep 0.2; done; echo m; sleep 0.7; echo 'sip:0010100002@$DOMAIN'; sleep 18; echo h; sleep 4 ) | pjsua --id sip:$UE1_MSISDN@$DOMAIN --registrar sip:$DOMAIN:5060 $BASE --username $UE1_MSISDN --password $UE1_KI --local-port 5061 --play-file /tmp/left_msg.wav --auto-play --outbound=sip:$PCSCF_IP:5060\;lr > /tmp/pjV2.log 2>&1 &"
wait_pj 25 pjV2.log "Call 0 state changed to CONFIRMED"; RV2C=$?
VM2_AFTER=0; i=0
while [ "$VM2_AFTER" -eq 0 ] && [ "$i" -lt 50 ]; do
  sleep 3
  VM2_AFTER=$(docker exec "$FREESWITCH" sh -c "ls ${VM2_DIR}/msg_*.wav 2>/dev/null | wc -l")
  i=$((i+1))
done
report "$([ $RV2C -eq 0 ] && echo 0 || echo 1)" "FEAT-02: llamada UE1 -> buzón UE2 (CONFIRMED)" "UE1 -> 0010100002 vía iFC (terminating-unregistered)"
report "$([ "$VM2_AFTER" -gt 0 ] && echo 0 || echo 1)" "FEAT-02: mensaje grabado en buzón UE2" "msg_*.wav: 0 -> ${VM2_AFTER:-0} (Buzón 0010100002)"
# 3. Registrar UE2 → debe recibir MWI (NOTIFY message-summary)
docker exec -d "$SOFTPHONE" sh -c "pjsua --id sip:$UE2_MSISDN@$DOMAIN --registrar sip:$DOMAIN:5060 $BASE --username $UE2_MSISDN --password $UE2_KI --local-port 5062 > /tmp/pjR2.log 2>&1 &"
sleep 5
MWI_LOG=$(docker logs --since 30s mims3_scscf 2>&1 | grep -a "MWI_DELIVER" | head -1)
report "$([ -n "$MWI_LOG" ] && echo 0 || echo 1)" "FEAT-02: MWI entregado al registrar UE2" "$([ -n "$MWI_LOG" ] && echo 'MWI_DELIVER en log S-CSCF' || echo 'sin MWI_DELIVER')"
# 4. Recuperación: UE2 llama a 0100004 → autentica con PIN → escucha/borra
docker exec -d "$SOFTPHONE" sh -c "rm -f /tmp/pjR3.log; ( until grep -aq 'Response msg 200/REGISTER' /tmp/pjR3.log 2>/dev/null; do sleep 0.2; done; echo m; sleep 0.7; echo 'sip:0100004@$DOMAIN'; sleep 8; printf '#\n5\n6\n7\n8\n'; sleep 5; printf '1\n'; sleep 5; printf '7\n'; sleep 3; echo h; sleep 4 ) | pjsua --id sip:$UE2_MSISDN@$DOMAIN --registrar sip:$DOMAIN:5060 $BASE --username $UE2_MSISDN --password $UE2_KI --local-port 5062 --outbound=sip:$PCSCF_IP:5060\;lr > /tmp/pjR3.log 2>&1 &"
wait_pj 25 pjR3.log "Call 0 state changed to CONFIRMED"; RR3=$?
sleep 10
VMS_PIN_LOG=$(docker logs --since 60s "$FREESWITCH" 2>&1 | grep -a "VMS_PIN ok" | head -1)
report "$([ $RR3 -eq 0 ] && [ -n "$VMS_PIN_LOG" ] && echo 0 || echo 1)" "FEAT-02: recuperación con PIN (0100004)" "$([ -n "$VMS_PIN_LOG" ] && echo 'VMS_PIN ok en log FreeSWITCH' || echo 'PIN no autenticado')"
kill_sip; sleep 1

echo "=================== Resultado ==================="
printf "PASS: %s   FAIL: %s\n" "$PASS" "$FAIL"
if [ "$FAIL" -eq 0 ]; then
  echo "ESTADO: OK — la maqueta supera la prueba"
  exit 0
else
  echo "ESTADO: FALLO — revisar docs/paso_a_paso.md (sección 15)"
  exit 1
fi