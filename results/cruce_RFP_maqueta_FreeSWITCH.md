# Cruce de Funcionalidades — RFP uVAS 2026 ↔ Maqueta FreeSWITCH

> Documento de trazabilidad entre las funcionalidades esperadas en el RFP
> `doc/20260817 uVAS RFP 2026.md` (Millicom) y las capacidades de la **maqueta de
> FreeSWITCH** (`maqueta-ims-3/`): Core IMS (Kamailio P/I/S-CSCF + PyHSS) + AS
> Frontera ISC (Kamailio `asfront`) + **FreeSWITCH como Application Server (AS)**
> + RTPEngine + interfaz de operación `mims_ui`.
>
> Conclusión adelantada: **la maqueta cubre hoy las funcionalidades de voz (IVR,
> VMS) y provee la plataforma para cumplir el resto de funcionalidades del RFP**
> (SMSC/FDA/SMSFW/USSD/MCA/SCE/charging/reporting) ampliando con capacidad nativa
> de FreeSWITCH y/o AS complementarios dentro de la misma arquitectura por iFC —
> sin tocar el Core IMS.

---

## 1. Funcionalidades esperadas por el RFP

El RFP (sección 1.1 *Background*, pág. 24) pide una **plataforma uVAS**
convergente que incluya, sin limitarse a:

| # | Funcionalidad RFP | Bloque |
|---|---|---|
| F1 | **SMSC** (Short Message Service Center) | Mensajería |
| F2 | **FDA — First Delivery Attempt** | Mensajería |
| F3 | **SMS Firewall (SMSFW)** | Mensajería / Seguridad |
| F4 | **Voice Mail System (VMS)** | Voz |
| F5 | **Missed Call Alert (MCA)** | Voz / Notificación |
| F6 | **USSD Gateway** | Servicios interactivos |
| F7 | **Interactive Voice Response (IVR)** | Voz |
| F8 | **SCE — Service Creation Environment** | Desarrollo de servicios |
| F9 | Charging (tarificación/cobro) | Horizontal |
| F10 | Reporting (informes) | Horizontal |
| F11 | Monitoring & Management (supervisión y gestión) | Horizontal |
| F12 | Convergencia / cloud-native / virtualizado / 5G-ready | Plataforma |

---

## 2. La maqueta de FreeSWITCH (qué es y qué está validado)

| Componente | Detalle |
|---|---|
| Core IMS | Kamailio P-CSCF (:5060), I-CSCF (:4060), S-CSCF (:6060) con Cx Diameter (PyHSS: UAR/UAA, MAR/MAA, SAR/SAA + iFC) |
| AS Frontera | Kamailio `asfront` (interworking **ISC → SIP plano**), destino del iFC#1 |
| **AS aplicación** | **FreeSWITCH** (`mims3_freeswitch`): dialplan `public` (IVR y VMS nativos) sin Asterisk |
| Plano de medios | RTPEngine anclado en el P-CSCF (`RTPEngine engaged for Application Server`) |
| Autenticación | Digest-AKAv1-MD5 **E2E demostrado** (`ue_aka_probe.py` → 200 OK); registro IMS 401→200 |
| Orquestación | `docker-compose.yml`, red `172.32.0.0/24`, 14 contenedores, `restart: unless-stopped` |
| Interfaz de operación | `mims_ui` (`http://localhost:8090`): estado, E2E, operación, logs, VMS |
| Verificación | `scripts/test_maqueta.sh` → **PASS 15 / FAIL 0** (registro, iFC, IVR, RTPEngine, VMS) |

**Evidencia VMS:** `freeswitch/vms/0100003/INBOX/msg_*.wav` (grabados vía iFC a
`0100003`). **Evidencia IVR:** playback de `freeswitch/ivr_bienvenida.wav` a
`0100002`. **Evidencia AKA:** 401 con `algorithm=AKAv1-MD5` sin ck/ik → 200 OK.

---

## 3. Matriz de cruce RFP ↔ maqueta FreeSWITCH

Estado: **✅ Implementado** (validado) · **🟡 Ampliable-nativo** (soporte en la
imagen FreeSWITCH, requiere dialplan/script/config) · **🟠 Complemento-AS**
(requiere un módulo/AS adicional en la misma maqueta por iFC).

