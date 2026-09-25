#!/bin/bash
# UE1 llama a un MSISDN/no registrado. El S-CSCF aplica el iFC (AS Frontera
# Kamailio -> FreeSWITCH) y FreeSWITCH responde como Application Server (IVR).
# Ejecutar dentro de softphone: docker exec -it mims3_softphone /mnt/softphone/scripts/test_call_ue1_to_ue2.sh

set -e
DEST=${1:-0100002}
DOMAIN=${IMS_DOMAIN:-ims.mnc001.mcc001.3gppnetwork.org}
PCSCF=${PCSCF_IP:-172.32.0.8}
API=${2:-$DEST}

echo "== INVITE de UE1 hacia $DEST (no registrado) por P-CSCF $PCSCF =="

# Verificar que UE1 está registrado (Contact en el S-CSCF)
docker logs mims3_scscf --tail 200 | grep -q "ims_registrar_scscf.*$DEST" && true

cd /mnt/softphone/scenarios
sipp "$PCSCF:5060" -sf invite.xml \
  -s "$DEST@$DOMAIN" -au "001011234567890" -ap "${UE1_KI:-8baf473f2f8fd09487cccbd7097c6862}" -realm "$DOMAIN" \
  -i "$(hostname -I | awk '{print $1}')" -p 5062 \
  -m 1 -l 1 -nostdin -trace_msg -trace_err -timeout 45 \
  -t u1 -rtp_echo || {
    echo "Llamada fallida - revisar: docker logs mims3_scscf / mims3_asfront / mims3_freeswitch" >&2
    exit 1
  }
echo "== Fin INVITE UE1 -> $DEST =="