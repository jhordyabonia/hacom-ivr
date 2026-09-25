#!/bin/bash
# Registro de un UE (UE1) contra la maqueta IMS. Prueba el flujo completo:
# UE -> P-CSCF -> I-CSCF -> S-CSCF (con desafío digest MD5 contra PyHSS).
# Ejecutar dentro del contenedor softphone:  docker exec -it mims3_softphone /mnt/softphone/scripts/test_register_ue1.sh

set -e
IMSI=${UE1_IMSI:-001011234567890}
KI=${UE1_KI:-8baf473f2f8fd09487cccbd7097c6862}
DOMAIN=${IMS_DOMAIN:-ims.mnc001.mcc001.3gppnetwork.org}
PCSCF=${PCSCF_IP:-172.32.0.8}
ID="sip:${IMSI}@${DOMAIN}"

echo "== Registro IMS UE1: $ID via P-CSCF $PCSCF =="
echo "-- DNS:"
getent hosts pcscf.${DOMAIN} 2>/dev/null || true
getent hosts icscf.${DOMAIN} 2>/dev/null || true

if command -v pjsua >/dev/null; then
  echo "-- pjsua (digest estándar)"
  timeout 35 pjsua \
    --id "$ID" \
    --registrar "sip:${PCSCF}:5060" \
    --realm "$DOMAIN" \
    --username "$IMSI" \
    --password "$KI" \
    --local-port 5061 \
    --no-tcp --no-udp-transports --no-video --no-audio \
    --auto-answer 200 --duration 30 \
    --app-log-level 3 --log-level 3 2>&1 | tee /tmp/ue1_register.log
else
  echo "-- sipp"
  cd /mnt/softphone/scenarios
  sipp "$PCSCF:5060" -sf register.xml \
    -s "$IMSI@$DOMAIN" -au "$IMSI" -ap "$KI" -realm "$DOMAIN" \
    -i "$(hostname -I | awk '{print $1}')" -p 5062 \
    -m 1 -l 1 -nostdin -trace_msg -trace_err -timeout 30
fi
echo "== Fin registro UE1 =="