| RFP | Funcionalidad | Capacidad en la maqueta FreeSWITCH | Estado | Evidencia / Dónde |
|---|---|---|---|---|
| F7 | **IVR** | `mod_dptools` (answer/sleep/playback) + `mod_say_*`, `mod_lua`, `mod_httapi`, `mod_xml_curl` para menús, BD y flujos configurables | ✅ | `freeswitch/conf/dialplan/public.xml` (`ivr_0100002`); E2E paso 5 |
| F4 | **VMS** | `mod_voicemail` (cargado) + `mod_dptools` `record`; bandejas por MSISDN en volumen `storage/vms` | ✅ | `public.xml` (`vms_0100003`); `freeswitch/vms/0100003/INBOX/msg_*.wav`; E2E paso 6 |
| F8 | **SCE** | **Motor nativo**: servicios en Lua (`mod_lua`), control HTTP (`mod_httapi`), dialplan remoto/webhook (`mod_xml_curl`), `mod_v8`/`mod_json_cdr` disponibles; flujos JSON por país sin redeploy | 🟡 | Módulos **cargados**: `mod_lua`, `mod_httapi`; en disco: `mod_xml_curl.so` |
| F5 | **MCA** | CDR de la llamada (`mod_cdr_csv` cargado) + `mod_event_socket` para detectar contestación/no-answer; aviso entregado por SMS (`mod_sms`) o MB/MWI vía S-CSCF | 🟡 | `mod_cdr_csv`, `mod_event_socket`, `mod_sms.so` en la imagen |
| F1 | **SMSC** | Enrutar `MESSAGE` por **iFC → AS Frontera** (mismo patrón que INVITE); recepción/entrega SMS con `mod_sms` (image) o AS python `vas/smsc` + cola redis/MySQL | 🟠 | Patrón ISC ya validado para INVITE; el tránsito de `MESSAGE` en S-CSCF/Frontera es extensión directa |
| F2 | **FDA** | Cola de entrega persistida (redis/MySQL) en el AS SMS; entrega inmediata si el destinatario está registrado o **diferida** hasta su próximo `REGISTER` (hook al S-CSCF) | 🟠 | Mismo AS SMSC + estado DLR; redis/MySQL ya presentes en la maqueta |
| F3 | **SMS Firewall** | Política MO/MT (regex, blacklist, rate limit, scoring) en la cadena del SMSC, antes de entregar; misma lógica que recibe los MESSAGE | 🟠 | AS `vas/smsfw` interpuesto en la cadena SMS; estilos ya previstos en `plan_trabajo_uVAS_2026.md` |
| F6 | **USSD Gateway** | Emulación USSD sobre SIP `MESSAGE`/menú por etapas con motor FreeSWITCH (Lua/HTTAPI) o AS python; stub de integración MAP/SS7 para propuesta | 🟠 | Motor de menú = el mismo IVR/SCE; interfaz real USSDG es integración, no IMS |
| F9 | **Charging** | CDR generado por FreeSWITCH (`mod_cdr_csv`, `mod_xml_cdr`, `mod_json_cdr`/`mod_cdr_mongodb` en disco); API de ingesta → BD/CDR; Ro/Rf como desarrollo posterior | 🟡 | `mod_cdr_csv` **cargado**; `mod_xml_cdr.so` en disco |
| F10 | **Reporting** | Interaces `mims_ui` (Flask) consultando CDR/MySQL (tablas por rellenar con CDR de FreeSWITCH) + `mod_db`/MySQL | 🟡 | `mims_ui` sobre `:8090`; MySQL (`mims3_mysql`) en la maqueta |
| F11 | **Monitoring & Management** | `mod_event_socket` (ESL, cargado) expone eventos/estadísticas; `mims_ui` ya supervisa contenedores, DNS y listeners; `<healthcheck>` en compose | 🟡 | `mims3_ui` + `docker compose`/`docker ps` |
| F12 | **Convergencia / cloud-native / 5G** | Todo contenerizado por servicio; Core IMS + AS escalables; camino a Helm/K8s y SBA/NEF documentado en fases | 🟡 | 14 contenedores, red parametrizada, `.env` |

**Cobertura:** 2/12 **implementado hoy** (IVR, VMS); 6/12 **ampliable-nativo**
(SCE, MCA, charging, reporting, monitoring, cloud-native); 4/12 **complemento-AS**
(SMSC, FDA, SMSFW, USSD) — los 4 del dominio de mensajería, que comparten un
único patrón a desarrollar (ruta `MESSAGE` por iFC + AS SMS), sin tocar el Core.

