#!/bin/sh
# ue.sh <1|2> [opciones pjsua extra...] — UE IMS de la maqueta (pjsua parcheado).
#
# Perfil 3GPP del UE (TS 24.229 §5.1.1, TS 33.203):
#   IMPU (From/To)      sip:<MSISDN>@dominio
#   IMPI (Authorization) <IMSI>@dominio, enviado desde el 1er REGISTER (--use-ims)
#   Autenticación       IMS-AKA Digest-AKAv1-MD5 con K/OPc/AMF de la USIM
#   Seguridad Gm        sec-agree + IPsec ESP (hmac-sha-1-96, ealg null)
#   Contact             +g.3gpp.icsi-ref (MMTEL) y +g.3gpp.smsip (RFC 3840)
#   PANI                3GPP-E-UTRAN-FDD con utran-cell-id-3gpp (MCC|MNC|TAC|ECI)
#
# Las claves son los valores de prueba provisionados en PyHSS (.env y
# interfaz/app.py); no son credenciales reales.
DOMAIN=ims.mnc001.mcc001.3gppnetwork.org
# P-CSCF: IP de la tarea (no la VIP de Swarm: ESP no atraviesa IPVS); en compose
# local, la IP fija del contenedor.
PCSCF=${IMS_PCSCF_IP:-$(getent ahostsv4 tasks.mims3_pcscf 2>/dev/null | awk 'NR==1{print $1}')}
PCSCF=${PCSCF:-172.32.0.8}
OPC=61f0f589e23b2bd9c35fe9f2d09db0c1
UE=$1; shift
case "$UE" in
  1) MSISDN=${UE1_MSISDN:-0010100001}; IMSI=${UE1_IMSI:-001011234567890}; KI=${UE1_KI:-8baf473f2f8fd09487cccbd7097c6862}; BASE=20000 ;;
  2) MSISDN=${UE2_MSISDN:-0010100002}; IMSI=${UE2_IMSI:-001011234567891}; KI=${UE2_KI:-2a6ab8297e0d15c7a12eef0d8a12b143}; BASE=30000 ;;
  *) echo "uso: $0 <1|2> [opciones pjsua]" >&2; exit 2 ;;
esac
# Cada sesión del UE usa puertos protegidos nuevos (port-s par, port-c = port-s+1),
# como un terminal que se reinicia: el P-CSCF no puede confundir la sesión con
# SA de un registro anterior. port-s es también el --local-port de pjsua.
PORT_S=${IMS_PORT_S:-$(( BASE + ($(od -An -N2 -tu2 /dev/urandom) % 4000) * 2 ))}
PORT_C=$(( PORT_S + 1 ))

# IP local = origen de la ruta hacia el P-CSCF. En Swarm el contenedor tiene la
# red overlay (ruta al P-CSCF) y docker_gwbridge (ruta por defecto); sin fijarla,
# pjsua publica la IP de gwbridge en Via/Contact y las SA IPsec se instalan con
# un origen que no coincide con el tráfico real (TS 33.203 §7.1).
LOCAL_IP=$(ip -4 route get "$PCSCF" 2>/dev/null |
  awk '{ for (i = 1; i <= NF; i++) if ($i == "src") { print $(i + 1); exit } }')
[ -n "$LOCAL_IP" ] || { echo "sin ruta IPv4 hacia P-CSCF $PCSCF" >&2; exit 1; }

# Restos de una ejecución anterior (SA, NAT y conntrack) del mismo UE.
IPSEC=/mnt/softphone/ims-ipsec.sh          # versión del repo (bind-mount)
export IMS_IPSEC_SCRIPT="$IPSEC"
sh "$IPSEC" flush "$PORT_S"

export IMS_AKA_K="$KI" IMS_AKA_OPC="$OPC" IMS_AKA_AMF=8000
export IMS_SECAGREE=1 IMS_PORT_S="$PORT_S" IMS_PORT_C="$PORT_C"
export IMS_PANI="3GPP-E-UTRAN-FDD; utran-cell-id-3gpp=001010001000019B"

# stdout por línea: la UI y test_maqueta.sh leen el log mientras pjsua corre y lo
# terminan con kill -9; con buffer de bloque se perdería el final (Service-Route).
STDBUF=$(command -v stdbuf >/dev/null 2>&1 && echo "stdbuf -oL -eL")
exec $STDBUF pjsua \
  --id "sip:$MSISDN@$DOMAIN" \
  --registrar "sip:$DOMAIN" \
  --realm "$DOMAIN" \
  --username "$IMSI@$DOMAIN" \
  --password "aka" \
  --use-ims \
  --local-port "$PORT_S" \
  --bound-addr "$LOCAL_IP" --ip-addr "$LOCAL_IP" \
  --outbound "sip:$PCSCF:5060;lr" \
  --contact-params ';+g.3gpp.icsi-ref="urn%3Aurn-7%3A3gpp-service.ims.icsi.mmtel";+g.3gpp.smsip' \
  --reg-timeout 600 \
  --no-tcp --null-audio --log-level 4 \
  "$@"
