# Maqueta Core IMS con Kamailio (P/I/S-CSCF) + PyHSS + Asterisk — Paso a paso

Guía reproducible para levantar una maqueta local de núcleo IMS (Core IMS) en Docker:
registro IMS de un softphone (pjsua) y llamada hacia el Application Server (Asterisk)
pasando por la lógica de filtro inicial (iFC) de PyHSS.

---

## 1. Objetivo y alcance

- Poner en marcha **P-CSCF, I-CSCF y S-CSCF** con Kamailio sobre el dominio
  `ims.mnc001.mcc001.3gppnetwork.org`.
- **PyHSS** como HSS (interfaces Diameter **Cx**: UAR/UAA, MAR/MAA, SAR/SAA) y API REST
  de aprovisionamiento.
- **RTPEngine** como plano de medios (RTP/NAT).
- **Asterisk** como Application Server (AS) invocado por **iFC** para servir un IVR.
- Validar:
  1. Registro IMS del UE (`401` desafío → `200 OK` + `Service-Route`).
  2. Llamada `UE → número 0XXXXXX` que el S-CSCF enruta al AS por iFC, el AS responde
     `200 OK` y reproduce un audio IVR en RTP.

> Alcance NO cubierto: IPsec en la interfaz Gm, Rx/PCRF (QoS), charging/Ro, soporte
> AKAv2, llamada UE→UE (ver `conclusiones.md`).

---

## 2. Prerrequisitos

- Docker con el plugin **`docker compose`** (el binario `docker-compose` del host no se usa).
- Puertos libres: `8080` (API PyHSS) y los de los contenedores mapeados del compose.
- ~4 GB de RAM disponibles.
- Dominio/resolución DNS local resuelta por el contenedor `dns` (BIND) en `172.30.0.2`.

## 3. Estructura del proyecto

```
maqueta-ims/
├── docker-compose.yml
├── .env                     # MC/MNC, dominio, IPs, credenciales de suscriptores
├── dns/                     # zona ims.mnc001.mcc001.3gppnetwork.org (A, SRV _sip._udp)
├── kamailio/                # Dockerfile base (imagen mims_kamailio)
├── icscf/ scscf/ pcscf/     # inits + configs Kamailio de cada CSCF
├── pyhss/                   # maqueta_ifc.xml (plantilla iFC) + scripts de aprovisionamiento
├── asterisk/                # AS: pjsip.conf, extensions.conf, ivr_bienvenida.wav, voicemail.conf (format=wav), prompts vm-* + beep
├── softphone/               # pjsua
├── interfaz/                # mims_ui (Flask + Docker SDK): app.py con API VMS/media, static/ con el reproductor
├── rtpengine/ mysql/ scripts/
└── docs/                    # documentación (este archivo, manual_interfaz, arquitectura, conclusiones, guiones)
```

## 4. Red (mims_network `172.30.0.0/24`)

| Servicio          | IP           | Puerto / nota                              |
|-------------------|--------------|---------------------------------------------|
| dns (BIND)        | 172.30.0.2   | 53/udp                                      |
| redis             | 172.30.0.3   | 6379 (PyHSS)                                |
| mysql             | 172.30.0.4   | 3306 (BD `icscf` de selectores de S-CSCF)   |
| pyhss_api         | 172.30.0.5   | 8080 API REST                               |
| icscf             | 172.30.0.6   | SIP UDP/TCP 4060 → Diameter 3869            |
| scscf             | 172.30.0.7   | SIP UDP 6060 → Diameter 3870                |
| pcscf             | 172.30.0.8   | SIP UDP 5060                                |
| asterisk (AS)     | 172.30.0.9   | SIP UDP 5060                                |
| softphone (pjsua) | 172.30.0.10  | SIP UDP 5061/5062/5063 (por proceso)        |
| rtpengine         | 172.30.0.11  | 2223/udp                                    |
| pyhss_diameter    | 172.30.0.12  | 3868 (Cx)                                   |
| pyhss_hss         | 172.30.0.13  | HSS (SQLite compartida con API)             |
| ui (mims_ui)      | 172.30.0.14  | 8888 interno (mapeado al host `8090`)       |

