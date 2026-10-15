#!/bin/sh
set -eu

peer=${1:?uso: test_ipsec_route_source.sh <ip-pcscf>}
route=$(ip -4 route get "$peer" 2>/dev/null) || {
  echo "FAIL: no hay ruta IPv4 hacia P-CSCF $peer" >&2
  exit 1
}
local_ip=$(printf '%s\n' "$route" |
  awk '{ for (i = 1; i <= NF; i++) if ($i == "src") { print $(i + 1); exit } }')
[ -n "$local_ip" ] || {
  echo "FAIL: la ruta IPv4 hacia $peer no incluye dirección de origen" >&2
  exit 1
}

if ip xfrm policy 2>/dev/null |
  awk -v src="$local_ip/32" -v dst="$peer/32" '
    $1 == "src" { matches = ($2 == src && $4 == dst) }
    $1 == "dir" && $2 == "out" && matches { found = 1 }
    END { exit !found }
  '
then
  printf 'PASS: política XFRM de salida usa %s -> %s\n' "$local_ip" "$peer"
else
  printf 'FAIL: falta política XFRM de salida para %s -> %s\n' "$local_ip" "$peer" >&2
  exit 1
fi
