#!/bin/bash
# capture_iteration_swarm.sh — capture_iteration.sh para la maqueta en Docker Swarm (DEV).
# Uso: bash scripts/capture_iteration_swarm.sh <dir_salida>
#
# El tráfico overlay entre nodos viaja en VXLAN, así que se captura dentro de
# los namespaces de red de las tareas (nodo Core IMS):
#   P-CSCF   : Gm (UE<->P-CSCF, IPsec ESP) y Mw (P-CSCF<->I/S-CSCF)
#   AS-Front : ISC (S-CSCF<->AS-Front) y el tramo AS-Front<->FreeSWITCH
# Ninguna petición se ve en ambos puntos, por lo que la unión no duplica mensajes.
#   tcpdump -i any -s0 -w maqueta_ims.pcap   (por namespace; mergecap une)
#   tshark -r maqueta_ims.pcap -Y sip -w maqueta_ims_sip_only.pcap
#   check_3gpp.py --nodes nodes.json (IPs reales de las tareas) -> check_3gpp.md
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$(mkdir -p "$1" && cd "$1" && pwd)"
export SWARM_MODE=1
. "$SCRIPT_DIR/docker_swarm_lib.sh"

CORE="${SWARM_MANAGER}"
REMOTE_DIR="/tmp/mims3_capture"
swarm_ssh "$CORE" -n "rm -rf $REMOTE_DIR; mkdir -p $REMOTE_DIR"

# Mapa IP -> rol con todas las IPs (redes IMS e ISC) y las VIP de cada servicio.
nodes_json() {
  local svc role ip first=1
  echo "{"
  for pair in softphone:UE pcscf:P-CSCF icscf:I-CSCF scscf:S-CSCF asfront:AS-Front freeswitch:FreeSWITCH; do
    svc="mims3_${pair%%:*}"; role="${pair##*:}"
    swarm_locate "$svc" || continue
    for ip in $(swarm_ssh "${SWARM_HOST[$svc]}" -n \
        "docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' ${SWARM_CID[$svc]}") \
        $(swarm_ssh "$CORE" -n "docker service inspect -f '{{range .Endpoint.VirtualIPs}}{{.Addr}} {{end}}' $svc" | sed 's|/[0-9]*||g'); do
      [ "$first" = 1 ] || echo ","; first=0
      printf '  "%s": "%s"' "$ip" "$role"
    done
  done
  # Swarm hace SNAT a la IP del balanceador de la red (<red>-endpoint) en el
  # tráfico enviado a una VIP. En los dos puntos de captura (nodo Core) solo el
  # S-CSCF envía peticiones a una VIP: al P-CSCF (Path) y al AS-Front (iFC).
  for net in mims3_network mims3_isc; do
    ip=$(swarm_ssh "$CORE" -n "docker network inspect $net" | python3 -c '
import json, sys
for c in json.load(sys.stdin)[0].get("Containers", {}).values():
    if c["Name"].endswith("-endpoint"): print(c["IPv4Address"].split("/")[0])')
    [ -n "$ip" ] && printf ',\n  "%s": "S-CSCF"' "$ip"
  done
  echo; echo "}"
}

for svc in mims3_pcscf mims3_asfront; do
  swarm_locate "$svc" || { echo "sin tarea $svc" >&2; exit 2; }
  name="mims3_tcpdump_${svc#mims3_}"
  swarm_ssh "$CORE" -n "docker rm -f $name >/dev/null 2>&1; docker run -d --name $name \
    --net=container:${SWARM_CID[$svc]} --cap-add=NET_RAW --cap-add=NET_ADMIN \
    -v $REMOTE_DIR:/cap --entrypoint tcpdump mims3_kamailio -i any -s0 -U -w /cap/${svc#mims3_}.pcap >/dev/null"
done
sleep 2
bash "$SCRIPT_DIR/test_maqueta.sh" > "$OUT/test_maqueta.log" 2>&1; RC=$?
sleep 2
swarm_ssh "$CORE" -n "docker stop -t 2 mims3_tcpdump_pcscf mims3_tcpdump_asfront >/dev/null; \
  docker rm mims3_tcpdump_pcscf mims3_tcpdump_asfront >/dev/null"
for f in pcscf asfront; do
  swarm_ssh "$CORE" -n "cat $REMOTE_DIR/$f.pcap" > "$OUT/$f.pcap"
done
nodes_json > "$OUT/nodes.json"

mergecap -F pcap -w - "$OUT/pcscf.pcap" "$OUT/asfront.pcap" > "$OUT/maqueta_ims.pcap"
# SIP protegido por IPsec (ESP con cifrado NULL) y puertos de core forzados a SIP,
# igual que capture_iteration.sh. La overlay de Swarm tiene MTU 1450: el INVITE
# con SDP y el NOTIFY MWI se fragmentan y "-Y sip" solo conserva el último
# fragmento; se añaden los fragmentos previos (MF=1) para poder reensamblar.
tshark -o esp.enable_null_encryption_decode_heuristic:TRUE \
  -d tcp.port==6060,sip -d tcp.port==4060,sip -r - -Y "sip || ip.flags.mf == 1" -w - \
  < "$OUT/maqueta_ims.pcap" > "$OUT/maqueta_ims_sip_only.pcap"
python3 "$SCRIPT_DIR/check_3gpp.py" "$OUT/maqueta_ims_sip_only.pcap" --nodes "$OUT/nodes.json" \
  --json "$OUT/check_3gpp.json" > "$OUT/check_3gpp.md"; RC3=$?
grep -E '^\s*\[(PASS|FAIL)\]|^PASS:' "$OUT/test_maqueta.log"
tail -n 30 "$OUT/check_3gpp.md"
echo "E2E rc=$RC  3GPP rc=$RC3"
exit $(( RC | RC3 ))
