# Guion de demo — Qué decir paso a paso (Core IMS + IVR + VMS)

Versión de apoyo para el presentador. Cada paso incluye **qué ejecutar**, una
**explicación fácil** (1 frase), una **explicación técnica** y una **alternativa
en lenguaje no técnico** (analogía para público sin background de redes).

> Los comandos se ejecutan contra la maqueta ya levantada (todo `Up`, suscriptores
> provisionados). Ver `paso_a_paso.md` para el despliegue.

---

## Paso 0 — Arranque y comprobación previa (no se muestra, 2 min)

**Qué ejecutar (preparación):**

```bash
cd maqueta-ims
docker compose up -d --force-recreate && docker compose ps   # todo Up
```

**Qué decir (fácil):**
> "Tenemos trece contenedores corriendo: toda una red de telefonía instalada en un
> solo equipo, y un AS que además de IVR ya responde el buzón de voz."

**Qué decir (técnico):**
> "La maqueta desplegada es un Core IMS completo: P-CSCF, I-CSCF y S-CSCF basados
> en Kamailio 6.2, HSS (PyHSS) con interfaz Cx Diameter, RTPEngine para los medios
> y Asterisk como Application Server. Todo sobre la red `mims_network`
> (172.30.0.0/24) y el dominio `ims.mnc001.mcc001.3gppnetwork.org`."

**Alternativa no técnica:**
> "Imaginen que esto es una miniatura de la red de telefonía de un operador.
> En vez de ocupar un edificio con cajas y antenas, está todo metido en programas
> dentro de este ordenador, e incluso hemos inventado nuestra propia compañía:
> prefijo MCC 001 / MNC 01."

---

## Paso 1 — La topología (mapa de la red) — 3 min

**Dónde:** abrir `results/arquitectura.drawio`.

**Qué decir (fácil):**
> "En una llamada normal intervienen tres piezas: el teléfono, la 'centralita' de
> la red y una base de datos con los datos de los clientes. Aquí es lo mismo, y
> además hemos separado cada tarea en su propio programa."

**Qué decir (técnico), señalando cada nodo:**
> - **UE (softphone pjsua)** es el terminal IMS del abonado.
> - **P-CSCF (172.30.0.8:5060)** es el punto de entrada de la red desde el UE
>   (interfaz Gm); gestiona el flujo y negocia los medios con RTPEngine.
> - **I-CSCF (172.30.0.6:4060)** es el encaminador que consulta a la HSS qué
>   S-CSCF debe atender al usuario (mensajes Cx UAR/UAA).
> - **S-CSCF (172.30.0.7:6060)** autentica al usuario (MAR/MAA), mantiene el
>   registro (SAR/SAA) y aplica la lógica de **iFC** (Initial Filter Criteria).
> - **PyHSS** es la base de datos maestra: suscriptores, vectores de autenticación
>   y los **iFC** que deciden a qué Application Server se desvía cada llamada.
> - **Asterisk (172.30.0.9)** es el **AS** que presta el servicio: **IVR** en
>   `0100002` y **buzón de voz (VMS)** en `0100003` (app_voicemail).
> - **RTPEngine (172.30.0.11)** transporta la voz (RTP) entre UE y AS.
> - **DNS (172.30.0.2)** traduce el nombre `ims.mnc001.mcc001.3gppnetwork.org`.

**Alternativa no técnica (analogía con un hotel):**
> "Piensen en un hotel con jefes con distintas tareas:
> - el teléfono de la habitación es el UE;
> - el botones de la puerta (P-CSCF) recibe a todo el que llega;
> - recepción (I-CSCF) pregunta en el registro del hotel quién está alojado;
> - el gerente del piso (S-CSCF) comprueba la tarjeta del huésped y aplica las
>   reglas del hotel;
> - el libro de registros del hotel (HSS) tiene los datos de cada cliente y las
>   reglas ('a este cliente se le sirve el desayuno' = iFC);
> - el camarero (Asterisk) trae el desayuno (el IVR);
> - y un mensajero (RTPEngine) lleva las bandejas entre habitaciones."

---

## Paso 2 — Registro del terminal (el teléfono 'inicia sesión') — 4 min

**Qué ejecutar (UE1, AOR = IMPU del IMSI):**

```bash
docker exec -d mims_softphone sh -c 'pjsua \
  --id sip:001011234567890@ims.mnc001.mcc001.3gppnetwork.org \
  --registrar sip:ims.mnc001.mcc001.3gppnetwork.org:5060 \
  --realm ims.mnc001.mcc001.3gppnetwork.org \
  --username 001011234567890 \
  --password 8baf473f2f8fd09487cccbd7097c6862 \
  --local-port 5061 --no-tcp --null-audio --log-level 4 >/tmp/pj1.log 2>&1'
```

**Qué mostrar:** en `docker exec mims_softphone grep -aE "401|200 OK|Service-Route|registration success" /tmp/pj1.log`:
`100 → 401 Unauthorized - Challenging the UE → 100 → 200 OK` + Service-Route.
Y en `docker logs mims_pyhss_hss`: `MAR/MAA` y `SAR/SAA`.

**Qué decir (fácil):**
> "El teléfono no entra directo: la red primero le envía una prueba ('demuestra
> quién eres'), el teléfono responde con su contraseña y la red le da el pase."

**Qué decir (técnico):**
> "El REGISTER llega al P-CSCF con R-URI el dominio; al no haber header
> Authorization, el I-CSCF hace un UAR (con el IMSI como identidad, procedente del
> header To) y la HSS responde el S-CSCF seleccionado. El S-CSCF emite el desafío
> digest (MAR/MAA, 401). En el segundo REGISTER, ya autenticado, el S-CSCF
> resuelve el perfil y los iFC de la HSS (SAR/SAA), guarda las IMPU contactadas en
> usrloc y responde 200 OK con Service-Route
> `sip:orig@scscf.ims.mnc001.mcc001.3gppnetwork.org:6060;lr`."

**Alternativa no técnica:**
> "Es como entrar en una zona restringida con tarjeta: la puerta pide el carné
> (401), tú lo enseñas (segundo REGISTER con tu contraseña) y te abren (200 OK).
> Además la red te deja una 'ruta' anotada: cuando te llamen, sabrán por qué
> pasillo encontrarte (la Service-Route)."

---

## Paso 3 — La llamada al IVR (el momento clave) — 5 min

**Qué ejecutar (con UE1 ya registrado):**

```bash
# Llamada determinista: espera el 200/REGISTER y ordena la llamada por consola ('m'),
# con --outbound al P-CSCF para que el anclaje RTPEngine ocurra (ver §12 de paso_a_paso).
docker exec -d mims_softphone sh -c "rm -f /tmp/pjC.log; ( until grep -aq 'Response msg 200/REGISTER' /tmp/pjC.log 2>/dev/null; do sleep 0.2; done; echo m; sleep 0.5; echo 'sip:0100002@ims.mnc001.mcc001.3gppnetwork.org'; sleep 20 ) | pjsua \
  --id sip:001011234567890@ims.mnc001.mcc001.3gppnetwork.org \
  --registrar sip:ims.mnc001.mcc001.3gppnetwork.org:5060 \
  --realm ims.mnc001.mcc001.3gppnetwork.org \
  --username 001011234567890 \
  --password 8baf473f2f8fd09487cccbd7097c6862 \
  --local-port 5061 --no-tcp --null-audio --log-level 4 \
  --outbound=sip:172.30.0.8:5060\;lr > /tmp/pjC.log 2>&1 &"
```

**Qué mostrar (UE):** `CALLING → CONNECTING → CONFIRMED` y luego `DISCONNECTED`
(razón 200). **Qué mostrar (Asterisk):**

```bash
docker logs mims_asterisk | grep -E "ims_as-00000000|Playing"
```

`NoOp → Answer → Playback(ivr_bienvenida) → "Playing 'ivr_bienvenida.slin'" → Hangup`.

**Qué decir (fácil):**
> "El teléfono pide 'extensión 0100002'. La red no se limita a conectarla: consulta
> la ficha del cliente y decide que esta llamada debe pasar por el servidor de
> aplicaciones, que contesta automáticamente con un audio de bienvenida."

**Qué decir (técnico):**
> "El INVITE originado por el UE (SessionCase 0) llega al S-CSCF, que evalúa el
> iFC #1 de la HSS (`INVITE + Case 0 → sip:asterisk.ims.mnc001.mcc001.3gppnetwork.org:5060`)
> y enruta la sesión al AS por la interfaz ISC. El P-CSCF y el S-CSCF reemplazan el
> SDP con RTPEngine (log 'RTPEngine engaged for Application Server'). Asterisk
> identifica al remitente por IP (identify 172.30.0.7 → endpoint `ims_as`),
> ejecuta `ims-in`: Answer, Playback del IVR (8 kHz) y Hangup; el 200 OK asciende,
> se cursa el ACK, fluye RTP bidireccional por RTPEngine y el BYE cierra el diálogo."

