#!/bin/sh
# ims-ipsec.sh — SA IPsec ESP del UE hacia el P-CSCF (TS 33.203 §7, modo transporte).
#
# Invocado por pjsua (ims_ext.c) al recibir un 401 con Security-Server:
#   ims-ipsec.sh setup UE_IP P_IP port_uc port_us spi_uc spi_us \
#                port_pc port_ps spi_pc spi_ps alg ealg IK CK
#   ims-ipsec.sh flush <port_us>          (al arrancar el UE: borra todo lo suyo)
#   ims-ipsec.sh init <port_us> <port_uc> <P_IP>  (puerto cliente desde el 1er REGISTER)
#
# Pares de SA (TS 33.203 §7.1):
#   UE:port_uc -> P:port_ps  spi_ps   |  P:port_ps -> UE:port_uc  spi_uc
#   UE:port_us -> P:port_pc  spi_pc   |  P:port_pc -> UE:port_us  spi_us
# Re-autenticación (TS 33.203 §7.4): el juego nuevo se instala junto al vigente,
# que se conserva hasta la siguiente negociación (el P-CSCF puede responder aún
# por él); el juego anterior a ese se retira.
set -e
STATE_DIR=/tmp/ims-ipsec

flush() { # $1 = port_us
  d="$STATE_DIR/$1"
  for f in "$d/prev.undo" "$d/cur.undo"; do
    [ -f "$f" ] && sh "$f" >/dev/null 2>&1
    rm -f "$f"
  done
  rm -f "$d/prev.ports" "$d/cur.ports"
  nft delete table ip "ims_$1" 2>/dev/null || true
}

if [ "$1" = "flush" ]; then flush "$2"; exit 0; fi
# init <port_us> <port_uc> <P_IP>: antes de cualquier SA el UE ya envía sus
# peticiones (REGISTER inicial no protegido) desde port_uc (TS 33.203 §7.1, UDP).
if [ "$1" = "init" ]; then
  T="ims_$2"
  nft delete table ip "$T" 2>/dev/null || true
  {
    echo "table ip $T {"
    echo "  chain out { type route hook output priority -150;"
    echo "    ip daddr $4 udp sport $2 udp dport 5060 udp sport set $3 meta mark set 0x33"
    echo "  }"
    echo "  chain rawout { type filter hook output priority -300; ip daddr $4 udp sport { $2, $3 } notrack; }"
    echo "  chain in { type filter hook prerouting priority -300;"
    echo "    ip saddr $4 udp dport { $2, $3 } notrack"
    echo "    ip saddr $4 udp dport $3 udp dport set $2"
    echo "  }"
    echo "}"
  } | nft -f -
  exit 0
fi
[ "$1" = "setup" ] || { echo "uso: $0 setup ...|flush <port_us>" >&2; exit 2; }
shift
UE=$1; P=$2; PORT_UC=$3; PORT_US=$4; SPI_UC=$5; SPI_US=$6
PORT_PC=$7; PORT_PS=$8; SPI_PC=$9; shift 9
SPI_PS=$1; ALG=$2; EALG=$3; IK=$4; CK=$5

case "$ALG" in
  hmac-sha-1-96) AALG="hmac(sha1)"; AKEY="0x${IK}00000000" ;;   # IK || 32 bits a cero
  hmac-md5-96)   AALG="hmac(md5)";  AKEY="0x${IK}" ;;
  *) echo "alg no soportado: $ALG" >&2; exit 3 ;;
esac
case "$EALG" in
  null)         ENC="enc cipher_null \"\"" ;;
  aes-cbc)      ENC="enc cbc(aes) 0x${CK}" ;;
  *) echo "ealg no soportado: $EALG" >&2; exit 3 ;;
esac

D="$STATE_DIR/$PORT_US"
mkdir -p "$D"
# Generaciones: se retira la anterior a la vigente; la vigente pasa a "prev".
[ -f "$D/prev.undo" ] && sh "$D/prev.undo" >/dev/null 2>&1
rm -f "$D/prev.undo"
[ -f "$D/cur.undo" ] && mv "$D/cur.undo" "$D/prev.undo"
UNDO="$D/cur.undo"
: > "$UNDO"

