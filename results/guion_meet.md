# Guion de demo — Core IMS + IVR + VMS (maqueta en Docker)

Duración estimada: **~18 minutos**. Preparada antes de empezar (todo `Up`,
UE1/UE2 registrados) y ejecución en vivo de una llamada al IVR de Asterisk y una
**grabación de buzón de voz (VMS)**.

---

## 0. Preparación previa (no se muestra)

```bash
cd maqueta-ims
docker compose up -d --force-recreate && docker compose ps   # todo Up (healthy)
# suscriptores + iFC + scscf (paso_a_paso.md §8-§9), luego registrar UE1 y UE2
# (o hacerlo todo desde el panel: http://localhost:8090 → Config → Provisionar → Operación)
```

> La demo puede mostrarse desde terminal o desde la **interfaz `mims_ui`**
> (`http://localhost:8090`): su pestaña **Prueba E2E** lanza los mismos 13 checks
> en vivo, y **Estado** muestra contenedores/DNS/listeners. Los comandos de abajo
> son la versión por terminal.

## 1. Contexto (2 min)

- Objetivo: probar un **Core IMS** (P/I/S-CSCF + HSS) con Kamailio, registro de un
  UE y enrutado de una llamada al Application Server (Asterisk) vía **iFC** desde
  la HSS.
- Dominio 3GPP: **`ims.mnc001.mcc001.3gppnetwork.org`** (MCC 001 / MNC 01).
- Todos los nodos son contenedores Docker en `mims_network` (`172.30.0.0/24`).

## 2. Topología (3 min) — `results/arquitectura.drawio`

```
UE (pjsua) ─Gm─> P-CSCF ─Mw─> I-CSCF ─Cx×UAR/UAA─> HSS (PyHSS)
                 │                    │
                 │                    V
                 │                I-CSCF → S-CSCF (elegido vía UAA)
                 │                            │
                 │              ┌─────────────┴─────────────┐
                 │              │ Mw: INVITE (iFC#1→ AS)    │ Cx: MAR/MAA, SAR/SAA
                 │              V                           │
                 │        AS Asterisk (IVR + VMS)      RTPEngine (medios)
```

- **P-CSCF** (172.30.0.8:5060): proxy en el borde, gestión de flujo.
- **I-CSCF** (172.30.0.6:4060): consulta la HSS (UAR/UAA) y selecciona el S-CSCF.
- **S-CSCF** (172.30.0.7:6060): autenticación (MAR/MAA), registro (SAR/SAA) y
  evaluación de **iFC**.
- **PyHSS** (172.30.0.12/13): Cx + API REST + plantilla iFC (`maqueta_ifc.xml`).
- **Asterisk** AS (172.30.0.9): endpoint `ims_as`, contexto `ims-in`: **IVR**
  (`0100002`) y **buzón de voz VMS** (`0100003`, app_voicemail → INBOX `msg*.wav`).
- **DNS** (172.30.0.2): A del dominio → P-CSCF y SRV `_sip._udp` → I-CSCF.
- **mims_ui** (172.30.0.14, host `:8090`): panel de operación (estado, prueba E2E
  13/13, provisión, **VMS con reproductor** y logs) que usa el socket de Docker.

## 3. Registro del UE (4 min) — en vivo

Desde `mims_softphone` (AOR = IMPU del IMSI):

```bash
pjsua --id sip:001011234567890@ims... --registrar sip:ims.mnc001.mcc001.3gppnetwork.org:5060 \
      --realm ims.mnc001.mcc001.3gppnetwork.org --username 001011234567890 \
      --password 8baf473f2f8fd09487cccbd7097c6862 --local-port 5061 --no-tcp --null-audio --log-level 4
```

**Qué mostrar:**
1. En el log del UE: `100 → 401 Unauthorized - Challenging the UE → 100 → 200 OK`
   + **Service-Route** y `registration success, status=200`.
2. En `mims_pyhss_hss`: líneas `MAR`/`MAA` (401) y `SAR`/`SAA` (200).
3. En `mims_scscf`: la IMPU registrada (`sip:001011234567890@...`, expires).

Habla clave: “el registro IMS es un doble paso: primero un desafío calculado por la
HSS y luego la revalidación con el digest; el 200 OK incluye la Service-Route por
la que el S-CSCF enviará las llamadas de este usuario”.

## 4. Llamada al IVR (5 min) — en vivo

Con UE1 registrado:

```bash
tail -f /dev/null | pjsua --id sip:001011234567890@ims... \
  --registrar sip:ims.mnc001.mcc001.3gppnetwork.org:5060 \
  --realm ims.mnc001.mcc001.3gppnetwork.org --username 001011234567890 \
  --password 8baf473f2f8fd09487cccbd7097c6862 --local-port 5063 --no-tcp --null-audio \
  --log-level 4 sip:0100002@ims.mnc001.mcc001.3gppnetwork.org
```

**Qué mostrar:**
1. UE: `CALLING → CONNECTING → CONFIRMED` (tras `100 Trying` y `200 OK`), luego
   `DISCONNECTED` (razón **200 Normal call clearing**) al terminar el IVR.
2. Asterisk: `pjsip show channel` y log `Executing [0100002@ims-in] Playback(ivr_bienvenida)`.
3. Logs del S-CSCF: *“RTPEngine engaged for Application Server”* (medios por RTPEngine).
4. (Opcional) `docker logs mims_pcscf` mostrando el reemplazo de SDP.