Dominio: `ims.mnc001.mcc001.3gppnetwork.org` (MCC `001`, MNC `01`).

## 5. Construcción de imágenes

```bash
# Imagen de Kamailio (herlesupreeth/docker_kamailio:master, Kamailio 6.2.0-dev1, Ubuntu)
# MODIFICA la infra del nodo (P/I/S-CSCF). Construir SIEMPRE con docker build:
cd maqueta-ims/kamailio && docker build -t mims_kamailio .

# Nodo Application Server:
cd maqueta-ims/asterisk && docker build -t mims_asterisk .
```

> ⚠️ **No usar `docker compose build kamailio`**: el compose no define servicio `kamailio`
> (da `no such service`). Además, al reconstruir la imagen hay que recrear los
> contenedores CSCF con `--force-recreate` (si no, reusan la imagen vieja del mismo tag).

## 6. Arranque

```bash
cd maqueta-ims
docker compose up -d --force-recreate        # primera vez (o tras cambios de imagen)
docker compose ps
```

Tras editar configs de los CSCF/Asterisk se re-ejecuta el init con:
```bash
docker compose up -d --force-recreate icscf scscf pcscf   # o restart asterisk
```

Estado esperado: **todos `Up`**. P-CSCF loguea *"Successfully bound to PCSCF IPSEC module"*;
I-CSCF y S-CSCF cierran corridores Diameter contra `pyhss_diameter:3868`.

## 7. DNS

La zona `ims_zone` define, entre otros:

```
@             1D IN A      PCSCF_IP        ; el A del DOMINIO va en "@" (apex)
_sip._udp     1D IN SRV 0 0 4060 icscf     ; _sip._udp.ims.mnc001...
```

Verificación:
```bash
dig @172.30.0.2 ims.mnc001.mcc001.3gppnetwork.org A +short          # 172.30.0.8
dig @172.30.0.2 _sip._udp.ims.mnc001.mcc001.3gppnetwork.org SRV     # icscf:4060
```

> ⚠️ El nombre relativo `ims` NO es el apex (sería `ims.ims.mnc001...`). El registro A del
> dominio debe declararse con `@`.

## 8. Aprovisionamiento de PyHSS

### 8.1 API REST (http://localhost:8080)

```bash
# APN "internet"
curl -X PUT http://localhost:8080/apn/ -d '{"apn":"internet","apn_ambr_downlink":100000000,"apn_ambr_uplink":50000000,"apn_qos_qci":9}'

# Vectores de autenticación (campo "ki" = password digest del UE)
curl -X PUT http://localhost:8080/auc/ -d '{"ki":"8baf473f2f8fd09487cccbd7097c6862","opc":"61f0f589e23b2bd9c35fe9f2d09db0c1","amf":"8000","sqn":7091}'
curl -X PUT http://localhost:8080/auc/ -d '{"ki":"2a6ab8297e0d15c7a12eef0d8a12b143","opc":"61f0f589e23b2bd9c35fe9f2d09db0c1","amf":"8000","sqn":7091}'

# Suscriptores EPS + IMS (ifc_path = plantilla iFC; se rellena por Jinja2 por IMSI/MSISDN)
curl -X PUT http://localhost:8080/subscriber/     -d '{"imsi":"001011234567890","msisdn":"0010100001","apn_list":["internet"],"ip":0,"serving_mme_ip":0,"default_bearer_qos_qci":9}'
curl -X PUT http://localhost:8080/ims_subscriber/ -d '{"imsi":"001011234567890","msisdn":"0010100001","msisdn_list":"0010100001","ifc_path":"maqueta_ifc.xml"}'
curl -X PUT http://localhost:8080/subscriber/     -d '{"imsi":"001011234567891","msisdn":"0010100002","apn_list":["internet"],"ip":0,"serving_mme_ip":0,"default_bearer_qos_qci":9}'
curl -X PUT http://localhost:8080/ims_subscriber/ -d '{"imsi":"001011234567891","msisdn":"0010100002","msisdn_list":"0010100002","ifc_path":"maqueta_ifc.xml"}'
```

