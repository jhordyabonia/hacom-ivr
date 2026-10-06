#!/bin/bash
# test_maqueta.sh — Prueba simple y verificable de la maqueta Core IMS
# Valida: contenedores, DNS, listeners SIP, registro IMS con IMS-AKA + IPsec ESP
# (TS 33.203), llamada UE->AS (iFC) con IVR en FreeSWITCH, menú DTMF (FEAT-01),
# buzón 0100003 y VMS completo por MSISDN (FEAT-02: deposit por iFC
# terminating-unregistered, MWI por SUBSCRIBE/NOTIFY y recuperación con PIN).
# Uso:  bash scripts/test_maqueta.sh   (salida exit 0 si todo pasa)

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
cd "$ROOT" || exit 2

DOMAIN="ims.mnc001.mcc001.3gppnetwork.org"
UE1_IMSI="001011234567890"; UE1_MSISDN="0010100001"
UE2_IMSI="001011234567891"; UE2_MSISDN="0010100002"; UE2_PIN="5678"
# Los UEs se lanzan con softphone/scripts/ue.sh (pjsua parcheado): IMPU =
# sip:<MSISDN>@dominio, IMPI = <IMSI>@dominio, IMS-AKA (K/OPc/AMF) y sec-agree
# con SA IPsec ESP hacia el P-CSCF (TS 24.229 §5.1.1.2, TS 33.203 §7).
UE="/mnt/softphone/scripts/ue.sh"
SOFTPHONE="mims3_softphone"
FREESWITCH="mims3_freeswitch"
ASFRONT="mims3_asfront"
PCSCF="mims3_pcscf"
PCSCF_IP="172.32.0.8"
VMS_DIR="/var/lib/freeswitch/storage/vms/0100003/INBOX"

PASS=0; FAIL=0
say()    { echo "[ $1 ]"; }
report() { # $1=0/1  $2=operacion  $3=detalle
  if [ "$1" -eq 0 ]; then PASS=$((PASS+1)); printf "  [PASS] %s  (%s)\n" "$2" "$3";
  else FAIL=$((FAIL+1)); printf "  [FAIL] %s  (%s)\n" "$2" "$3"; fi
}
# Los guiones de UE terminan con 'q' (pjsua cuelga y se des-registra por la SA);
# kill_sip espera esa salida ordenada y solo entonces fuerza.
kill_sip() {
  local i=0
  while [ "$i" -lt 12 ] && docker exec "$SOFTPHONE" pgrep -f pjsua >/dev/null 2>&1; do sleep 1; i=$((i+1)); done
  docker exec "$SOFTPHONE" sh -c 'pkill -9 -f pjsua; true' 2>/dev/null
}
wait_pj() { # $1=timeout_s  $2=log  $3=patron ; cuando el patrón aparece en /tmp/$2
  local t="$1"; local i=0
  while [ "$i" -lt "$t" ]; do
    if docker exec "$SOFTPHONE" sh -c "grep -aq \"$3\" /tmp/$2" 2>/dev/null; then return 0; fi
    sleep 1; i=$((i+1))
  done
  return 1
}
# ue_run <ue> <log> <guion> [opciones pjsua]: el guion (comandos de consola de
# pjsua) arranca cuando el REGISTER obtiene 200 OK.
ue_run() {
  local ue="$1" log="$2" script="$3"; shift 3
  docker exec -d "$SOFTPHONE" sh -c "rm -f /tmp/$log; ( until grep -aq 'Response msg 200/REGISTER' /tmp/$log 2>/dev/null; do sleep 0.2; done; $script ) | $UE $ue $* > /tmp/$log 2>&1"
}
fs_cli() { docker exec "$FREESWITCH" fs_cli -x "$1" 2>/dev/null | tr -d '\r'; }
vm_count() { # mensajes (nuevos+guardados) del buzón $1; vm_boxcount "all" = new:saved:new-urg:saved-urg
  fs_cli "vm_boxcount default/$1@$DOMAIN|all" | awk -F: 'NF>=2{print $1+$2; exit} END{if(NR==0)print 0}'
}

echo "=================== Test maqueta Core IMS (maqueta-ims-3) ==================="
echo "Dominio: $DOMAIN"

say "PASO 0/6 — Estado limpio (sin UEs, llamadas ni suscripciones de ejecuciones previas)"
kill_sip
# pjsua no cancela su suscripción MWI al salir: el AS (FreeSWITCH) se reinicia
# para no arrastrar diálogos/suscripciones de una ejecución anterior hacia
# contactos ya des-registrados (init.sh arranca sin el estado SIP persistido).
docker restart "$FREESWITCH" >/dev/null
i=0; until docker exec "$FREESWITCH" fs_cli -x "sofia status profile external" 2>/dev/null | grep -q "RUNNING\|sip:mod_sofia" || [ "$i" -ge 60 ]; do sleep 1; i=$((i+1)); done
sleep 3

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

