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

[ ${#MNC} == 3 ] && IMS_DOMAIN="ims.mnc${MNC}.mcc${MCC}.3gppnetwork.org" || IMS_DOMAIN="ims.mnc0${MNC}.mcc${MCC}.3gppnetwork.org"
FREESWITCH_IP="${FREESWITCH_HOST:-$FREESWITCH_IP}"
ASFRONT_ALLOWED_CIDR="${ASFRONT_ALLOWED_CIDR:-$SCSCF_IP}"
if [[ "${SWARM_MODE:-0}" == "1" ]]; then
	ASFRONT_IP="$(ip -o -4 addr show dev eth0 scope global | awk 'NR == 1 {split($4, a, "/"); print a[1]}')"
	[[ -n "$ASFRONT_IP" ]] || { echo "No se pudo determinar la IP overlay de AS Frontera" >&2; exit 1; }
fi

mkdir -p /etc/kamailio_asfront
cp /mnt/asfront/asfront.cfg /etc/kamailio_asfront
cp /mnt/asfront/kamailio_asfront.cfg /etc/kamailio_asfront

export IMS_SLASH_DOMAIN=`echo $IMS_DOMAIN | sed 's/\./\\\./g'`

sed -i 's|ASFRONT_LISTEN_IP|'$ASFRONT_IP'|g' /etc/kamailio_asfront/asfront.cfg
sed -i 's|FREESWITCH_IP|'$FREESWITCH_IP'|g' /etc/kamailio_asfront/asfront.cfg
sed -i 's|ASFRONT_ALLOWED_CIDR|'$ASFRONT_ALLOWED_CIDR'|g' /etc/kamailio_asfront/kamailio_asfront.cfg
sed -i 's|SCSCF_IP|'$SCSCF_IP'|g' /etc/kamailio_asfront/asfront.cfg
sed -i 's|IMS_DOMAIN|'$IMS_DOMAIN'|g' /etc/kamailio_asfront/asfront.cfg
sed -i 's|IMS_SLASH_DOMAIN|'$IMS_SLASH_DOMAIN'|g' /etc/kamailio_asfront/asfront.cfg

sed -i 's|MYSQL_IP|'$MYSQL_IP'|g' /etc/kamailio_asfront/asfront.cfg

# La Frontera no requiere BD: solo se sustituyen IPs en asfront.cfg;
# el resto de placeholders en kamailio_asfront.cfg (FREESWITCH_IP, SCSCF_IP)
# se resuelven también dentro de la config principal.
sed -i 's|FREESWITCH_IP|'$FREESWITCH_IP'|g' /etc/kamailio_asfront/kamailio_asfront.cfg
sed -i 's|SCSCF_IP|'$SCSCF_IP'|g' /etc/kamailio_asfront/kamailio_asfront.cfg
sed -i 's|IMS_DOMAIN|'$IMS_DOMAIN'|g' /etc/kamailio_asfront/kamailio_asfront.cfg
sed -i 's|IMS_SLASH_DOMAIN|'$IMS_SLASH_DOMAIN'|g' /etc/kamailio_asfront/kamailio_asfront.cfg

# Swarm: el nodo está en varias redes overlay (IMS e ISC). Kamailio escucha en
# todas ellas y elige el socket de salida por ruta (mhomed), de modo que el
# tráfico ISC sale con la IP de la red ISC y no con la de la red IMS.
if [[ "${SWARM_MODE:-0}" == "1" ]]; then
	echo >> /etc/kamailio_asfront/asfront.cfg   # el .cfg puede no terminar en salto de línea
	DEFAULT_DEV="$(ip -4 route show default | awk '{for (i = 1; i <= NF; i++) if ($i == "dev") {print $(i + 1); exit}}')"
	for EXTRA_IP in $(ip -o -4 addr show scope global | awk -v d="$DEFAULT_DEV" '$2 != d {split($4, a, "/"); print a[1]}'); do
		[[ "$EXTRA_IP" == "$ASFRONT_IP" ]] && continue
		printf 'listen=udp:%s:5060\nlisten=tcp:%s:5060\n' "$EXTRA_IP" "$EXTRA_IP" >> /etc/kamailio_asfront/asfront.cfg
	done
	echo "mhomed=1" >> /etc/kamailio_asfront/asfront.cfg
fi

rm -f /kamailio_asfront.pid
exec kamailio -f /etc/kamailio_asfront/kamailio_asfront.cfg -P /kamailio_asfront.pid -DD -E -e $@