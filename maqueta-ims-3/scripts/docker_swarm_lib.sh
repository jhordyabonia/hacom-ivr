#!/bin/bash
# docker_swarm_lib.sh — permite ejecutar test_maqueta.sh contra la maqueta
# desplegada en Docker Swarm (3 nodos DEV: Core IMS, Base de Datos, IVR+VMS).
#
# Se carga desde test_maqueta.sh cuando SWARM_MODE=1. Define una función
# docker() que traduce cada nombre mims3_<servicio> al contenedor de la tarea
# Swarm en ejecución, en el nodo donde corre, y ejecuta el subcomando por SSH.
#
# Requisitos: acceso SSH a los nodos como $SWARM_USER (clave o SSH_ASKPASS).
#   SWARM_MANAGER  IP del manager Swarm   (por defecto 192.168.5.231)
#   SWARM_USER     usuario SSH            (por defecto administrator)
# Uso:  SWARM_MODE=1 bash scripts/test_maqueta.sh

SWARM_MANAGER="${SWARM_MANAGER:-192.168.5.231}"
SWARM_USER="${SWARM_USER:-administrator}"
SWARM_CM_DIR="$(mktemp -d "${TMPDIR:-/tmp}/swarm-ssh.XXXXXX")"
trap 'ssh -O exit -o ControlPath="$SWARM_CM_DIR/%r@%h:%p" "$SWARM_USER@$SWARM_MANAGER" 2>/dev/null; rm -rf "$SWARM_CM_DIR"' EXIT

declare -A SWARM_HOST SWARM_CID

swarm_ssh() { # $1=host [-n: sin stdin], resto = comando remoto (ya escapado)
  local host="$1" opts=(); shift
  [ "${1:-}" = "-n" ] && { opts+=(-n); shift; }
  ssh "${opts[@]}" -o ControlMaster=auto -o ControlPath="$SWARM_CM_DIR/%r@%h:%p" \
      -o ControlPersist=10m -o ConnectTimeout=10 "$SWARM_USER@$host" "$@"
}

swarm_locate() { # $1=mims3_<servicio> -> SWARM_HOST[$1], SWARM_CID[$1]
  local svc="$1" node task host cid
  [ -n "${SWARM_CID[$svc]:-}" ] && return 0
  read -r node task < <(swarm_ssh "$SWARM_MANAGER" -n \
    "docker service ps --filter desired-state=running --no-trunc --format '{{.Node}} {{.ID}}' $svc" 2>/dev/null | head -1)
  [ -n "$task" ] || return 1
  host=$(swarm_ssh "$SWARM_MANAGER" -n "docker node inspect --format '{{.Status.Addr}}' $node" 2>/dev/null)
  cid=$(swarm_ssh "$host" -n "docker ps -q --filter label=com.docker.swarm.task.id=$task" 2>/dev/null | head -1)
  [ -n "$cid" ] || return 1
  SWARM_HOST[$svc]="$host"; SWARM_CID[$svc]="$cid"
}

docker() {
  local sub="$1"; shift
  local args=() svc="" a name
  # `docker restart` sobre el contenedor de una tarea deja huérfanos: Swarm
  # programa una tarea nueva y el contenedor viejo vuelve a arrancar detrás de
  # la misma VIP. En Swarm se reinicia el servicio.
  if [ "$sub" = "restart" ] && [[ "${1:-}" == mims3_* ]]; then
    swarm_ssh "$SWARM_MANAGER" -n "docker service update --force --detach=false $1" >/dev/null
    unset "SWARM_CID[$1]" "SWARM_HOST[$1]"
    return
  fi
  for a in "$@"; do
    if [ -z "$svc" ] && [[ "$a" == mims3_* ]]; then
      name="${a%%:*}"
      swarm_locate "$name" || { echo "swarm: servicio $name sin tarea en ejecución" >&2; return 1; }
      svc="$name"
      a="${SWARM_CID[$svc]}${a#"$name"}"
    fi
    args+=("$a")
  done
  [ -n "$svc" ] || { command docker "$sub" "$@"; return; }

  if [ "$sub" = "cp" ]; then # solo local -> contenedor: docker cp <archivo> mims3_x:<ruta>
    local src="${args[0]}" dst="${args[1]#*:}"
    swarm_ssh "${SWARM_HOST[$svc]}" "docker exec -i ${SWARM_CID[$svc]} sh -c $(printf '%q' "cat > '$dst'")" < "$src"
    return
  fi
  swarm_ssh "${SWARM_HOST[$svc]}" -n "docker $sub $(printf '%q ' "${args[@]}")"
}
