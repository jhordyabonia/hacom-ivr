# Respuesta de la maqueta Core IMS (resultado verificable)

Respuesta a los enunciados de `prompts.md`. Estado: **verde — 13/13 checks**,
validado por `scripts/test_maqueta.sh` (terminal, `exit 0`) y por el botón
**Prueba E2E** de la interfaz (`http://localhost:8090`).

## 1. Core IMS desplegado y funcionando

- Red Docker `172.30.0.0/24` con 13 contenedores (IPs estables: dns .2, redis .3,
  mysql .4, icscf .6, scscf .7, pcscf .8, asterisk .9, ui .14).
- Diameter Cx operativa: **UAR/UAA**, **MAR/MAA** (desafío 401), **SAR/SAA** (perfil + iFC).
- Registro IMS de **UE1** y **UE2**: `100 → 401 → 100 → 200 OK` + `Service-Route`.
- Llamada `UE1 → 0100002`: INVITE por el P-CSCF (RTPEngine anclado) → iFC#1 → AS
  (Asterisk) → `200 OK`/ACK → **Playback del IVR** (`ivr_bienvenida.wav`).

```text
[PASO 1/6] contenedores arriba:        PASS (13/13)
[PASO 2/6] DNS dominio → P-CSCF:       PASS
[PASO 3/6] listeners SIP/UDP:          PASS (scscf:6060, icscf:4060, pcscf:5060, asterisk:5060)
[PASO 4/6] registro IMS UE1/UE2:       PASS (401 → 200 OK + Service-Route)
[PASO 5/6] llamada UE1 → AS:           PASS (CONFIRMED + IVR + RTPEngine)
[PASO 6/6] VMS (0100003):              PASS (CONFIRMED + mensaje grabado)
```

## 2. Registro reparado (causa raíz y workaround)

- **Causa raíz**: el módulo `ims_icscf` (Kamailio 6.2.0-dev1, imagen
  `ghcr.io/herlesupreeth/docker_kamailio:master` de 5 días) construye destinos
  inválidos (`bad_uri` con host+puerto pegados o sin esquema) y mangla el RURI
  del REGISTER en la segunda ronda (`new_t(): uri invalid`). No era DNS ni red
  (A/AAAA/SRV responden rcode 0; tcpdump mostró **0 consultas** del I-CSCF, su
  resolver interno usaba cache rota/negativa).
- **Workaround en configuración** (sin tocar el código fuente):
  1. `use_dns_cache=off` en `kamailio_icscf.cfg`.
  2. `HSS_SCSCF_POOL` y tabla `icscf.s_cscf` = `sip:scscf.<dominio>:6060;transport=udp`.
  3. `route[set_scscf_dst]` (reescribe `$ru` para REGISTER y `$du` siempre) en las
     6 ramas de relay (UAR/LIR success, los dos `I_scscf_select`).
- **Resultado estable**: UE1 y UE2 completan el registro; desaparecieron
  `bad_uri`, `500 Error forwarding to SCSCF` y `400 Bad Request URI`.

## 3. VMS funcionando

- El UE1 llama a `0100003@ims...`; el S-CSCF enruta por la misma iFC al AS.
- Asterisk: `Answer` → `Playback(ivr_bienvenida)` → `VoiceMail(0100003@default,su)`
  → prompts `vm-theperson`/`vm-isunavail` → `beep` → grabación.
- Mensaje guardado: `msg0000.wav` (**PCM16 lineal 8 kHz mono**, reproducible) +
  `msg0000.txt` en `/var/spool/asterisk/voicemail/default/0100003/INBOX`.
- Verificación automatizada: cuenta `msg*.wav` antes y después (PASO 6/6 y
  pestaña **VMS** de la interfaz: `0 → 1`, etc.).
- **Reproductor**: la pestaña VMS lista los mensajes (hora, tamaño, duración) y
  cada uno trae un `.wav` que se sirve por `GET /api/vms/media?mailbox=…&msg=…`
  (`audio/wav` PCM16; el navegador lo reproduce con ▶).
- **Mensaje desde la web**: la pestaña VMS ofrece *Enviar un mensaje desde la web*
  (grabar con micrófono o subir un archivo). El navegador convierte a PCM16 8 kHz
  y `POST /api/vms/audio` inyecta el audio en el UE1 y lanza la llamada real; el
  mensaje queda en la bandeja y se escucha con ▶.

## 4. Interfaz de operación

- `GET /api/vms` → `{"mailboxes":[{"mailbox":"0100002","messages":0,"list":[],...},
  {"mailbox":"0100003","messages":N,"list":[{"name":"msg0000.wav","size":206764,
  "modified":"2026-09-10T19:54:54","duration_s":13},...],"last":"msg0000.wav"}],...}`.
- `POST /api/actions/vms` (prueba VMS) →
  `{"confirmed":true,"messages_before":N,"messages_after":N+1,"ok":true,...}`.
- `POST /api/vms/audio` (multipart `audio` WAV PCM16 8 kHz + `ue` + `dest`) →
  `{"ok":true,"duration_s":6.0,"confirmed":true,"messages_before":4,"messages_after":5,...}`.
- `POST /api/test` → 13 results, todos `PASS` (ejemplo: `VMS: mensaje grabado en
  INBOX · msg*.wav: 0 -> 1`).

## Estado final

```text
PASS: 13   FAIL: 0
ESTADO: OK — la maqueta supera la prueba (exit 0)
```

Límites conocidos: IPsec Gm desactivado, autenticación MD5 (no AKA), sin Rx/Ro,
UE→UE requiere el AS como B2BUA (ver `conclusiones.md`).