### 8.2 Asignar S-CSCF (el PUT `ims_subscriber` NO acepta el campo `scscf`)

Tabla SQLite `ims_subscriber` (singular), columnas `scscf` / `scscf_realm`:

```bash
docker exec mims_pyhss_hss python3 - <<'EOF'
import sqlite3
c = sqlite3.connect('/var/lib/pyhss/hss.db')
scscf  = 'sip:scscf.ims.mnc001.mcc001.3gppnetwork.org'
realm  = 'ims.mnc001.mcc001.3gppnetwork.org'
c.execute("UPDATE ims_subscriber SET scscf=?, scscf_realm=? WHERE imsi='001011234567890'", (scscf, realm))
c.execute("UPDATE ims_subscriber SET scscf=?, scscf_realm=? WHERE imsi='001011234567891'", (scscf, realm))
c.commit(); print(c.total_changes, "filas actualizadas")
EOF
```

### 8.3 Plantilla iFC (`pyhss/maqueta_ifc.xml`)

Debe declarar como IMPU, además de `sip:MSISDN@dominio` y `tel:MSISDN`, la **IMPU del IMSI**
(`sip:IMSI@dominio`). Sin ella, el S-CSCF falla al guardar el registro
(`ERROR ... Error processing REGISTER`; el UE recibe `500 Server error on UAR select next S-CSCF`).
El fichero está montado en el contenedor (`/opt/pyhss/maqueta_ifc.xml`), por lo que se
relee dinámicamente en cada SAR.

## 9. Base de datos MySQL `icscf` (selección de S-CSCF en I-CSCF)

Schema desde el propio paquete de la imagen (`/usr/local/src/kamailio/misc/examples/ims/icscf/icscf.sql`)
y datos mínimos:

```sql
-- s_cscf: URI completa (host:puerto + transport) que devuelven las UAA del I-CSCF.
-- OBLIGATORIO que coincida con HSS_SCSCF_POOL (docker-compose) para que el
-- módulo ims_icscf lo parsee como host limpio (ver §14).
INSERT INTO s_cscf (id, name) VALUES (1, 'sip:scscf.ims.mnc001.mcc001.3gppnetwork.org:6060;transport=udp');
-- dominio de confianza (reduce las LIR/RTR a la red propia)
INSERT INTO nds_trusted_domains (id, trusted_domain) VALUES (1, 'ims.mnc001.mcc001.3gppnetwork.org');
-- capacidades del S-CSCF (0 y 1)
INSERT INTO s_cscf_capabilities (id_s_cscf, capability) VALUES (1,0),(1,1);
```

Verificación:
```bash
docker exec mims_mysql mysql -u root -prootpass icscf -e "SELECT * FROM s_cscf;"
```

## 10. Interfaz de operación (mims_ui)

Panel web (en español) para operar la maqueta sin terminal: estado de los nodos,
**prueba E2E de 13 checks** (incluye VMS), registro de UEs, llamada de prueba al AS,
prueba del buzón de voz (pestaña **VMS**), provisión de suscriptores en PyHSS y logs
de los contenedores. Acceso: **http://localhost:8090**.

```bash
# La interfaz arranca con el resto del compose; reconstruir tras tocar interfaz/app.py:
docker compose up -d --build --force-recreate ui
```

- Backend **Flask** + **Docker SDK** (usa el socket `/var/run/docker.sock`); los
  valores de los UEs se persisten en el volumen `ui_config` (`/var/lib/ims-ui/config.json`).