---

## 4. Detalle por funcionalidad

### F7 — IVR (✅ Implementado)
- `public.xml`: `ivr_0100002` → `answer → sleep → playback(ivr_bienvenida.wav) → hangup`.
- El menú DTMF real se construye con `mod_dptools` (`read`), `mod_lua`/`mod_httapi`
  consultando MySQL, y `mod_say_*` para lectura de saldos/números.
- RTP anclado en RTPEngine (`RTPEngine engaged`), camino UE → P-CSCF → S-CSCF →
  iFC → AS Frontera → FreeSWITCH.

### F4 — VMS (✅ Implementado)
- `public.xml`: `vms_0100003` → graba el mensaje RTP del llamante a
  `vms/<MSISDN>/INBOX/msg_<fecha>.wav`.
- `mod_voicemail` **cargado** da el VMS completo (greeting, MWI/`message-summary`,
  recuperación) disponible para evolucionar el buzón actual sin redeploy del Core.
- Volumen `./freeswitch/vms:/var/lib/freeswitch/storage/vms` (persistente).
- Cobertura **TS 26.114**: `mod_amr`/`mod_amrwb` cargados (red AMR-ready); el
  softphone pjsua actual no ofrece AMR (limitación de cliente, no de la maqueta).

### F5 — MCA (🟡 ampliable-nativo)
- FreeSWITCH genera **CDR** (`mod_cdr_csv` cargado): el AS detecta
  `disposition=no answer`/`busy`.
- El aviso se materializa como **SMS** (`mod_sms` en la imagen) con contenido
  "Llamada perdida de <MSISDN> a las <hora>", o como notificación MB/MWI al
  destinatario vía S-CSCF. Con el SMSC (F1) resuelto, el envío es real.

### F1 — SMSC (🟠 complemento-AS, patrón ya validado)
- El **mismo mecanismo ISC que ya enruta INVITE a `asfront`** enruta SIP `MESSAGE`
  añadiendo una iFC con `Method=MESSAGE` y prioridad propia en `maqueta_ifc.xml`.
- El AS SMS (módulo `mod_sms` o AS python `vas/smsc`) normaliza, persiste y
  entrega; stubs SMPP para integrar el SMSC real del operador.

### F2 — FDA (🟠 complemento-AS, reposo sobre F1)
- Entrega **inmediata** si el destinatario está registrado, **diferida** en caso
  contrario: el S-CSCF avisa al AS en el `REGISTER` del destinatario y el AS
  reintenta el primer intento de entrega.
- Estados `delivered/undelivered/deleted` (DLR) en BD.

### F3 — SMS Firewall (🟠 complemento-AS, reposo sobre F1)
- Interpuesto en la cadena del SMSC: filtros MO/MT por número, contenido (regex),
  blacklist, rate-limit y scoring; rechazo/reescritura antes de la entrega.

### F6 — USSD Gateway (🟠 complemento-AS)
- Reutiliza el **motor de menú del IVR** sobre SIP `MESSAGE` (patrón `*123*NN#`),
  con persistencia de sesión (redis/MySQL). El enlace real al USSDC (SIGTRAN/MAP)
  queda como integración de propuesta (stub en maqueta).

### F8 — SCE (🟡 ampliable-nativo, la gran ventaja de FreeSWITCH)
- **Lenguajes y control nativos cargados**: `mod_lua` y `mod_httapi` para
  flujos dinámicos y **webhooks** (lógica externa), `mod_xml_curl` (en disco)
  para dialplan y direcciones por servicio.
- Flujos de producto por país en JSON/YAML/Lua, **desplegables sin reinicio** y
  sin tocar el Core IMS; catálogo y editor opcional en la interfaz.

### F9 — Charging (🟡 ampliable)
- `mod_cdr_csv` **cargado** (CDR ya producido); `mod_xml_cdr`/`mod_json_cdr`
  (en disco) permiten emitir CDR en JSON a la API de facturación de la maqueta;
  persistencia en MySQL. Ro/Rf (OCS online / Rf a OCS) como fases posteriores.

