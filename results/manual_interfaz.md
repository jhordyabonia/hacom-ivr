# Manual de la interfaz de operación (mims_ui)

Interfaz web para operar y validar la maqueta Core IMS sin usar comandos: muestra el
estado de la red, lanza la **prueba E2E** (13/13 checks), registra los UEs, hace una
llamada de prueba, valida el **buzón de voz (VMS)**, provisiona suscriptores en PyHSS
y consulta los logs de los nodos.

- Acceso: **http://localhost:8090**
- Contenedor: `mims_ui` (IP `172.30.0.14`, puerto interno `8888`).
- Stack: **Flask** (backend) + **Docker SDK** + frontend estático (HTML/JS/CSS) en español.

---

## 1. Arranque

```bash
# La maqueta completa, incluida la interfaz (servicio `ui` del compose):
docker compose up -d --force-recreate

# Solo la interfaz (tras editar interfaz/app.py o los estáticos):
cd maqueta-ims
docker compose up -d --build --force-recreate ui
```

La interfaz usa el **socket de Docker** (`/var/run/docker.sock`) para ejecutar la
prueba dentro de los contenedores; no necesita credenciales de los nodos. El `.env`
del proyecto define dominio, IPs y valores por defecto de los UEs.

## 2. Pestañas

| Pestaña       | Qué hace                                                                 |
|---------------|--------------------------------------------------------------------------|
| **Estado**    | Contenedores (13) con estado/imagen, resolución DNS del dominio (A → P-CSCF) y listeners SIP/UDP de S-CSCF, I-CSCF, P-CSCF y asterisk. |
| **Prueba E2E**| Ejecuta la validación completa (misma batería que `scripts/test_maqueta.sh`): 13 comprobaciones con detalle de cada una y resultado global OK/FAIL. |
| **Operación** | Acciones: registro de UE1/UE2, llamada de prueba `UE → 0100002` (IVR del Asterisk) y "detener" (mata los procesos pjsua). Muestra las últimas líneas relevantes del log del UE. |
| **VMS**       | Estado de los buzones (listado `msg*.wav` con hora/size/duración) y de los prompts `vm-*`; **reproductor por mensaje** (pulsar ▶; sirve `GET /api/vms/media`) y botón **Prueba VMS** (UE1 → 0100003). Un segundo panel, **"Enviar un mensaje desde la web"**, permite **grabar con el micrófono** (MediaRecorder) o **seleccionar un archivo de audio** (mp3/wav/webm/ogg…); el navegador lo convierte a PCM16 8 kHz y `POST /api/vms/audio` lo inyecta al softphone y lo graba en el buzón con la llamada real. |
| **Configuración** | Edita IMSI/MSISDN/ki/puerto de UE1 y UE2 (persistido en el volumen `ui_config` → `/var/lib/ims-ui/config.json`), provisión de ambos suscriptores en PyHSS (idempotente) e información de la iFC. |
| **Logs**      | Selector de contenedor + número de líneas; vuelca la cola del log.        |

### Prueba E2E (13 comprobaciones)

1. Contenedores arriba (13/13).
2. Resolución DNS del dominio → `172.30.0.8` (P-CSCF).
3. Listener SIP/UDP **S-CSCF** `:6060`.
4. Listener SIP/UDP **I-CSCF** `:4060`.
5. Listener SIP/UDP **P-CSCF** `:5060`.
6. Listener SIP/UDP **Asterisk** `:5060`.
7. Registro IMS **UE1** (`401 → 200 OK + Service-Route`).
8. Registro IMS **UE2** (`200 OK`).
9. Llamada `UE1 → AS` (diálogo **CONFIRMED**).
10. Asterisk reproduce el **IVR** (`Playing 'ivr_bienvenida.slin'`).
11. **RTPEngine engaged (P-CSCF)** (medios reemplazados por RTPEngine).
12. **VMS**: llamada `UE1 → 0100003` (diálogo **CONFIRMED** vía iFC).
13. **VMS**: mensaje de voz grabado en la bandeja (`msg*.wav: 0 → 1`).

> La comprobación "RTPEngine engaged" requiere que el INVITE pase por el P-CSCF.
> La llamada de prueba arranca pjsua con `--outbound=sip:172.30.0.8:5060;lr` para
> garantizarlo; si se quita ese parámetro, el INVITE va directo al S-CSCF por la
> Service-Route y esa comprobación falla (la llamada sigue funcionando).

## 3. API REST