- Documentación y API: `results/manual_interfaz.md`.
- La misma validación se ejecuta por terminal con `bash scripts/test_maqueta.sh`
  (salida texto, `exit 0` si todo pasa). Ambos usan la misma batería de checks.

## 11. Registro IMS (pjsua = UE)

El UE registra con AOR = IMPU del IMSI (el UAR del primer REGISTER usa el header To como
identity de respaldo; con el AOR del MSISDN el UAR no encuentra al suscriptor → 403).

UE1:
```bash
docker exec -d mims_softphone sh -c 'pjsua \
  --id sip:001011234567890@ims.mnc001.mcc001.3gppnetwork.org \
  --registrar sip:ims.mnc001.mcc001.3gppnetwork.org:5060 \
  --realm ims.mnc001.mcc001.3gppnetwork.org \
  --username 001011234567890 \
  --password 8baf473f2f8fd09487cccbd7097c6862 \
  --local-port 5061 --no-tcp --null-audio --log-level 4 >/tmp/pj1.log 2>&1'
```

Esperado en el log del UE:
```
SIP/2.0 100 Trying
SIP/2.0 401 Unauthorized - Challenging the UE
SIP/2.0 100 Trying
SIP/2.0 200 OK
Service-Route: <sip:orig@scscf.ims.mnc001.mcc001.3gppnetwork.org:6060;lr>
sip:001011234567890@ims.mnc001.mcc001.3gppnetwork.org: registration success, status=200 (OK)
```

Flujo Diameter que lo sostiene (visto en `mims_pyhss_hss`):
`UAR`/`UAA` → selección de S-CSCF; `MAR`/`MAA` → vectores de autenticación (401);
`SAR`/`SAA` → perfil del suscriptor + iFC (200 OK).

UE2 (mismo comando cambiando IMSI `...891`, ki `2a6ab8297e0d15c7a12eef0d8a12b143`,
`--local-port 5062`).

> Notas pjsua:
> - NO existe `--no-video`; usar `--null-audio`.
> - Para colgar/auto-quit: `tail -f /dev/null | pjsua ...` mantiene el stdin abierto
>   (si el stdin llega a EOF el CLI cuelga las llamadas y se desregistra).

## 12. Llamada al AS (IVR) por iFC

Con UE1 registrado, llamar a un número de la familia `0XXXXXX` (el AS contesta e invoca
el IVR de bienvenida):

```bash
# Llamada determinista: el UE lanza pjsua, espera el 200/REGISTER (provider del pipe)
# y solo entonces ordena la llamada por la consola ('m' + URI), evitando el 403 del
# S-CSCF. --outbound fuerza el paso del INVITE por el P-CSCF (RTPEngine).
docker exec -d mims_softphone sh -c "rm -f /tmp/pjC.log; ( until grep -aq 'Response msg 200/REGISTER' /tmp/pjC.log 2>/dev/null; do sleep 0.2; done; echo m; sleep 0.5; echo 'sip:0100002@ims.mnc001.mcc001.3gppnetwork.org'; sleep 20 ) | pjsua \
  --id sip:001011234567890@ims.mnc001.mcc001.3gppnetwork.org \
  --registrar sip:ims.mnc001.mcc001.3gppnetwork.org:5060 \
  --realm ims.mnc001.mcc001.3gppnetwork.org \
  --username 001011234567890 \
  --password 8baf473f2f8fd09487cccbd7097c6862 \
  --local-port 5061 --no-tcp --null-audio --log-level 4 \
  --outbound=sip:172.30.0.8:5060\;lr \
  > /tmp/pjC.log 2>&1 &"
```

Esperado en el UE: `CALLING → CONNECTING → CONFIRMED` (tras `100 Trying` y `200 OK`) y,
al terminar el IVR, `DISCONNECTED` (razón `200 Normal call clearing`).