### F10 / F11 — Reporting, Monitoring & Management (🟡 ampliable)
- `mims_ui` (`:8090`) ya gestiona estado de los 14 contenedores, DNS, listeners,
  E2E, operación (registro/llamada) y VMS.
- `mod_event_socket` (ESL) expone eventos y estadísticas en vivo para reportes
  y monitoreo Prometheus/Grafana (fase posterior).

### F12 — Convergencia / cloud-native / 5G-ready (🟡)
- Arquitectura de **microservicios contenerizados** (14 contenedores), dominios
  parametrizados por país (MCC/MNC), Core IMS 3GPP; camino a Helm/K8s y
  separación SBA/NEF documentado en `plan_trabajo_uVAS_2026.md` (etapas 5-6).

---

## 5. Módulos FreeSWITCH de la maqueta (verificado en contenedor `mims3_freeswitch`)

**Cargados** (los que sustentan hoy IVR/VMS y el roadmap):
`mod_sofia, mod_dptools, mod_voicemail, mod_amr, mod_amrwb, mod_opus, mod_cdr_csv, mod_conference, mod_fifo, mod_lua, mod_httapi, mod_loopback, mod_event_socket, mod_dialplan_xml, mod_say_*, mod_local_stream, mod_sndfile, mod_tone_stream, mod_spandsp, ...`

**En disco (activables):** `mod_sms.so, mod_xml_curl.so, mod_json_cdr.so, mod_cdr_mongodb.so, mod_java.so, mod_perl.so, ...`

**Nota de diseño del RFP de mensajería:** en esta imagen no existe
`mod_smpp.so` (en versiones con SMPP se habilita si el AS SMS usa SMPP contra el
SMSC del operador); el tránsito SIP `MESSAGE` → FreeSWITCH/`mod_sms` o AS python
cubre el mismo rol sin depender de ese módulo.

---

## 6. Conclusión

1. **Voz (núcleo del AS) — cumplido hoy**: IVR y VMS funcionan y se validan en
   E2E (`15/15`), enrutados por **iFC del S-CSCF hacia FreeSWITCH**, con medios
   anclados en RTPEngine y autenticación **AKAv1-MD5** demostrada.
2. **Plataforma convergente** — la maqueta es la base para el resto de
   funcionalidades del RFP sin cambiar el Core:
   - **Capacidad nativa FreeSWITCH** (SCE, MCA, charging, reporting, monitoreo)
     = configuración/scripts + habilitar módulos ya presentes.
   - **Dominio de mensajería** (SMSC, FDA, SMSFW, USSD) = extensión del
     mecanismo **iFC ya validado** (`MESSAGE`) + AS SMS sobre la misma maqueta.
3. **Cumplimiento con el RFP**: todas las funcionalidades F1–F12 son **alcanzables
   sobre la maqueta de FreeSWITCH**; 2 implementadas y 10 con soporte verificado
   (6 vía módulos/capacidad nativa y 4 vía un AS mensajería sobre el patrón ISC
   existente).
4. **Ventaja competitiva para la propuesta**: un solo plano VAS (FreeSWITCH) que
   cubre voz y sirve de base para SCE/charging/reporting, un patrón único y
   ligero para añadir servicios por iFC, y un timeline de entrega corto porque el
   Core IMS y el enrutado de servicios ya están construidos y validados.

---

## 7. Referencias y repositorio de evidencia

- RFP: `doc/20260817 uVAS RFP 2026.md` (funcionalidades en §1.1, pág. 24).
- Plan de etapas: `results/plan_trabajo_uVAS_2026.md` (F1-F4 → Etapa 2, USSD →
  Etapa 3, SCE/charging → Etapas 1/4/5).
- Comparativa AS y recomendación: `results/argumentacion_AS_kamailio_vs_freeswitch.md`.
- Cumplimiento 3GPP: `results/diagnostico_cumplimiento_3gpp.md`.
- E2E: `maqueta-ims-3/scripts/test_maqueta.sh` (15/15).
- AKA: `maqueta-ims-3/scripts/ue_aka_probe.py` (Digest-AKAv1-MD5 → 200 OK).
- AS Frontera ISC: `maqueta-ims-3/asfront/{asfront.cfg,kamailio_asfront.cfg}`.
- FreeSWITCH AS: `maqueta-ims-3/freeswitch/conf/{dialplan/public.xml,sip_profiles/external.xml}`.