| Método y ruta                | Descripción                                                              |
|------------------------------|--------------------------------------------------------------------------|
| `GET  /health`               | `200` si el socket de Docker está disponible (si no, `503`).              |
| `GET  /api/status`           | Estado de contenedores, DNS y listeners en JSON.                         |
| `POST /api/test`             | Ejecuta la prueba E2E y devuelve `{results, ok}`.                        |
| `GET  /api/config`           | UEs cargados (por defecto + sobreescritos por `config.json`), dominio e iFC. |
| `POST /api/config`           | Actualiza campos de los UEs (JSON, p.ej. `{"1":{"ki":"..."}}`).          |
| `POST /api/config/provision` | Provisiona UE1/UE2 en PyHSS (idempotente).                               |
| `POST /api/actions/register` | Registra un UE (`{"ue":"1"}`). Devuelve líneas clave del log.            |
| `POST /api/actions/call`     | Llamada determinista (`{"ue":"1","dest":"0100002"}`). Devuelve líneas del diálogo. |
| `POST /api/actions/stop`     | Detiene todos los procesos pjsua.                                        |
| `GET  /api/vms`              | Estado de buzones (`mailboxes[].list` con `name/size/modified/duration_s`) y prompts `vm-*`. |
| `GET  /api/vms/media?mailbox=0100003&msg=msg0000.wav` | Sirve el audio del mensaje como `audio/wav` (PCM16 8 kHz mono; el navegador lo reproduce). Valida el nombre con `msg\d+\.wav` y bloquea `..`/`/`. |
| `POST /api/vms/audio`      | Multipart `audio` (WAV PCM16 8 kHz, 1.5–120 s) + `ue` + `dest`. Lo inyecta al softphone y llama; la grabación queda en el buzón. Devuelve `{ok, duration_s, confirmed, messages_before/after}`. |
| `POST /api/actions/vms`      | Prueba VMS: `{"ue":"1","dest":"0100003"}` → llama, graba y devuelve `messages_before/after` + líneas del diálogo. |
| `GET  /api/logs?name=...&tail=N` | Últimas `N` líneas del log del contenedor (por defecto `mims_pcscf`). |

## 4. Flujo de uso recomendado

1. **Estado** → comprobar 13/13 contenedores y listeners en verde.
2. **Configuración** → revisar los datos de UE1/UE2 (IMSIs, kis, puertos SIP).
3. **Configuración → Provisionar** (primera vez o tras reconstruir la BD PyHSS).
4. **Operación** → registrar UE1 y UE2 (verde = `200 OK + Service-Route`).
5. **Prueba E2E** → lanzar y esperar **13/13 OK**.
6. (Opcional) **VMS** → botón *Prueba VMS*, confirmar el incremento de mensajes y
   pulsar ▶ en el mensaje para escucharlo. Para un **mensaje propio**: pestaña VMS →
   *Enviar un mensaje desde la web* → 🎙 Grabar (o 📂 seleccionar archivo) →
   *Enviar al buzón 0100003*; al terminar la llamada el audio aparece con ▶.
7. Si algo falla: pestaña **Logs** y tabla de errores de `results/paso_a_paso.md` §15.

## 5. Notas

- **Grabaciones VMS**: `voicemail.conf` usa `format=wav`, así que la app guarda los
  mensajes como **PCM16 lineal a 8 kHz mono** (`msgNNNNN.wav` + `msgNNNNN.txt`), que
  el reproductor del navegador descodifica nativamente (el formato antiguo GSM `wav49`
  NO es reproducible en Chrome). El `NNNNN` es el contador de mensajes, no la duración:
  la GUI calcula la duración aproximada a partir del tamaño.
- **Cómo detecta el registro**: el backend espera la llegada de
  `Response msg 200/REGISTER` + `Service-Route` en `/tmp/pj<X>.log` del softphone
  (pjsua con pipe no imprime la línea de "registration success").
- **Llamada determinista**: pjsua recibe la orden de llamar (`m` + URI) por su consola
  (pipe) **después** de completar el registro. Llamar al arrancar provoca
  `403 - You must register first with a S-CSCF`.
- **Volumen `ui_config`**: `config.json` sobrevive a `--force-recreate`; se puede
  editar a mano (`docker exec mims_ui cat /var/lib/ims-ui/config.json`).
- **Privilegios**: el contenedor solo necesita el socket; no se mapean otros puertos
  de los nodos.
- El mismo flujo se puede ejecutar por terminal con
  `bash scripts/test_maqueta.sh` (salida texto, exit 0 si todo pasa).