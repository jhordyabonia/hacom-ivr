#!/bin/sh
# FreeSWITCH como AS aplicacion (IVR/VMS) para la Frontera IMS.
# Recibe INVITEs del AS Frontera; sirve 0100002 (IVR) y 0100003 (VMS).

set -e

# 1. Crear directorio de trabajo de FreeSWITCH
mkdir -p /etc/freeswitch /var/run/freeswitch /var/lib/freeswitch /var/log/freeswitch
chown -R freeswitch:freeswitch /var/run/freeswitch /var/lib/freeswitch /var/log/freeswitch 2>/dev/null || true

# 2. Copiar config vanilla a /etc/freeswitch
cp -a /usr/share/freeswitch/conf/vanilla/* /etc/freeswitch/

# 2b. Superponer la configuración versionada de la maqueta (bind-mount
#     ./freeswitch -> /mnt/freeswitch): dialplan, perfiles SIP, voicemail.conf,
#     directorio IMS. Un cambio en el repo se aplica con "docker restart".
cp -a /mnt/freeswitch/conf/. /etc/freeswitch/

# 2a. Swarm: local_ip_v4 se autodetecta por la ruta por defecto (docker_gwbridge),
#     inalcanzable desde el AS Frontera. Se fija la IP de la red overlay IMS.
if [ "${SWARM_MODE:-0}" = "1" ]; then
	DEFAULT_DEV=$(ip route | awk '$1 == "default" {for (i = 1; i <= NF; i++) if ($i == "dev") {print $(i + 1); exit}}')
	OVERLAY_IP=$(ip -o -f inet addr show | awk -v d="$DEFAULT_DEV" '$2 != "lo" && $2 != d {split($4, a, "/"); print a[1]; exit}')
	[ -n "$OVERLAY_IP" ] || { echo "No se pudo determinar la IP overlay de FreeSWITCH" >&2; exit 1; }
	sed -i "s|<include>|<include>\n  <X-PRE-PROCESS cmd=\"set\" data=\"local_ip_v4=$OVERLAY_IP\"/>|" /etc/freeswitch/vars.xml
fi

# 2c. Diálogos/suscripciones SIP de una ejecución anterior (MWI de UEs que ya
#     no existen): el AS arranca sin estado; los UEs vigentes vuelven a suscribirse.
rm -f /var/lib/freeswitch/db/sofia_reg_*.db

# 3. Desactivar mod_signalwire (no tenemos licencia)
sed -i 's|<load module="mod_signalwire"/>|<!-- <load module="mod_signalwire"/> -->|g' /etc/freeswitch/autoload_configs/modules.conf.xml 2>/dev/null || true

# 4. Preparar almacenamiento VMS (volumen montado en /var/lib/freeswitch/storage/vms)
mkdir -p /var/lib/freeswitch/storage/vms/0100003/INBOX
chown -R freeswitch:freeswitch /var/lib/freeswitch/storage/vms 2>/dev/null || true

# 5. Iniciar FreeSWITCH en foreground (logs a stdout para docker logs)
exec freeswitch -nonat -c