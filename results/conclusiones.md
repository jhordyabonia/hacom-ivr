# Maqueta Core IMS — Conclusiones

## Qué se logró

- **Core IMS funcional en Docker** con tres planos de control independientes
  (P-CSCF, I-CSCF, S-CSCF basados en Kamailio 6.2.0-dev1) y un HSS (PyHSS) con
  interfaces Diameter **Cx** operativas:
  - **UAR/UAA** (selección de S-CSCF por el I-CSCF).
  - **MAR/MAA** (vectores de autenticación → desafío `401`).
  - **SAR/SAA** (asignación de servidor, perfil del suscriptor e **iFC**).
- **Registro IMS validado** de dos suscriptores (UE1/UE2):
  `100 → 401 (desafío digest MD5) → 100 → 200 OK` con **Service-Route**
  (`sip:orig@scscf.ims.mnc001.mcc001.3gppnetwork.org:6060;lr`) en el S-CSCF.
  El S-CSCF mantiene las IMPU (`sip:MSISDN@...`, `tel:MSISDN`, `sip:IMSI@...`)
  vinculadas al contacto del UE.
- **Llamada validada UE→AS por iFC**: el UE marca `0100002@ims...`, el S-CSCF
  evalúa el **iFC#1** (`INVITE` + `SessionCase 0` → `sip:asterisk.ims...:5060`) y
  enruta la sesión al **Asterisk AS**; el AS responde `200 OK`, reproduce un audio
  **IVR** (`ivr_bienvenida.wav`) y cierra la sesión. El plano de medios es
  reemplazado por **RTPEngine** (log: *RTPEngine engaged for Application Server*).
- **Buzón de voz (VMS) validado UE→AS**: el UE llama a `0100003@ims...` (misma iFC),
  el **AS** ejecuta `VoiceMail(0100003@default,su)` (app_voicemail), reproduce los
  prompts `vm-*`, graba el mensaje del llamante y lo guarda como `msg*.wav`/`.txt`
  en la bandeja (`.../voicemail/default/0100003/INBOX`). El test E2E lo verifica
  contando mensajes antes/después. Con `format=wav` los mensajes se graban en
  **PCM16 lineal (8 kHz)**, que el **reproductor de la interfaz** sirve y reproduce
  en el navegador (`GET /api/vms/media`).
- **Reproducibilidad**: `results/paso_a_paso.md` recoge el despliegue completo
  (build, DNS, aprovisionamiento, BD, registro, llamada y VMS) y los errores más
  comunes con su causa/solución.
- **Interfaz de operación (`mims_ui`)**: panel web en `http://localhost:8090`
  (Flask + Docker SDK) con estado de los 13 contenedores, DNS y listeners,
  **prueba E2E de 13 checks** (incluye VMS), registro/llamada de los UEs, buzón
  con **reproductor de mensajes** (pestaña **VMS**), provisión en PyHSS y logs. Validación **13/13**
  también en terminal con `scripts/test_maqueta.sh`. Manual: `results/manual_interfaz.md`.

## Lecciones técnicas (pitfalls resueltos)

1. **Imagen de Kamailio.** `kamailio/kamailio-ci:5.5.2-alpine` no tiene
   `sdp_iterator_*` ni los binarios auxiliares. Se usó
   `ghcr.io/herlesupreeth/docker_kamailio:master` (Kamailio 6.2.0-dev1, Ubuntu),
   construida con `docker build -t mims_kamailio ./kamailio`. El tag compartido
   obliga a `--force-recreate` de los CSCF tras reconstruir.
2. **Adaptaciones del P-CSCF a 6.2** (base con modparams eliminados/renombrados):
   `WITH_IPSEC` y `WITH_RX` apagados, `ims_ipsec_pcscf` cargado fuera del ifdef
   (lo exige `ims_registrar_pcscf`), `delete_delay` comentado, bloque
   `sdp_iterator_*` (a=inactive) comentado, condición `$sdp(c:ip)` eliminada.
3. **DNS**: el UE debe registrar con **R-URI el dominio**, no la IP del P-CSCF
   (`sip:ims.mnc001.mcc001.3gppnetwork.org:5060`); así el P-CSCF reescribe
   `sip:user@dominio` y el relay resuelve el **SRV `_sip._udp` → icscf:4060**.
   El registro A del dominio va en el **apex `@`** de la zona (no en `ims`).
4. **iFC y la IMPU del IMSI**: la plantilla debe incluir `sip:IMSI@dominio`
   como identidad pública. Sin ella el `update_contacts` del S-CSCF falla
   (`Error processing REGISTER`) y el UE recibe `500 Server error on UAR select
   next S-CSCF`.
5. **UAR y la identidad privada**: en el primer REGISTER (sin header Authorization)
   el I-CSCF envía el header To como User-Name del UAR; por eso el UE debe
   autenticarse con AOR = IMPU del IMSI (PyHSS busca por IMSI).
