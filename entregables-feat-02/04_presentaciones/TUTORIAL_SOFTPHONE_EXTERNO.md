# Tutorial — conectar un softphone externo a la maqueta IMS

Versión en diapositivas: `Tutorial_softphone_externo.pptx`.

## 0. Elegir el camino

| Camino | Cliente | Seguridad | Uso |
|---|---|---|---|
| **A** | UE IMS de la maqueta (pjsua parcheado) | IMS-AKA + IPsec ESP (3GPP) | Demos y pruebas de conformidad |
| **B** | Zoiper / Linphone / MicroSIP | SIP Digest (perfil no-3GPP, TS 33.203 Anexo N) | Solo DEV |

Los softphones comerciales no implementan IMS-AKA ni sec-agree, por eso el camino B
exige activar un perfil que la maqueta trae **desactivado**.

## 1. Paso común: ruta hacia la red de la maqueta (sin NAT)

IPsec ESP no atraviesa NAT sin encapsulado UDP, y el P-CSCF y RTPEngine anuncian
direcciones `172.32.0.x`. Con una ruta, el softphone las alcanza directamente.

En el host de la maqueta:

```bash
sudo sysctl -w net.ipv4.ip_forward=1
sudo iptables -I DOCKER-USER -s <LAN>/24 -d 172.32.0.0/24 -j ACCEPT
```

En el equipo del softphone:

```bash
sudo ip route add 172.32.0.0/24 via <IP-del-host-de-la-maqueta>
ping -c1 172.32.0.8      # P-CSCF
```

## 2. Camino A — UE IMS de la maqueta en otro equipo (Linux + Docker)

```bash
# copiar maqueta-ims-3/softphone al equipo y construir
docker build -t mims3_softphone softphone/
docker run -it --rm --net=host --cap-add NET_ADMIN --cap-add NET_RAW \
  -v "$PWD/softphone:/mnt/softphone" mims3_softphone bash
# dentro del contenedor
/mnt/softphone/scripts/ue.sh 1          # UE1 (ue.sh 2 para UE2)
```

En la consola de pjsua: `m` y luego `sip:0100002@ims.mnc001.mcc001.3gppnetwork.org`
(IVR; DTMF con `#` y el dígito) o `sip:0100004@…` (buzón, PIN de prueba de UE2: 5678).
Esperado en el log: `sec-agree: SA IPsec ESP establecidas` y
`registration success, status=200`.

## 3. Camino B — softphone comercial (solo DEV)

1. Activar el perfil en `maqueta-ims-3/scscf/scscf.cfg`: cambiar
   `##!define WITH_NON3GPP_DIGEST` por `#!define WITH_NON3GPP_DIGEST` y
   `docker restart mims3_scscf`.
2. Cuenta SIP:
   - Usuario / usuario de autenticación: `0010100001` (MSISDN de UE1)
   - Dominio: `ims.mnc001.mcc001.3gppnetwork.org`
   - Proxy de salida: `172.32.0.8:5060`, UDP
   - Contraseña: la clave de prueba `UE1_KI` de `maqueta-ims-3/.env`
   - Códecs: PCMU/PCMA
3. Llamar a `0100002` (IVR) o `0100003` (dejar mensaje).
4. **Al terminar**, volver a `##!define WITH_NON3GPP_DIGEST` y reiniciar el S-CSCF.
   Con el perfil desactivado un cliente Digest recibe `403 Authentication Failed`.

## 4. Diagnóstico

| Síntoma | Causa probable | Acción |
|---|---|---|
| `403 Authentication Failed` | Perfil Digest desactivado | Camino A, o activar el perfil (DEV) |
| Sin respuesta al REGISTER | Falta la ruta a `172.32.0.0/24` | `ip route` y regla `DOCKER-USER` |
| Llamada sin audio | RTP con NAT o firewall | Ruta directa; abrir UDP de RTPEngine |
| `sec-agree: fallo instalando SA` | SA residuales en el UE | `ip xfrm state flush; ip xfrm policy flush` |

Si no es posible enrutar (solo NAT), publicar puertos no basta: habría que configurar
`PCSCF_PUB_IP`/`advertise` en el P-CSCF y la IP pública de RTPEngine, y el camino A
dejaría de funcionar (ESP sin NAT-T). Para ese escenario conviene una VPN de capa 3.