Qué sucede en la red:
1. P-CSCF recibe el INVITE, lo enruta y **engage RTPEngine** (reemplazo del SDP).
2. S-CSCF evalúa el **iFC#1** (`INVITE` + `SessionCase 0` → AS) y enruta el INVITE al AS
   (`sip:asterisk.ims.mnc001.mcc001.3gppnetwork.org:5060`); log: *"RTPEngine engaged for Application Server"*.
3. Asterisk reconoce al S-CSCF por IP (identify `172.30.0.7` → endpoint `ims_as`)
   y ejecuta el contexto `ims-in`: `Answer()` + `Playback(ivr_bienvenida)` + `Hangup()`.
4. `200 OK` sube hasta el UE, se cursa el `ACK` y fluye RTP bidireccional por RTPEngine.

Verificación en Asterisk:
```bash
docker exec mims_asterisk asterisk -rx "pjsip show endpoint ims_as"
docker logs mims_asterisk                      # Seeking... Executing [0100002@ims-in...] -> Playback(ivr_bienvenida)
```

Verificación de registro en S-CSCF:
```bash
docker logs mims_scscf | grep -E "registered|impurecord" | tail
```

## 13. VMS: buzón de voz en el AS (Asterisk app_voicemail)

El mismo `context ims-in` enruta por iFC el número **`0100003`** a `VoiceMail`,
reutilizando el endpoint `ims_as` (pjsip). El flujo: `Answer()` → `Playback(ivr_bienvenida)`
→ `VoiceMail(0100003@default,su)` (salto de saludo del usuario + grabación directa).
Al terminar, la app guarda `msg0000.wav`/`msg0000.txt` en
`/var/spool/asterisk/voicemail/default/0100003/INBOX`.

Requisitos de la app (autocontenidos por `asterisk_init.sh` al arrancar el contenedor):
1. **Prompts de voz**: Asterisk reparte frases `vm-*` (por ejemplo `vm-theperson`,
   `vm-isunavail`, ...). Sin ellas la app aborta (`Spawn extension ... exited non-zero`).
   Se dejan versiones planas de 1 s en `asterisk/vm-*.wav` + `beep.wav` (bind `/mnt/asterisk` → sonidos).
2. **Audio real del llamante**: con `--null-audio` pjsua no manda RTP y la app abandona
   la grabación (`Recording was 0 seconds long`). Para la prueba E2E se genera un **tono de
   45 s** (`left_msg.wav`) que el softphone inyecta con `--play-file --auto-play`.
3. **cdr-csv**: el módulo cdr_csv escribe en `/var/log/asterisk/cdr-csv` (creado en `asterisk_init.sh`).
4. **`format=wav`** en `voicemail.conf`: graba los mensajes como **PCM16 lineal 8 kHz
   mono** (`msgNNNNN.wav`; `NNNNN` = contador, no duración). El formato antiguo `wav49`
   (GSM) **no se reproduce en el navegador**; da igual que el reproductor de la
   interfaz (pestaña **VMS**) los sirva por `GET /api/vms/media?mailbox=…&msg=…`
   (la GUI sustituye la duración por un cálculo ≈ tamaño/16000).
5. **Menaje desde la web**: `POST /api/vms/audio` recibe un WAV PCM16 8 kHz (el
   navegador lo convierte desde la grabación del micrófono o de un archivo mp3/wav/
   webm/ogg). El servidor antepone `PROMPT_PAD_S = 4` s de silencio (el AS tarda eso
   en pasar `Answer → Wait → Playback → vm-* → beep`) y lo inyecta como
   `/tmp/web_msg.wav` en el softphone — **sin tocar** `left_msg.wav` (tono 45 s),
   así la prueba E2E sigue siendo determinista. `vms_call(say_ms=…)` usa
   `--play-file /tmp/web_msg.wav` y cuelga `duración + padding + 3` s.