6. **Provisionamiento**: el `PUT /ims_subscriber/` de PyHSS no acepta `s_cscf`;
   los campos `scscf`/`scscf_realm` se fijan contra SQLite
   (tabla `ims_subscriber`).
7. **Asterisk 22**: `trust_id_incoming` no es opción válida del endpoint
   (`res_sorcery` rechaza el objeto); se identifica al S-CSCF por **identify** con
   IP `172.30.0.7`. El audio IVR debe estar en `/var/lib/asterisk/sounds`
   (8 kHz, 16-bit, mono).
8. **pjsua**: no existe `--no-video` (usar `--null-audio`); si el stdin llega a
   EOF, el CLI cuelga las llamadas → mantenerlo abierto (`tail -f /dev/null | pjsua`).
   Su consola solo procesa comandos vía **pipe** (no vía FIFO), y `m` exige la URI
   en una **segunda línea** (`echo m; echo 'sip:...@...'`).
9. **Llamada determinista.** pjsua lanza el INVITE al arrancar, antes de completar el
   REGISTER → S-CSCF `403 - You must register first with a S-CSCF` (era un falso
   PASS/FAIL intermitente). Solución: un escritor retrasado en el pipe que espera
   `200/REGISTER` en el log y recién entonces ordena la llamada (`m`).
10. **El INVITE bypasa el P-CSCF si no se fuerza.** Con el registro completado, pjsua
    ruta la llamada directo al S-CSCF por la **Service-Route**; el P-CSCF (y por
    tanto RTPEngine) queda fuera. Fijar `--outbound=sip:172.30.0.8:5060;lr`
    (P-CSCF) restablece el anclaje de medios; es lo que hacen `app.py` y
    `test_maqueta.sh`.
11. **Selección de S-CSCF en el I-CSCF (el problema más largo de la maqueta).** El
     módulo `ims_icscf` de Kamailio 6.2.0-dev1 parsea mal el pool y **mangla el
     RURI** del REGISTER. Workaround consolidado (ver `paso_a_paso.md` §15):
     `HSS_SCSCF_POOL` y la tabla `s_cscf` como URI completa
     (`sip:scscf.${IMS_DOMAIN}:6060;transport=udp`, nunca IP desnuda ni nombre sin
     puerto), `use_dns_cache=off` (el resolver interno del nodo no consulta DNS y
     usa cache rota), y `route[set_scscf_dst]` que reescribe `$ru`/`$du` a la URI
     canónica, inyectado en las ramas de relay (UAR/LIR success, los dos
     `I_scscf_select`). Con esto la cadena `401 (MAR) → 200 OK (SAR)` queda
     estable y desaparecen `bad_uri`, `500 Error forwarding to SCSCF` y
     `new_t(): uri invalid (400)`.
12. **VMS en el AS.** `app_voicemail` necesita (a) los prompts `vm-*` en los
    sonidos de Asterisk (sin ellos aborta con `Spawn extension ... non-zero`), y
    (b) **audio RTP real** del llamante: con `--null-audio` pjsua no genera RTP y
    la grabación se abandona (`Recording was 0 seconds long`). En la prueba se
    inyecta un tono de 45 s (`--play-file --auto-play`) y se validan los mensajes
    contando `msg*.wav` en `.../0100003/INBOX`.

## Limitaciones de la maqueta

- **IPsec** en Gm desactivado (los UEs son softphones en una red Docker; se
  sustituye por el manejo de flujo del P-CSCF + RTPEngine).
- **Autenticación** MD5 (HTTP Digest), no AKAv1/AKAv2.
- **Sin** `iFC` de tipo "copiar" (registro/subscripción hacia AS), **sin** Rx/PCRF
  (QoS), **sin** Ro/Rf (charging) y **sin** ISC real con QoS de SDP 3GPP.
- **UE→UE**: el iFC#1 (todo INVITE originado) desvía también los INVITEs entre
  suscriptores al AS; una llamada UE→UE directa requeriría que el AS actuara como
  B2BUA (reescribir y re-originar la sesión hacia el S-CSCF) o eliminar ese iFC.
- El **AS no valida** el origen (confía en el identify por IP del S-CSCF).

## Siguientes pasos sugeridos

1. Llamada **UE→UE** con el AS como B2BUA (patrón de tercer party call control) o
   con una segunda iFC condicionada por Request-URI.
2. **Integrar ISabelPBX** como AS IVR real (flujo de negocio) y registro de IVR
   auditado (CDR en MySQL).
3. Activar **IPsec/Gm** (con UE IMS), **Rx/PCRF** para QoS y **Ro** de charging.
4. Migrar el S-CSCF a **auth AKAv2** y añadir **Sh (UDR)** para datos de perfil.
5. CI/operación: la prueba E2E ya está estandarizada (interfaz `mims_ui` +
   `scripts/test_maqueta.sh`) con **13 checks** verificables (incluye VMS); añadir
   healthchecks a los contenedores y un `scripts/demo.sh` que prepare la demo
   (inicio, provisión, registro) en un solo comando.