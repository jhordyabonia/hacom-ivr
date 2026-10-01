#!/bin/sh
# mwi_notify.sh <box> — Emite MWI (NOTIFY message-summary, RFC 3842) al S-CSCF.
#
# FreeSwitch no dispone de API outbound para NOTIFY en esta versión (sofia global
# sip_notify fue eliminado). Se emite un NOTIFY SIP crudo al S-CSCF por TCP
# (172.32.0.7:6060). El S-CSCF (route[MWI]) decide: reenvía al UE si está
# registrado o encola el MWI hasta el siguiente REGISTER (route[MWI_DELIVER]).
#
# Uso desde dialplan:  system /usr/share/freeswitch/scripts/mwi_notify.sh <box>

BOX="${1:-}"
[ -z "$BOX" ] && exit 1

VMHOST="ims.mnc001.mcc001.3gppnetwork.org"
SCSCF="172.32.0.7"
SCSCF_PORT="6060"
BODY="Messages-Waiting: yes\r\nVoice-Message: 1/0"
NBODY="$(printf '%b' "$BODY" | wc -c)"
BRANCH="z9hG4bK-mwi-$(/bin/busybox date +%s)-$$"
MSG="NOTIFY sip:${BOX}@${VMHOST} SIP/2.0\r\n"
MSG="${MSG}Via: SIP/2.0/TCP 172.32.0.15:5060;branch=${BRANCH}\r\n"
MSG="${MSG}Max-Forwards: 70\r\n"
MSG="${MSG}From: <sip:vms@${VMHOST}>;tag=mwi\r\n"
MSG="${MSG}To: <sip:${BOX}@${VMHOST}>\r\n"
MSG="${MSG}Call-ID: mwi-${BOX}-$$@${VMHOST}\r\n"
MSG="${MSG}CSeq: 1 NOTIFY\r\n"
MSG="${MSG}Event: message-summary\r\n"
MSG="${MSG}Subscription-State: active\r\n"
MSG="${MSG}Content-Type: application/simple-message-summary\r\n"
MSG="${MSG}Content-Length: ${NBODY}\r\n"
MSG="${MSG}\r\n${BODY}"

printf '%b' "$MSG" | /bin/busybox nc -w 2 "$SCSCF" "$SCSCF_PORT" >/dev/null 2>&1
exit 0