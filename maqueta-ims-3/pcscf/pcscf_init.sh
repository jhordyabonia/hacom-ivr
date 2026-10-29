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

sh -c "echo 1 > /proc/sys/net/ipv4/ip_nonlocal_bind"
sh -c "echo 1 > /proc/sys/net/ipv6/ip_nonlocal_bind"

[ ${#MNC} == 3 ] && EPC_DOMAIN="epc.mnc${MNC}.mcc${MCC}.3gppnetwork.org" || EPC_DOMAIN="epc.mnc0${MNC}.mcc${MCC}.3gppnetwork.org"
[ ${#MNC} == 3 ] && IMS_DOMAIN="ims.mnc${MNC}.mcc${MCC}.3gppnetwork.org" || IMS_DOMAIN="ims.mnc0${MNC}.mcc${MCC}.3gppnetwork.org"
MYSQL_IP="${MYSQL_HOST:-$MYSQL_IP}"
RTPENGINE_IP="${RTPENGINE_HOST:-$RTPENGINE_IP}"
if [[ "${SWARM_MODE:-0}" == "1" ]]; then
	PCSCF_IP="$(ip -o -4 addr show dev eth0 scope global | awk 'NR == 1 {split($4, a, "/"); print a[1]}')"
	[[ -n "$PCSCF_IP" ]] || { echo "No se pudo determinar la IP overlay de P-CSCF" >&2; exit 1; }
	# Keep the IPsec endpoint stable across the task IP and the DNS service VIP.
	for attempt in {1..30}; do
		PCSCF_PUB_IP="$(getent ahostsv4 mims3_pcscf 2>/dev/null | awk 'NR == 1 {print $1}')"
		[[ -n "$PCSCF_PUB_IP" ]] && break
		sleep 1
	done
	[[ -n "$PCSCF_PUB_IP" ]] || { echo "No se pudo determinar la VIP Swarm de P-CSCF" >&2; exit 1; }
	# Acceso externo (softphone por VPN): el 5060 publicado en modo host entra
	# por docker_gwbridge (ruta por defecto), no por la overlay.
	if [[ -n "$EXT_ADVERTISE_IP" ]]; then
		EXT_DEV="$(ip route show default | awk 'NR == 1 {print $5}')"
		PCSCF_EXT_IP="$(ip -o -4 addr show dev "$EXT_DEV" scope global | awk 'NR == 1 {split($4, a, "/"); print a[1]}')"
		[[ -n "$PCSCF_EXT_IP" ]] || { echo "No se pudo determinar la IP externa de P-CSCF" >&2; exit 1; }
	fi
fi

mkdir -p /etc/kamailio_pcscf
cp /mnt/pcscf/pcscf.cfg /etc/kamailio_pcscf
cp /mnt/pcscf/pcscf.xml /etc/kamailio_pcscf
cp /mnt/pcscf/kamailio_pcscf.cfg /etc/kamailio_pcscf
cp -r /mnt/pcscf/route /etc/kamailio_pcscf
cp -r /mnt/pcscf/sems /etc/kamailio_pcscf
cp /mnt/pcscf/tls.cfg /etc/kamailio_pcscf
cp /mnt/pcscf/dispatcher.list /etc/kamailio_pcscf

# Socket externo anunciado con la IP del nodo: Via/Record-Route alcanzables
# desde la VPN. Los UEs de la overlay siguen en el socket PCSCF_LISTEN_IP.
# mhomed: el socket de salida se elige por la ruta al destino (overlay hacia
# el core, gwbridge hacia la VPN), no por el socket de entrada.
if [[ -n "$PCSCF_EXT_IP" ]]; then
	sed -i "/^listen=tcp:PCSCF_LISTEN_IP:5060$/a listen=udp:$PCSCF_EXT_IP:5060 advertise $EXT_ADVERTISE_IP:5060\nlisten=tcp:$PCSCF_EXT_IP:5060 advertise $EXT_ADVERTISE_IP:5060\nmhomed=1" /etc/kamailio_pcscf/pcscf.cfg
fi
sed -i 's|PCSCF_EXT_IP|'$PCSCF_EXT_IP'|g' /etc/kamailio_pcscf/route/rtp.cfg
sed -i 's|PCSCF_EXT_IP|'$PCSCF_EXT_IP'|g' /etc/kamailio_pcscf/route/mo.cfg

while ! mysqladmin ping -h ${MYSQL_IP} --silent; do
	sleep 5;
done

# Sleep until permissions are set
sleep 10;

# Create PCSCF database, populate tables and grant privileges
if [[ -z "`mysql -u root -h ${MYSQL_IP} -qfsBe "SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME='pcscf'" 2>&1`" ]];
then
	mysql -u root -h ${MYSQL_IP} -e "create database pcscf;"
	mysql -u root -h ${MYSQL_IP} pcscf < /usr/local/src/kamailio/utils/kamctl/mysql/standard-create.sql
	mysql -u root -h ${MYSQL_IP} pcscf < /usr/local/src/kamailio/utils/kamctl/mysql/presence-create.sql
	mysql -u root -h ${MYSQL_IP} pcscf < /usr/local/src/kamailio/utils/kamctl/mysql/ims_usrloc_pcscf-create.sql
	mysql -u root -h ${MYSQL_IP} pcscf < /usr/local/src/kamailio/utils/kamctl/mysql/ims_dialog-create.sql
	PCSCF_USER_EXISTS=`mysql -u root -h ${MYSQL_IP} -s -N -e "SELECT EXISTS(SELECT 1 FROM mysql.user WHERE User = 'pcscf' AND Host = '%')"`
	if [[ "$PCSCF_USER_EXISTS" == 0 ]]
	then
		mysql -u root -h ${MYSQL_IP} -e "CREATE USER 'pcscf'@'%' IDENTIFIED WITH mysql_native_password BY 'heslo'";
		mysql -u root -h ${MYSQL_IP} -e "GRANT ALL ON pcscf.* TO 'pcscf'@'%'";
		mysql -u root -h ${MYSQL_IP} -e "FLUSH PRIVILEGES;"
	fi
fi

if [[ ${DEPLOY_MODE} == 5G ]];
then
    sed -i 's|#!define WITH_RX\b|##!define WITH_RX|g' /etc/kamailio_pcscf/pcscf.cfg
	sed -i 's|##!define WITH_N5\b|#!define WITH_N5|g' /etc/kamailio_pcscf/pcscf.cfg
fi

REGISTRATION_EXPIRES_ENV=3600

sed -i 's|PCSCF_LISTEN_IP|'$PCSCF_IP'|g' /etc/kamailio_pcscf/pcscf.cfg
sed -i 's|REGISTRATION_EXPIRES_ENV|'$REGISTRATION_EXPIRES_ENV'|g' /etc/kamailio_pcscf/pcscf.cfg
sed -i 's|SCP_IP|'$SCP_IP'|g' /etc/kamailio_pcscf/pcscf.cfg
sed -i 's|PCSCF_PUB_IP|'$PCSCF_PUB_IP'|g' /etc/kamailio_pcscf/pcscf.cfg
sed -i 's|IMS_DOMAIN|'$IMS_DOMAIN'|g' /etc/kamailio_pcscf/pcscf.cfg
sed -i 's|EPC_DOMAIN|'$EPC_DOMAIN'|g' /etc/kamailio_pcscf/pcscf.cfg
sed -i 's|MYSQL_IP|'$MYSQL_IP'|g' /etc/kamailio_pcscf/pcscf.cfg

sed -i 's|PCSCF_LISTEN_IP|'$PCSCF_IP'|g' /etc/kamailio_pcscf/pcscf.xml
sed -i 's|REGISTRATION_EXPIRES_ENV|'$REGISTRATION_EXPIRES_ENV'|g' /etc/kamailio_pcscf/pcscf.xml
sed -i 's|IMS_DOMAIN|'$IMS_DOMAIN'|g' /etc/kamailio_pcscf/pcscf.xml
sed -i 's|EPC_DOMAIN|'$EPC_DOMAIN'|g' /etc/kamailio_pcscf/pcscf.xml
sed -i 's|PCRF_BIND_PORT|'$PCRF_BIND_PORT'|g' /etc/kamailio_pcscf/pcscf.xml
sed -i 's|PCSCF_BIND_PORT|'$PCSCF_BIND_PORT'|g' /etc/kamailio_pcscf/pcscf.xml

sed -i 's|RTPENGINE_IP|'$RTPENGINE_IP'|g' /etc/kamailio_pcscf/kamailio_pcscf.cfg
sed -i 's|RTPENGINE_IP|'$RTPENGINE_IP'|g' /etc/kamailio_pcscf/route/rtp.cfg

# Add static route to route traffic back to UE as there is not NATing
ip r add ${UE_IPV4_IMS} via ${UPF_IP}
# Route needed for VoWiFi client where internet APN is used
ip r add ${UE_IPV4_INTERNET} via ${UPF_IP}

rm -f /kamailio_pcscf.pid
exec kamailio -f /etc/kamailio_pcscf/kamailio_pcscf.cfg -P /kamailio_pcscf.pid -m 32 -M 1024 -DD -E -e $@

# Sync docker time
#ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone
