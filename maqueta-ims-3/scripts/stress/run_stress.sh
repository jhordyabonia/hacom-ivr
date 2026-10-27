#!/bin/bash
# run_stress.sh — batería de estrés sobre la maqueta DEV (Swarm) desde un cliente por VPN.
#   1. Arranca monitor.py en los 3 nodos (CPU/RAM/red del host + docker stats por contenedor).
#   2. Ejecuta las etapas (reposo, ráfaga de registros, escalones de llamadas IVR, depósitos VMS).
#   3. Recoge los CSV de los nodos y el JSONL de resultados en OUT.
# Uso: run_stress.sh <ues.csv> <dir_salida>
# Requiere: SSH a los nodos (SSH_ASKPASS o clave), VPN activa y abonados de carga
# provisionados con provision_load_ues.py.
set -u
UES="$1"; OUT="$2"; mkdir -p "$OUT"
DIR="$(cd "$(dirname "$0")" && pwd)"
PROXY=192.168.5.231
declare -A NODES=([core]=192.168.5.231 [db]=192.168.5.232 [ivr]=192.168.5.233)
MON_SECS="${MON_SECS:-1500}"
ssh_n(){ ssh -o ConnectTimeout=10 -o LogLevel=ERROR "administrator@$1" "${@:2}"; }
stage(){ echo "$(date +%s.%N | cut -c1-14),$1,$2" >> "$OUT/stages.csv"; echo "[$(date +%T)] $1 $2"; }

echo "t,stage,event" > "$OUT/stages.csv"
for n in "${!NODES[@]}"; do
  ssh_n "${NODES[$n]}" "mkdir -p /tmp/stress && cat > /tmp/stress/monitor.py" < "$DIR/monitor.py"
  ssh_n "${NODES[$n]}" "rm -f /tmp/stress/*.csv; nohup python3 /tmp/stress/monitor.py --node $n --secs $MON_SECS --interval 2 --dir /tmp/stress >/tmp/stress/monitor.log 2>&1 &"
done

lg(){ python3 -I "$DIR/loadgen.py" --proxy $PROXY --ues "$UES" --out "$OUT/results.jsonl" "$@"; }

stage A_reposo start; sleep 60; stage A_reposo end
stage B_registros start; lg --label B_registros --register-only --concurrency 50 --duration 1; stage B_registros end
sleep 15
for c in 10 20 30 40 45; do
  stage "C_ivr_$c" start
  lg --label "C_ivr_$c" --concurrency "$c" --dest 0100002 --hold 20 --duration 120 --gap 1
  stage "C_ivr_$c" end
  sleep 15
done
stage D_vms_20 start
lg --label D_vms_20 --concurrency 20 --dest 0100003 --hold 10 --duration 90 --gap 1
stage D_vms_20 end
sleep 20; stage fin end

for n in "${!NODES[@]}"; do
  ssh_n "${NODES[$n]}" "pkill -f /tmp/stress/monitor.py; cat /tmp/stress/host_$n.csv" > "$OUT/host_$n.csv"
  ssh_n "${NODES[$n]}" "cat /tmp/stress/ctn_$n.csv" > "$OUT/ctn_$n.csv"
done
echo "OK: resultados en $OUT"