**Alternativa no técnica:**
> "Cuando marcas el 0100002, es como dar una orden en un restaurante: la cocina no
> se limita a conectar llamadas, mira tu ticket (el perfil en la HSS) y aplica una
> regla: 'este cliente pide IVR de bienvenida' (el iFC). Entonces tu llamada se
> desvía al camarero (Asterisk), que le dice hola de viva voz y cuelga.
> La voz no viaja por el mismo sitio que las órdenes: un mensajero aparte
> (RTPEngine) carga los vasos de un lado a otro."

---

## Paso 3bis — La interfaz mims_ui (2 min, opcional)

**Dónde:** abrir **http://localhost:8090** y mostrar las pestañas.

**Qué mostrar:**
1. **Estado**: contenedores (13) en verde, DNS resuelto a `172.30.0.8` y los 4
   listeners SIP activos.
2. **Prueba E2E**: pulsar el botón y dejar que corra; mostrar el resultado
   **13/13 OK** con su detalle por fila (la fila 12-13 es del **VMS**).
3. **VMS**: los mensajes del buzón listados con hora, tamaño y duración, y un
   **reproductor** que suena al pulsar ▶ (el audio sale de `GET /api/vms/media`).

**Qué decir (fácil):**
> "Todo esto también se puede pilotar desde un panel visual, sin terminal: un botón
> certifica la red completa con 13 comprobaciones, y ahí mismo se escuchan las
> grabaciones que dejan los usuarios en el buzón."

**Qué decir (técnico):**
> "El panel (`mims_ui`, Flask + Docker SDK sobre el socket de Docker) reutiliza la
> misma batería de checks que `scripts/test_maqueta.sh`: contenedores, DNS,
> listeners SIP/UDP, registro IMS de UE1/UE2, diálogo CONFIRMED contra el AS,
> reproducción del IVR en Asterisk, anclaje de medios en RTPEngine (P-CSCF), y el
> flujo VMS (llamada a `0100003` + mensaje `msg*.wav` en la bandeja). El
> reproductor sirve el WAV por HTTP sin transcodificar: `format=wav` en
> `voicemail.conf` graba PCM16 lineal de 8 kHz, que el navegador reproduce
> nativamente."

---

## Paso 3ter — El buzón de voz (VMS): la llamada que deja un mensaje — 4 min

**Qué ejecutar (con UE1 ya registrado; alternativa de un clic: pestaña
**VMS → Prueba VMS** de la interfaz):**

```bash
# Se genera el tono que hace de "voz del llamante" (el softphone con --null-audio
# no emite RTP; sin audio la grabación se abandona). Detalle en paso_a_paso.md §13.
docker exec -d mims_softphone sh -c "rm -f /tmp/pjV.log; ( until grep -aq 'Response msg 200/REGISTER' /tmp/pjV.log 2>/dev/null; do sleep 0.2; done; echo m; sleep 0.7; echo 'sip:0100003@ims.mnc001.mcc001.3gppnetwork.org'; sleep 18; echo h; sleep 4 ) | pjsua \
  --id sip:001011234567890@ims.mnc001.mcc001.3gppnetwork.org \
  --registrar sip:ims.mnc001.mcc001.3gppnetwork.org:5060 \
  --realm ims.mnc001.mcc001.3gppnetwork.org \
  --username 001011234567890 --password 8baf473f2f8fd09487cccbd7097c6862 \
  --local-port 5061 --no-tcp --null-audio --log-level 4 \
  --play-file /tmp/left_msg.wav --auto-play \
  --outbound=sip:172.30.0.8:5060\;lr > /tmp/pjV.log 2>&1 &"
```

**Qué mostrar:**
- Asterisk (`docker logs mims_asterisk | grep -E "0100003|vm-|VoiceMail|Playing"`):
  `NoOp(VMS...) → Answer → Playback(ivr_bienvenida) → VoiceMail("0100003@default,su")`
  → `vm-theperson` → `vm-isunavail` → `beep` → fin de grabación.
- La bandeja:
  `docker exec mims_asterisk ls -l /var/spool/asterisk/voicemail/default/0100003/INBOX/`
  → `msg0000.wav` (PCM16, reproducible) + `msg0000.txt` (metadatos del mensaje).
- En la interfaz (pestaña **VMS**): apretar ▶ y que suene la grabación.

**Qué decir (fácil):**
> "Esta vez no es un mensaje grabado por la empresa: es una llamada de verdad que
> la red desvía (por el mismo mecanismo del IVR) al contestador, y el mensaje que
> deja el llamante se queda guardado en la bandeja. Y desde el panel se escucha."