say "PASO 4/6 — Registro IMS de UE1 (IMS-AKA 401 -> SA IPsec -> 200 OK + Service-Route)"
kill_sip
ue_run 1 pj1.log "sleep 4; echo q; sleep 3"
wait_pj 20 pj1.log "registration success, status=200"; R1=$?
docker exec "$SOFTPHONE" sh -c "grep -aq 'algorithm=AKAv1-MD5' /tmp/pj1.log && grep -aq 'Service-Route' /tmp/pj1.log"; R1B=$?
docker exec "$SOFTPHONE" sh -c "grep -aq 'SA IPsec ESP establecidas' /tmp/pj1.log"; R1S=$?
N_SA=$(docker exec "$PCSCF" sh -c "ip xfrm state 2>/dev/null | grep -c '^src'" 2>/dev/null || echo 0)
report "$([ $R1 -eq 0 ] && [ $R1B -eq 0 ] && echo 0 || echo 1)" "registro UE1 IMS-AKA (401 AKAv1-MD5 + 200 OK + Service-Route)" "IMPI $UE1_IMSI@$DOMAIN"
report "$([ $R1S -eq 0 ] && [ "${N_SA:-0}" -ge 4 ] && echo 0 || echo 1)" "sec-agree: SA IPsec ESP UE<->P-CSCF" "SA en P-CSCF: ${N_SA:-0}"
sleep 4; kill_sip; sleep 1

say "PASO 5/6 — Llamada UE1 -> AS (iFC -> IVR en FreeSWITCH)"
# Determinista: pjsua registra; un escritor retrasado por el pipe ordena la llamada
# ('m') al ver 200 OK del REGISTER. El 'sleep' final mantiene abierto el stdin
# (al cerrarse pjsua cuelga: 487 Session already DISCONNECTED).
ue_run 1 pjC.log "echo m; sleep 0.5; echo 'sip:0100002@$DOMAIN'; sleep 14; echo q; sleep 4"
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
# En pjsua '#' abre "DTMF strings to send" y la línea siguiente envía los dígitos
# (RFC 4733). Consumido por play_and_get_digits y persistido como CDR de opción.
IVR_N0=$(docker exec "$FREESWITCH" sh -c "wc -l < /mnt/freeswitch/logs/ivr_cdr.jsonl 2>/dev/null || echo 0")
ue_run 1 pjF.log "echo m; sleep 0.7; echo 'sip:0100002@$DOMAIN'; sleep 5; printf '#\n1\n'; sleep 10; echo q; sleep 4"
wait_pj 25 pjF.log "Call 0 state changed to CONFIRMED"; RF=$?
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
ue_run 1 pjV.log "echo m; sleep 0.7; echo 'sip:0100003@$DOMAIN'; sleep 18; echo h; sleep 2; echo q; sleep 4" --play-file /tmp/left_msg.wav --auto-play
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
# 1. UE2 se registra y se des-registra (REGISTER Expires: 0 protegido por la SA)
#    para que el S-CSCF lo tenga como no registrado.
# 2. UE1 llama a UE2 -> S-CSCF terminating-unregistered -> iFC P40 -> asfront ->
#    FreeSWITCH: mod_voicemail graba en el buzón del MSISDN de UE2.
# 3. UE2 se registra con --mwi: SUBSCRIBE message-summary -> iFC P10 -> AS de
#    buzón -> NOTIFY "Messages-Waiting: yes" por el diálogo (S-CSCF, P-CSCF, SA).
# 4. UE2 llama a 0100004, autentica con PIN (DTMF), escucha (1) y borra (7) ->
#    el buzón queda vacío y llega NOTIFY "Messages-Waiting: no".
# Buzón de UE2 vacío al empezar (mod_voicemail: borra ficheros y su índice).
# vm_list: creado:leído:usuario:dominio:carpeta:fichero:uuid:cid_nombre:cid_num:duración
for u in $(fs_cli "vm_list $UE2_MSISDN@$DOMAIN" | awk -F: '{print $7}' | grep -E '^[0-9a-f-]{36}$'); do
  fs_cli "vm_delete $UE2_MSISDN@$DOMAIN $u" >/dev/null