Prueba manual determinista (misma técnica que §12):
```bash
# 1) tono (generarlo en el contenedor asterisk y copiarlo al softphone)
docker exec mims_asterisk python3 -c "import struct,math,wave; SR=8000; F=bytearray()
for i in range(SR*45):
    t=i/SR; v=int(9000*math.sin(2*math.pi*420*t)*(0.9 if int(t*2)%2 else 0.35)); F+=struct.pack('<h',v)
wave.open('/tmp/tone.wav','wb').writeframes(bytes(F))" 2>/dev/null
docker cp mims_asterisk:/tmp/tone.wav /tmp/ && docker cp /tmp/tone.wav mims_softphone:/tmp/left_msg.wav
docker exec mims_asterisk rm -f /var/spool/asterisk/voicemail/default/0100003/INBOX/msg*.*

# 2) llamada UE1 -> 0100003
docker exec -d mims_softphone sh -c "rm -f /tmp/pjV.log; ( until grep -aq 'Response msg 200/REGISTER' /tmp/pjV.log 2>/dev/null; do sleep 0.2; done; echo m; sleep 0.7; echo 'sip:0100003@ims.mnc001.mcc001.3gppnetwork.org'; sleep 18; echo h; sleep 4 ) | pjsua \
  --id sip:001011234567890@ims.mnc001.mcc001.3gppnetwork.org --registrar sip:ims.mnc001.mcc001.3gppnetwork.org:5060 \
  --realm ims.mnc001.mcc001.3gppnetwork.org --username 001011234567890 --password 8baf473f2f8fd09487cccbd7097c6862 \
  --local-port 5061 --no-tcp --null-audio --log-level 4 --play-file /tmp/left_msg.wav --auto-play \
  --outbound=sip:172.30.0.8:5060\;lr > /tmp/pjV.log 2>&1 &"
docker exec mims_softphone sh -c 'until grep -q "Call 0 state changed to CONFIRMED" /tmp/pjV.log; do sleep 1; done; echo OK'
# 3) comprobar el mensaje
docker exec mims_asterisk ls -l /var/spool/asterisk/voicemail/default/0100003/INBOX/
# 4) en el log de Asterisk se ve: NoOp(VMS...) -> Answer -> Wait -> Playback(ivr_bienvenida)
#    -> VoiceMail("0100003@default,su") -> vm-theperson -> vm-isunavail -> beep -> msg0000.wav
```

## 14. Comandos útiles

```bash
docker compose ps
docker logs --since 60s mims_pcscf
docker logs mims_pyhss_hss | grep -E "MAR|SAR|UAR"
docker exec mims_softphone grep -E "200 OK|registration success" /tmp/pj1.log
docker exec mims_asterisk asterisk -rx "pjsip show endpoints"
docker exec mims_icscf ss -lunp   # y scscf/pcscf
docker exec mims_asterisk ls /var/spool/asterisk/voicemail/default/0100003/INBOX/  # VMS
```

## 15. Solución de problemas (errores vistos en esta maqueta)