Habla clave: “el INVITE del usuario pasa por el S-CSCF, que consulta el perfil de la
HSS: el iFC dice `INVITE + SessionCase 0 → AS`. El AS contesta con su propio 200 OK,
el diálogo se confirma y el audio (IVR) viaja por RTPEngine”.

## 5. Buzón de voz (VMS) (4 min) — en vivo

Con UE1 registrado (desde la interfaz se hace con un clic en **VMS → Prueba VMS**;
por terminal, la llamada determinista necesita el tono `--play-file` de `paso_a_paso.md` §13):

```bash
docker exec mims_asterisk rm -f /var/spool/asterisk/voicemail/default/0100003/INBOX/msg*.*
docker logs --tail=0 mims_asterisk
docker exec -d mims_softphone sh -c "rm -f /tmp/pjV.log; ( until grep -aq 'Response msg 200/REGISTER' /tmp/pjV.log 2>/dev/null; do sleep 0.2; done; echo m; sleep 0.7; echo 'sip:0100003@ims.mnc001.mcc001.3gppnetwork.org'; sleep 18; echo h; sleep 4 ) | pjsua \
  --id sip:001011234567890@ims... --registrar sip:ims.mnc001.mcc001.3gppnetwork.org:5060 \
  --realm ims.mnc001.mcc001.3gppnetwork.org --username 001011234567890 --password 8baf473f2f8fd09487cccbd7097c6862 \
  --local-port 5061 --no-tcp --null-audio --log-level 4 --play-file /tmp/left_msg.wav --auto-play \
  --outbound=sip:172.30.0.8:5060\;lr > /tmp/pjV.log 2>&1 &"
docker exec mims_softphone sh -c 'until grep -q "Call 0 state changed to CONFIRMED" /tmp/pjV.log; do sleep 1; done; echo Llamada CONFIRMED'
```

**Qué mostrar:**
1. Asterisk: `Executing [0100003@ims-in] ... → NoOp(VMS: buzón...) → Answer →
   Playback(ivr_bienvenida) → VoiceMail("0100003@default,su") → vm-theperson →
   vm-isunavail → beep`.
2. La grabación aparece en la bandeja: `docker exec mims_asterisk ls .../0100003/INBOX/`
   (una `msg0000.wav` PCM16 + `msg0000.txt`).
3. En la **interfaz, pestaña VMS**: la lista muestra la hora/peso/duración y un
   **reproductor**; pulsar ▶ y el mensaje suena en el navegador (`GET /api/vms/media`).

Habla clave: “el mismo AS sirve hoy un IVR y mañana un servicio de correo de voz:
el S-CSCF no decide qué hacer con la llamada — solo aplica el iFC que viene del
perfil en la HSS. El AS graba el audio que le llega por RTPEngine y lo deja listo
para que el operador lo escuche desde el panel”.

**Bonus — mensaje desde la web (1 min):** en la pestaña VMS, panel *Enviar un
mensaje desde la web*: 🎙 **Grabar** (o **seleccionar archivo**) → *Enviar al buzón
0100003*. El navegador convierte el audio a PCM16 8 kHz, `POST /api/vms/audio` lo
inyecta al UE1 y la llamada real lo graba; vuelve a listar y aparece con ▶. Misma
firma que la prueba anterior pero con **audio de verdad** del usuario.

## 6. Interfaz de operación (2 min) — opcional

Abrir **http://localhost:8090** y mostrar:
1. **Estado**: 13 contenedores `Up`, DNS → `172.30.0.8`, 4 listeners SIP en verde.
2. **Prueba E2E**: pulsar "Ejecutar prueba" y hacer fade a los **13/13 OK** (es la
   misma batería que `scripts/test_maqueta.sh`).
3. **VMS**: mensajes listados (hora, tamaño, duración), reproductor y panel web.
4. (Opcional) **Operación**: registrar UE1/UE2 o repetir la llamada con un clic.

Habla clave: "sin tocar la terminal, desde este panel se puede certificar que la
maqueta funciona: 13 comprobaciones independientes, de los contenedores al anclaje
de medios por RTPEngine, y además escuchar la grabación del buzón".

## 7. Cierre / preguntas (2 min)

- Recap: registro 401→200 con Service-Route; llamada interceptada por iFC y servida
  por el AS; plano de medios reemplazado por RTPEngine; y servicio de **VMS** con
  la grabación audible desde el panel.
- Límites: sin IPsec Gm, auth MD5, sin UE→UE (el AS no es B2BUA aún), sin Rx/charging.
- Referencias: `results/paso_a_paso.md` (despliegue) y `results/arquitectura.drawio`.
- Próximos pasos: AS B2BUA para UE→UE, integración ISabelPBX, QoE por Rx.

---

### Notas de operación para el presentador

- Si el UE no registra, ver 401 (esperado) y que el segundo REGISTER no reciba 500:
  el `500` indica iFC sin la IMPU del IMSI (ver `paso_a_paso.md` §8.3).
- Mantener el `tail -f /dev/null |` delante de pjsua durante la llamada (si no,
  pjsua cuelga la llamada al llegar EOF en stdin).
- Volúmenes: `pyhss_db` persiste `hss.db`; los cambios de iFC se leen en caliente;
  cambios en `pjsip.conf`/`extensions.conf` requieren `docker compose restart asterisk`.