done
VM2_0=$(vm_count "$UE2_MSISDN"); VM2_0=${VM2_0:-0}
ue_run 2 pjD2.log "sleep 1; echo q; sleep 4"
wait_pj 20 pjD2.log "Unregistration sent\|unregistration success\|registration success, status=200 (OK), will re-register in 0"; RD2=$?
kill_sip
# El S-CSCF retira el contacto des-registrado en su temporizador de usrloc
# (timer_interval de ims_usrloc_scscf): se espera a que el IMPU deje de figurar como registrado.
i=0
while [ "$i" -lt 90 ] && docker exec mims3_scscf kamcmd -s unix:/var/run/kamailio/kamailio_ctl \
      ulscscf.showimpu "sip:$UE2_MSISDN@$DOMAIN" 2>/dev/null | grep -q 'state: registered'; do sleep 1; i=$((i+1)); done
ue_run 1 pjV2.log "echo m; sleep 0.7; echo 'sip:$UE2_MSISDN@$DOMAIN'; sleep 18; echo h; sleep 2; echo q; sleep 4" --play-file /tmp/left_msg.wav --auto-play
wait_pj 25 pjV2.log "Call 0 state changed to CONFIRMED"; RV2C=$?
VM2_AFTER=$VM2_0; i=0
while [ "$VM2_AFTER" -le "$VM2_0" ] && [ "$i" -lt 15 ]; do
  sleep 2; VM2_AFTER=$(vm_count "$UE2_MSISDN"); VM2_AFTER=${VM2_AFTER:-0}; i=$((i+1))
done
DEP_LOG=$(docker logs --since 60s "$FREESWITCH" 2>&1 | grep -a "VMS_DEPOSIT start id=$UE2_MSISDN" | head -1)
report "$([ $RV2C -eq 0 ] && [ -n "$DEP_LOG" ] && echo 0 || echo 1)" "FEAT-02: llamada UE1 -> UE2 no registrado desviada al buzón" "iFC terminating-unregistered -> VMS_DEPOSIT id=$UE2_MSISDN"
report "$([ "$VM2_AFTER" -gt "$VM2_0" ] && echo 0 || echo 1)" "FEAT-02: mensaje en buzón mod_voicemail de UE2" "vm_boxcount: $VM2_0 -> $VM2_AFTER"
kill_sip; sleep 1
# 3+4 en una sola sesión de UE2 (registro + MWI + recuperación).
ue_run 2 pjR2.log "sleep 6; echo m; sleep 0.7; echo 'sip:0100004@$DOMAIN'; sleep 4; printf '#\n$UE2_PIN\n'; sleep 7; printf '#\n1\n'; sleep 22; printf '#\n7\n'; sleep 5; echo h; sleep 8; echo q; sleep 4" --mwi
wait_pj 20 pjR2.log "Messages-Waiting: yes"; RMWI=$?
report "$([ $RMWI -eq 0 ] && echo 0 || echo 1)" "FEAT-02: MWI (SUBSCRIBE/NOTIFY message-summary) al UE2" "$([ $RMWI -eq 0 ] && echo 'NOTIFY Messages-Waiting: yes' || echo 'sin NOTIFY MWI')"
wait_pj 30 pjR2.log "Call 0 state changed to CONFIRMED"; RR3=$?
VMS_PIN_LOG=""; VM2_END=$VM2_AFTER; i=0
while [ "$i" -lt 60 ]; do
  sleep 1; i=$((i+1))
  [ -z "$VMS_PIN_LOG" ] && VMS_PIN_LOG=$(docker logs --since 60s "$FREESWITCH" 2>&1 | grep -a "VMS_PIN ok caller=$UE2_MSISDN" | head -1)
  VM2_END=$(vm_count "$UE2_MSISDN"); VM2_END=${VM2_END:-0}
  [ -n "$VMS_PIN_LOG" ] && [ "$VM2_END" -eq 0 ] && break
done
wait_pj 15 pjR2.log "Messages-Waiting: no"; RMWI0=$?
report "$([ $RR3 -eq 0 ] && [ -n "$VMS_PIN_LOG" ] && [ "$VM2_END" -eq 0 ] && echo 0 || echo 1)" "FEAT-02: recuperación con PIN (0100004), escucha y borrado" "$([ -n "$VMS_PIN_LOG" ] && echo "VMS_PIN ok; buzón $VM2_AFTER -> $VM2_END" || echo 'PIN no autenticado')"
report "$([ $RMWI0 -eq 0 ] && echo 0 || echo 1)" "FEAT-02: MWI actualizado tras borrar" "$([ $RMWI0 -eq 0 ] && echo 'NOTIFY Messages-Waiting: no' || echo 'sin NOTIFY de buzón vacío')"
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