| Síntoma                                                  | Causa / solución                                                      |
|----------------------------------------------------------|-----------------------------------------------------------------------|
| `no such service: kamailio` al `compose build`           | La imagen se construye con `docker build -t mims_kamailio ./kamailio` |
| El P-CSCF no arranca (modparams/funciones desconocidas)  | Base 6.2.0-dev1: ver adaptaciones en `pcscf/kamailio_pcscf.cfg` y `route/rtp.cfg` (ipsec fuera del ifdef, `delete_delay` comentado, bloque `sdp_iterator_*` comentado, sin `$sdp(c:ip)`) |
| `[[: not found` en los inits (sh)                        | entrypoint `/bin/bash` en el compose (dash no soporta `[[`)           |
| `could not resolve 'ICSCF_IP'` en `kamailio_icscf.cfg`   | El init del icscf no hace sed de `ICSCF_IP` en ese fichero → usar IP fija `listen=udp:172.30.0.6:4060` |
| `getent` no resuelve dentro del softphone                 | DNS integrado con caché; recrear dns (`--force-recreate dns`) tras tocar la zona |
| UE recibe `504` en el REGISTER (I-CSCF nunca ve el REGISTER) | El UE debe registrar con R-URI el **dominio** (no la IP del P-CSCF): `--registrar sip:ims.mnc001.mcc001.3gppnetwork.org:5060` |
| `500 Server error on UAR select next S-CSCF`             | iFC sin la IMPU del IMSI: `update_contacts` del S-CSCF falla (`Error processing REGISTER`). Añadir `<Identity>sip:IMSI@dominio</Identity>` a la plantilla |
| `403 Forbidden - HSS User Unknown`                        | AOR/To = MSISDN en el primer REGISTER; el UAR busca por IMSI. Registrar con AOR = IMPU del IMSI |
| Asterisk no carga el endpoint `ims_as`                    | `trust_id_incoming` no existe en Asterisk 22 → quitarlo de `pjsip.conf` |
| `Playback` falla (no encuentra el archivo)                | Copiar `ivr_bienvenida.wav` (8 kHz) a `/var/lib/asterisk/sounds/` (se hace en `asterisk_init.sh`) |
| pjsua cuelga la llamada al momento                         | stdin cerrado (EOF) → pjsua se marcha. Usar `tail -f /dev/null | pjsua ...` |
| La llamada no responde y el diálogo se destruye en S-CSCF | Verificar iFC y que el AS responda (log asterisk); comprobar identify del S-CSCF (172.30.0.7) |
| `403 Forbidden - You must register first with a S-CSCF` en el INVITE | pjsua llamó **antes** de registrar (race). Registrar primero y ordenar la llamada por consola ('m') cuando el log tenga `200/REGISTER` (launcher determinista de §12) |
| La llamada funciona pero el check «RTPEngine engaged (P-CSCF)» falla | El INVITE va **directo al S-CSCF** por la Service-Route, sin pasar por el P-CSCF. Añadir `--outbound=sip:172.30.0.8:5060;lr` al pjsua de la llamada |
| `bad_uri: [scscf.ims.mnc001...]` o `bad_uri: [172.30.0.7:6060]` en el I-CSCF al registrar | El módulo `ims_icscf` (Kamailio 6.2.0-dev1) parsea mal el S-CSCF del pool. Workaround consolidado: (1) `HSS_SCSCF_POOL` y `s_cscf` como URI completa `sip:scscf.${IMS_DOMAIN}:6060;transport=udp` (nunca IP desnuda ni nombre sin puerto); (2) `use_dns_cache=off` en `kamailio_icscf.cfg` (el resolver interno enfría/usa cache rota y NO consulta DNS); (3) `route[set_scscf_dst]` que reescribe `$ru`/`$du` a la URI canónica e inyectarlo en las ramas de relay de REGISTER/registro inicial (UAR y LIR success, `register_failure` con `I_scscf_select("1")`, y el `I_scscf_select("0")` de la lista guardada dentro de `route[register]`) |
| `500 Error forwarding to SCSCF` / `400 Bad Request URI` en S-CSCF tras añadir el pool | Evolución del fix anterior: el módulo dejaba el RURI sin esquema o con host inválido. El `route[set_scscf_dst]` + `$ru` (solo para REGISTER, donde la ruta la devuelve la UAA) arregla la cadena completa: 401 (MAR) → 200 OK (SAR), 403 y 500 desaparecen |
| `Spawn extension (ims-in, 0100003, 5) exited non-zero` en VoiceMail | Faltan los prompts `vm-*` (`vm-theperson`, `vm-isunavail`, ...). Poner `asterisk/vm-*.wav` (1 s) para que `asterisk_init.sh` los copie a los sonidos |
| `Recording was 0 seconds long but needs to be at least 2` (VMS) | Con `--null-audio` pjsua no genera audio RTP. Usar `--play-file left_msg.wav --auto-play` (tono 45 s) como fuente de la grabación |
| Contenedores de infraestructura caídos tras un rato | Reinicios/caídas durante la demo; por eso `restart: unless-stopped` está en los 13 servicios del compose |