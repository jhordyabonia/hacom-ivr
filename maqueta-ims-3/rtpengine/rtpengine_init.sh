#!/bin/bash

# BSD 2-Clause License

# Copyright (c) 2020-2025, Supreeth Herle
# All rights reserved.

# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:

# 1. Redistributions of source code must retain the above copyright notice, this
#    list of conditions and the following disclaimer.

# 2. Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.

# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

set -x
RUNTIME=${1:-rtpengine}

if [ "${SWARM_MODE:-0}" = "1" ]; then
	OVERLAY_IP="$(ip -o -4 addr show dev eth0 scope global | awk 'NR == 1 {split($4, a, "/"); print a[1]}')"
	if [ -z "$OVERLAY_IP" ]; then
		echo "No se pudo determinar la IP overlay de RTPEngine" >&2
		exit 1
	fi
	INTERFACE="$OVERLAY_IP"
	LISTEN_NG="$OVERLAY_IP:2223"
	# Acceso externo: interfaz "ext" en docker_gwbridge con pool propio
	# (publicado en modo host) y la IP del nodo en el SDP; "int" = overlay.
	if [ -n "$EXT_ADVERTISE_IP" ]; then
		EXT_DEV="$(ip route show default | awk 'NR == 1 {print $5}')"
		EXT_IP="$(ip -o -4 addr show dev "$EXT_DEV" scope global | awk 'NR == 1 {split($4, a, "/"); print a[1]}')"
		if [ -z "$EXT_IP" ]; then
			echo "No se pudo determinar la IP externa de RTPEngine" >&2
			exit 1
		fi
		CONFIG_FILE=/etc/rtpengine/rtpengine-maqueta.conf
		cat > "$CONFIG_FILE" <<-EOF
		[rtpengine]
		interfaces-config = interface
		# Ofertas sin respuesta (403/408/604 del lado UE): liberar sus puertos en
		# 60 s, no en 3600 s (por defecto), para no agotar el pool "ext".
		offer-timeout = 60

		[interface-int]
		address = $OVERLAY_IP

		[interface-ext]
		address = $EXT_IP
		advertised = $EXT_ADVERTISE_IP
		port-min = ${RTP_EXT_PORT_MIN:-49900}
		port-max = ${RTP_EXT_PORT_MAX:-49999}
		EOF
	fi
fi

if lsmod | grep xt_RTPENGINE || modprobe xt_RTPENGINE; then
	echo "rtpengine kernel module already loaded."
else
	modprobe xt_RTPENGINE
fi

# Populate options of the rtpengine cli command
[ -z "$INTERFACE" ] && INTERFACE="$(awk 'END{print $1}' /etc/hosts)"
[ -z "$TABLE" ] && TABLE="0"
[ -z "$LISTEN_NG" ] && LISTEN_NG="$(awk 'END{print $1}' /etc/hosts):2223"
[ -z "$PORT_MIN" ] && PORT_MIN="30000"
[ -z "$PORT_MAX" ] && PORT_MAX="40000"
[ -z "$TOS" ] && TOS="184"
[ -z "$PIDFILE" ] && PIDFILE="/run/ngcp-rtpengine-daemon.pid"

LISTEN_CLI="$(awk 'END{print $1}' /etc/hosts):9901"

OPTIONS=""
if [ -n "$CONFIG_FILE" ]; then
	OPTIONS="$OPTIONS --config-file=$CONFIG_FILE"
else
	OPTIONS="$OPTIONS --interface=$INTERFACE"
fi
OPTIONS="$OPTIONS --listen-ng=$LISTEN_NG --listen-cli=$LISTEN_CLI --pidfile=$PIDFILE --port-min=$PORT_MIN --port-max=$PORT_MAX "
OPTIONS="$OPTIONS --table=$TABLE  --tos=$TOS --foreground"

if test "$NO_FALLBACK" = "yes" ; then
	OPTIONS="$OPTIONS --no-fallback"
fi

# Sync docker time
#ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

set +e

# Sync docker time
#ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Ruta estática solo necesaria en despliegues con UPF/EPC (no usados en esta maqueta 4G)
# ip r add ${UE_IPV4_IMS} via ${UPF_IP}
# ip r add ${UE_IPV4_INTERNET} via ${UPF_IP}

set -x

exec $RUNTIME $OPTIONS