**Qué decir (técnico):**
> "El INVITE a `0100003` viaja igual que el del IVR: el S-CSCF aplica el iFC#1 y lo
> enruta al AS por ISC. Aquí el contexto `ims-in` ejecuta `VoiceMail(0100003@default,su)`
> (opción `su`: salta el saludo del usuario y graba directo). La app necesita los
> prompts `vm-*` en los sonidos de Asterisk y **audio RTP real** del llamante: por
> eso la prueba inyecta `--play-file`. `format=wav` guarda el mensaje como PCM16 a
> 8 kHz (el nombre `msgNNNNN` es el contador de mensajes, no la duración). La GUI
> lista los `msg*.wav` y los sirve por `GET /api/vms/media?mailbox=…&msg=…`."

**Alternativa no técnica:**
> "El IVR era el contestador de la empresa, 'todos nuestros asesores están...'.
> Ahora el que habla es de verdad el usuario que llama: se queda grabado igual que
> cuando llamas a un móvil y entra el buzón. En el panel web se pulsa ▶ y se oye
> exactamente lo que grabó. La red no tuvo que hacer nada distinto: la regla del
> cliente (iFC) ya decía que este número lo responde el servidor de aplicaciones."

**Bonus — grabar desde el navegador (1 min):** al final de la demostración, en la
pestaña **VMS → Enviar un mensaje desde la web**: 🎙 Grabar con el micrófono o
📂 seleccionar un archivo → *Enviar al buzón 0100003*. El navegador convierte el
audio a PCM16 8 kHz, la interfaz lo manda a `POST /api/vms/audio` (lo inyecta al
UE1 y lanza la llamada real) y, al colgar, el mensaje del usuario aparece en la
bandeja con ▶ para escucharlo.

**Qué decir (motor, resumen en 2 frases):**
> "El audio del usuario no se 'sube' al buzón por la API: la API se limita a
> inyectarlo en el terminal UE1, y es **la llamada IMS real** la que lo entrega al
> Asterisk por RTPEngine y lo graba. Por eso da igual dictar en el IVR, dejar un
> mensaje llamando o escribir aquí: el AS solo sabe grabar lo que le llega por la red."

---

## Paso 4 — Repaso y cierre — 2 min

**Qué decir (fácil):**
> "Hemos demostrado en un solo ordenador lo que antes necesitaba un laboratorio
> entero: un terminal se registra en una red IMS real, hace una llamada que la red
> encamina según las reglas del cliente a un contestador automático, y la grabación
> que deja el llamante se escucha desde el panel."

**Qué decir (técnico), resumen:**
> - Registro IMS validado: doble REGISTER con desafío digest (401) y 200 OK con
>   Service-Route; soportado por UAR/UAA, MAR/MAA y SAR/SAA sobre Cx.
> - Llamada interceptada por **iFC** (SessionCase 0) hacia el AS Asterisk, con
>   medios por RTPEngine y díalogo confirmado (200 OK + ACK + BYE).
> - **VMS**: el mismo camino sirve el buzón `0100003` (app_voicemail); la
>   grabación `msg*.wav` (PCM16) queda en la bandeja y se reproduce desde la
>   interfaz (`/api/vms/media`).
> - Estructura desplegada en `results/arquitectura.drawio` y reproducible desde
>   `results/paso_a_paso.md`.
> - Limitaciones conocidas: sin IPsec en Gm, autenticación MD5 (no AKAv2), sin
>   Rx/charging, y UE→UE requiere que el AS actúe como B2BUA.

**Alternativa no técnica (cierre):**
> "Lo valioso es que todo el 'edificio' del operador está simulado en este
> ordenador: quién eres, cómo te autenticas y qué reglas se te aplican; y la voz
> viaja igual que en un operador real. Esto sirve para enseñar, probar servicios
> (IVR, buzón de voz, y mañana cualquier otra) y formar al equipo sin tocar una red
> de verdad."

---

## Notas de operación para el presentador

- **Registro con AOR = IMPU del IMSI**, nunca el MSISDN (con el MSISDN el primer
  UAR falla con `403 - HSS User Unknown`).
- **`tail -f /dev/null |` (o el launcher determinista de §12 de paso_a_paso) delante**
  de pjsua al llamar: si el stdin llega a EOF, pjsua cuelga la llamada.
- UE2 (opcional) con IMSI `001011234567891`, ki `2a6ab8297e0d15c7a12eef0d8a12b143`,
  `--local-port 5062`. Mismo resultado `200 OK` + Service-Route.
- Si el segundo REGISTER diera `500 Server error on UAR select next S-CSCF`, la
  causa es la iFC sin la IMPU del IMSI (`paso_a_paso.md` §8.3) → actualizar
  `pyhss/maqueta_ifc.xml` (se relee en caliente).
- Si el `Playback` fallara, verificar `ivr_bienvenida.wav` en
  `/var/lib/asterisk/sounds` (lo copia `asterisk_init.sh` al arrancar).