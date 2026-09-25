# Prompts utilizados en la construcción de la maqueta Core IMS

Documento de soporte de la maqueta Core IMS (P/I/S-CSCF + PyHSS + Asterisk + VMS).
Recoge los enunciados que guiaron cada hito y el artefacto que produjeron.
Los resultados verificables están en `response.md` y el despliegue completo en
`paso_a_paso.md`; la validación ejecutable es `scripts/test_maqueta.sh` (13 checks).

## 1. Despliegue del Core IMS (registro y llamada)

> Desplegar una maqueta de Core IMS en Docker con Kamailio (P-CSCF, I-CSCF,
> S-CSCF) y PyHSS como HSS con Diameter Cx, de forma que un terminal softphone
> (pjsua) registre (401 → 200 OK, AKAv1/MD5) y pueda llamar a un Application
> Server (Asterisk) cuyo número se enruta por **iFC**.

**Artefactos**: `docker-compose.yml` (13 servicios, red `172.30.0.0/24`),
`kamailio/*/kamailio_*.cfg`, `pyhss/`, `asterisk/pjsip.conf`, `extensions.conf`,
`scripts/provision_hss.sh`, `scripts/test_maqueta.sh` (§1–§5).

## 2. Reparación del registro (módulo `ims_icscf`)

> El registro del UE devuelve `bad_uri: [scscf.ims...]`/`[172.30.0.7:6060]`,
> `500 (Error forwarding to SCSCF)` o `new_t(): uri invalid` en la segunda ronda.
> Encontrar la causa raíz y aplicar un workaround estable en configuración
> (sin tocar el código fuente de Kamailio).

**Resultado**: `use_dns_cache=off` + `HSS_SCSCF_POOL` y tabla `s_cscf` como URI
completa (`sip:scscf.<dominio>:6060;transport=udp`) + `route[set_scscf_dst]`
(reescritura de `$ru`/`$du`) inyectado en las ramas de relay del I-CSCF.
Registro estable: `401 (MAR) → 200 OK (SAR)`.

## 3. Buzón de voz (VMS) en el AS

> Añadir un buzón de voz a la maqueta: el AS (Asterisk) debe atender otra número
> de la familia iFC (`0100003`), saludar y **grabar el mensaje** del llamante en
> la bandeja del buzón, validable de forma automatizada (mensaje presente tras la
> llamada), e integrarlo en la interfaz de operación y en el script E2E.

**Artefactos**: `asterisk/voicemail.conf`, `extensions.conf` (exten `0100003`),
prompts `asterisk/vm-*.wav`, `asterisk_init.sh` (cdr-csv), `interfaz/app.py`
(pestaña/endpoints VMS + paso 6 del E2E), `interfaz/static/*`, PASO 6 de
`scripts/test_maqueta.sh`.

## 4. Interfaz de operación

> Panel web en español (Flask + Docker SDK, sin dependencias en el navegador)
> para operar la maqueta: estado de nodos, prueba E2E, registro/llamada de los
> UEs, provisión en PyHSS, logs y buzón de voz. Acceso `http://localhost:8090`.

**Artefactos**: `interfaz/app.py`, `interfaz/static/index.html|app.js|style.css`,
`results/manual_interfaz.md` (respuestas y API en `response.md`).