sa() { # src dst spi
  echo "ip xfrm state delete src $1 dst $2 proto esp spi $3" >> "$UNDO"
  # Un SPI puede repetirse si el P-CSCF se reinició (vuelve a 4096): se
  # sustituye cualquier SA residual con el mismo (destino, SPI).
  ip xfrm state delete src "$1" dst "$2" proto esp spi "$3" 2>/dev/null || true
  eval ip xfrm state add src "$1" dst "$2" proto esp spi "$3" mode transport \
    auth-trunc "'$AALG'" "$AKEY" 96 $ENC
}
sa "$UE" "$P" "$SPI_PS"
sa "$UE" "$P" "$SPI_PC"
sa "$P" "$UE" "$SPI_UC"
sa "$P" "$UE" "$SPI_US"

pol() { # src dst proto sport dport dir spi
  echo "ip xfrm policy delete src $1/32 dst $2/32 proto $3 sport $4 dport $5 dir $6" >> "$UNDO"
  ip xfrm policy delete src "$1/32" dst "$2/32" proto "$3" sport "$4" dport "$5" dir "$6" 2>/dev/null || true
  ip xfrm policy add src "$1/32" dst "$2/32" proto "$3" sport "$4" dport "$5" dir "$6" \
    tmpl src "$1" dst "$2" proto esp spi "$7" mode transport
}
for proto in 17 6; do   # udp, tcp (sin depender de /etc/protocols)
  pol "$UE" "$P" $proto "$PORT_UC" "$PORT_PS" out "$SPI_PS"
  pol "$UE" "$P" $proto "$PORT_US" "$PORT_PC" out "$SPI_PC"
  pol "$P" "$UE" $proto "$PORT_PS" "$PORT_UC" in "$SPI_UC"
  pol "$P" "$UE" $proto "$PORT_PC" "$PORT_US" in "$SPI_US"
done

# Puertos protegidos sin NAT con estado (TS 33.203 §7.1, caso UDP: el UE envía
# sus peticiones desde port_uc y recibe en port_us). pjsua usa un único socket
# (port_us), así que se reescriben los puertos sin conntrack con nftables:
#   salida : dport 5060 -> port_ps vigente ; peticiones a port_ps -> sport port_uc
#   entrada: dport port_uc -> port_us
# La cadena "route" re-enruta (y re-evalúa la política xfrm) solo si cambia la
# dirección o la marca: por eso cada reescritura fija meta mark.
# Se conservan los puertos del juego previo (diálogos con su Record-Route).
PREV_PS=""; PREV_UC=""
[ -f "$D/prev.ports" ] && . "$D/prev.ports"
[ -f "$D/cur.ports" ] && { . "$D/cur.ports"; PREV_PS=$CUR_PS; PREV_UC=$CUR_UC; }
echo "PREV_PS=$PREV_PS; PREV_UC=$PREV_UC" > "$D/prev.ports"
echo "CUR_PS=$PORT_PS; CUR_UC=$PORT_UC" > "$D/cur.ports"
T="ims_$PORT_US"
nft delete table ip "$T" 2>/dev/null || true
{
  echo "table ip $T {"
  echo "  chain out { type route hook output priority -150;"
  echo "    ip daddr $P udp sport $PORT_US udp dport 5060 udp dport set $PORT_PS meta mark set 0x33"
  echo "    ip daddr $P udp sport $PORT_US udp dport $PORT_PS udp sport set $PORT_UC meta mark set 0x33"
  [ -n "$PREV_PS" ] && echo "    ip daddr $P udp sport $PORT_US udp dport $PREV_PS udp sport set $PREV_UC meta mark set 0x33"
  echo "  }"
  echo "  chain rawout { type filter hook output priority -300; ip daddr $P udp sport { $PORT_US, $PORT_UC } notrack; }"
  echo "  chain in { type filter hook prerouting priority -300;"
  echo "    ip saddr $P udp dport { $PORT_US, $PORT_UC } notrack"
  echo "    ip saddr $P udp dport $PORT_UC udp dport set $PORT_US"
  [ -n "$PREV_UC" ] && echo "    ip saddr $P udp dport $PREV_UC notrack udp dport set $PORT_US"
  echo "  }"
  echo "}"
} | nft -f -
exit 0
