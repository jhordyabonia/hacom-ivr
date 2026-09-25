# Plan de trabajo — uVAS RFP 2026 (Millicom)

Plan de desarrollo paso a paso para responder al RFP `doc/20260817 uVAS RFP 2026.md`
aprovechando la **maqueta Core IMS + IVR** de `maqueta-ims/` (validada E2E 11/11).
Divide la entrega en **Producto Mínimo Viable (MVP)** y **desarrollos incrementales**.

> Documento interno (la propuesta a Millicom debe redactarse **en inglés**).
> El RFP exige (secciones 4.1-4.4): *Proposed Solution*, *Statements of Compliance*
> (Anexo B), *Commercial Offer* (Anexo C) y *Implementation Time Plan*. Este plan
> alimenta el *Implementation Time Plan* y el *Proposed Solution*.

---

## 0. Fechas del RFP (plan alineado al calendario)

| Hito RFP | Fecha | Estado |
|---|---|---|
| Acknowledge receipt | 19/Ago/2026 | ⚠️ Confirmar con Millicom si se emitió (parágrafo 2.2) |
| Technical clarifications | 20-31/Ago/2026 | ⚠️ Verificar si hubo preguntas pendientes |
| **Technical Presentation** | **14-17/Sep/2026** | Objetivo del **MVP** (ensayo 12-13/Sep) |
| **Submission Deadline** | **22/Sep/2026** | Objetivo: propuesta completa (MVP + roadmap) |
| Final negotiation | 23/Sep-7/Oct/2026 | Preparar detalle de etapas 2-6 |

Contactos RFP (solo e-mail, 2.2/2.6): `davide.giannetti@millicom.com` (procurement),
`Irving.Barria@Millicom.com` (technical lead).

## 1. Punto de partida — inventario de la maqueta

Lo que ya existe y está **validado** (11/11 PASS vía `scripts/test_maqueta.sh` y
`POST /api/test` de `mims_ui`):

| Componente | Dónde | Rol |
|---|---|---|
| Core IMS (Kamailio 6.2) | `maqueta-ims/{pcscf,icscf,scscf,kamailio}/` | P-CSCF :5060, I-CSCF :4060, S-CSCF :6060 |
| HSS (PyHSS, Cx Diameter) | `maqueta-ims/pyhss/` | UAR/UAA, MAR/MAA, SAR/SAA + iFC (`maqueta_ifc.xml`) |
| Aplicación (AS) — Asterisk + IVR | `maqueta-ims/asterisk/` | IVR `ivr_bienvenida` enrutado por iFC (ISC) |
| Plano de medios | `maqueta-ims/rtpengine/` | RTPEngine (anclaje, log *RTPEngine engaged*) |
| DNS / BD / caché | `maqueta-ims/{dns,mysql}/` + redis | BIND `ims.mnc001.mcc001.3gppnetwork.org`, BD `icscf`, redis |
| UEs (pjsua) | `maqueta-ims/softphone/` | Registro IMS UE1/UE2, llamadas deterministas (`--outbound`) |
| Orquestación | `maqueta-ims/docker-compose.yml` + `.env` | Red `172.30.0.0/24`, 13 contenedores, `restart: unless-stopped` |
| Interfaz de operación | `maqueta-ims/interfaz/` | Flask+Docker SDK, `http://localhost:8090` (Estado/E2E/Operación/Config/Logs) |
| Verificación | `maqueta-ims/scripts/test_maqueta.sh` | 11 checks: contenedores, DNS, listeners, registros, llamada, IVR, RTPEngine |
| Docs | `maqueta-ims/docs/` | `paso_a_paso.md`, `manual_interfaz.md`, `arquitectura.drawio`, guiones demo |

## 2. Brechas frente al RFP

Lo que pide el RFP (pág. 24) y cómo se cubre con la maqueta:

| Requisito RFP | Estado | Cómo se cubre (etapa) |
|---|---|---|
| **IVR** | ✅ Maqueta | Productizar: menús DTMF + BD + flujos configurables (Etapa 1) |
| **VMS (buzón de voz)** | ❌ Falta | Nuevo AS Asterisk/Freeswitch por iFC (Etapa 1) |
| **MCA (aviso de llamada perdida)** | ❌ Falta | Nuevo AS evento → notificación (Etapa 1, SMS nativo en 2) |
| **SMSC** | ❌ Falta | AS SMSoIP (SIP MESSAGE) + cola (Etapa 2) |
| **FDA (primer intento de entrega)** | ❌ Falta | Cola SMSC + entrega diferida al registrar (Etapa 2) |
| **SMS Firewall** | ❌ Falta | Filtros MO/MT en cadena SMSC (Etapa 2) |
| **USSD Gateway** | ❌ Falta | AS USSD (emula vía SIP MESSAGE; stub SMPP) (Etapa 3) |
| **SCE (creación de servicios)** | ❌ Falta | Motor IVR + diseñador visual + plantillas país (Etapa 4) |
| **Charging** | ❌ Falta | CDR local → MySQL (Ro/Rf) (Etapa 1 básica, 5 completa) |
| **Reporting / Monitoring / Mgmt** | ◑ Parcial | `mims_ui` (Estado/Logs) → pestañas Reportes y Monitoreo (Etapa 1-2) |
| **Multi-país (CL/UY/CO/EC)** | ◑ Parcial | Entorno por instancia/dominio MCC-MNC (Etapa 5) |
| **Cloud-native / virtualizado / 5G** | ◑ Parcial | Contenedores ya; microservicios + Helm/K8s + NFE/SBA (Etapa 5) |
| **L3 Support / mantenimiento** | ❌ Falta | Runbooks, MOP, equipos (Etapa 6) |

## 3. Arquitectura objetivo (cómo se extiende la maqueta)

**Principio rector:** cada servicio VAS es un **Application Server (AS)** enrutado por
**iFC del HSS vía ISC**, del mismo modo que hoy se enruta el IVR. Nada del Core
(P/I/S-CSCF, HSS, RTPEngine) cambia de tecnología; solo se **añaden AS** y se
**amplían iFC**.

```
 UE(pjsua) ─Gm─> P-CSCF ──> I-CSCF ──> S-CSCF ──ISC/iFC──> +- IVR..  (Etapa 1)
                                          │                 +- VMS...  (Etapa 1)
                                          │                 +- MCA.... (Etapa 1)
                                          │                 +- SMSC..  (Etapa 2)
                                          │                 +- USSD..  (Etapa 3)
                                          │                  +- SCE... (Etapa 4)
                                          │ Cx (MAR/SAR) / Charging (Rf/Ro) / CDR ─> MySQL
                                          └─> RTPEngine (medios) ─> AS de voz
```

Decisiones de arranque:

1. **Repositorio `maqueta-ims/vas/`** para todos los AS de valor (cada uno con su
   `Dockerfile`, config y tests). El Core IMS se mantiene intacto (`pcscf/`, `icscf/`,
   `scscf/`, `pyhss/`, `rtpengine/`).
2. **iFC en `maqueta-ims/pyhss/maqueta_ifc.xml`** = único punto de enrutamiento;
   cada regla nueva añade un `<InitialFilterCriteria>` con `<Priority>` (30 hoy IVR,
   40 terminating-unregistered).
3. **BD y colas**: reutilizar `mims_mysql` (nueva BD `vas`) y `mims_redis` para
   colas/estados (SMSC, VMS, MCA).
4. **Charging**: cada AS emite CDR (JSON) → API común `vas/ocs` → tabla `cdr` en
   MySQL; consulta desde `mims_ui`.
5. **`mims_ui`** (`interfaz/app.py`) se amplía con pestañas **Reportes** y
   **Monitoreo** y con el E2E extendido (de 11 a ~18 checks).
6. **Multi-país**: cada instancia = un `.env`/`values` con `MCC/MNC`, dominio,
   plan de numeración y credenciales (la maqueta ya parametriza MCC/MNC).

---

## 4. Etapas de desarrollo

Cada etapa tiene **objetivo**, **tareas (qué y dónde)** y **criterio de salida**.
Las etapas 0-1 conforman el **MVP para la presentación técnica (14-17/Sep)**.
Las etapas 2-6 son incrementales (post-presentación, a detallar en la propuesta).

### Etapa 0 — Consolidar la maqueta (base de todo) — 10-11/Sep

Objetivo: que la maqueta sea la **plataforma demo reproducible** y queden capturas/scripts
para la presentación.

| # | Qué hacer | Dónde |
|---|---|---|
| 0.1 | Verificar E2E y script: 11/11 | `bash scripts/test_maqueta.sh`; `curl -X POST http://localhost:8090/api/test` |
| 0.2 | Añadir **healthchecks** a `dns,mysql,redis,pyhss_*,icscf,scscf,pcscf,rtpengine,asterisk,dns,softphone,ui` | `maqueta-ims/docker-compose.yml` (bloque `healthcheck:` + `depends_on: condition: service_healthy`) |
| 0.3 | Crear `scripts/demo.sh`: reinicia todo, provisiona, registra UEs y deja 2 UEs con llamada lista | `maqueta-ims/scripts/demo.sh` |
| 0.4 | Capturas: Estado 13/13, E2E 11/11, logs S-CSCF iFC, log *RTPEngine engaged* | `maqueta-ims/docs/evidencias/` |
| 0.5 | Actualizar docs con resultado (ya verdes) | `maqueta-ims/docs/{paso_a_paso,conclusiones,manual_interfaz}.md` |

Criterio de salida: `test_maqueta.sh` 11/11 dos veces seguidas + carpeta `evidencias/`.
Recomendado también hacer `docker compose up -d --force-recreate` limpio desde cero.

### Etapa 1 — MVP de voz: IVR productivo + VMS + MCA + charging + reporting (objetivo presentación 14-17/Sep) — 11-13/Sep

Objetivo: demostrar una **plataforma VAS de voz** completa sobre el Core IMS:
IVR con menú DTMF, buzón de voz (VMS), aviso de llamada perdida (MCA), CDRs y
panel de reportes — TODO enrutable por iFC y verificable desde `mims_ui`.

**1.1 IVR como servicio (productizar el existente)**

| # | Qué hacer | Dónde |
|---|---|---|
| 1.1.1 | Extender `extensions.conf` con 3 flujos demo: bienvenida → menú → IVR DTMF (saldo simulado / opciones), consultando MySQL | `maqueta-ims/asterisk/extensions.conf` (contexto `ims-in`) |
| 1.1.2 | Config de flujos por país en JSON (servida por la API del IVR) | nuevo `maqueta-ims/vas/ivr/flows/*.json` |
| 1.1.3 | Scripts de base de datos `vas` (tablas `ivr_flow`, `ivr_option` ctl) | `maqueta-ims/vas/db/schema.sql` (cargada por `mysql_init`) |
| 1.1.4 | API REST del IVR (Flask) para consultar/configurar flujos | nuevo `maqueta-ims/vas/ivr/api.py` (imagen `vas_ivr`) |
| 1.1.5 | Ampliar `mims_ui` con datos del IVR (lectura desde API) | `maqueta-ims/interfaz/app.py` (nuevos endpoints `/api/ivr/*`) |

**1.2 VMS (buzón de voz)**

| # | Qué hacer | Dónde |
|---|---|---|
| 1.2.1 | Perfil de buzón por MSISDN en BD `vas` (plan de numeración del país) | `maqueta-ims/vas/db/schema.sql` |
| 1.2.2 | Contexto Asterisk `msv-voicemail`: si el destino no contesta (timeout de anillo), grabar mensaje y colgar | `maqueta-ims/asterisk/extensions.conf` + `voicemail.conf` |
| 1.2.3 | Nueva iFC **terminating** para destinos no registrados → VMS (antes priority 40 del IVR) | `maqueta-ims/pyhss/maqueta_ifc.xml` (añadir `<InitialFilterCriteria>` Priority 50 → `sip:vms.<dominio>:5060`) |
| 1.2.4 | Notificación de mensaje nuevo (MWI SIP `NOTIFY`/`message-summary`) | `maqueta-ims/asterisk/extensions.conf` (callback vía S-CSCF al UE) |
| 1.2.5 | Optional: como VMS robusto, AS propio vehiculizado | `maqueta-ims/vas/vms/` (imagen `vas_vms`, sólo si hay tiempo) |

**1.3 MCA (aviso de llamada perdida)**

| # | Qué hacer | Dónde |
|---|---|---|
| 1.3.1 | Servicio MCA: captura eventos "no contestado" (log Asterisk/patrón y API) | `maqueta-ims/vas/mca/` (imagen `vas_mca`, Python/Flask) |
| 1.3.2 | Generar aviso "llamada perdida de X" → notificación SIP (MWI) / cola; si no hay SMSC aún, log+API (SMS real en Etapa 2) | `maqueta-ims/vas/mca/handlers.py` |
| 1.3.3 | Enrutado: escucha del evento de llamada no contestada (hook) | `maqueta-ims/asterisk/extensions.conf` (contexto `ims-mca`) |

**1.4 Charging básico (CDR + OCS stub)**

| # | Qué hacer | Dónde |
|---|---|---|
| 1.4.1 | CDR de Asterisk a MySQL (tabla `cdr`) con `ami`/`cdr.conf` | `maqueta-ims/asterisk/cdr.conf`, `maqueta-ims/vas/db/schema.sql` |
| 1.4.2 | API común `vas/ocs`: ingesta CDR (JSON), persistencia y consulta | `maqueta-ims/vas/ocs/api.py` (imagen `vas_ocs`) |
| 1.4.3 | (Futuro Ro) stub de OCS online por consumo | `maqueta-ims/vas/ocs/ro_stub.py` (Etapa 5) |

**1.5 Reporting y Monitoreo en `mims_ui`**

| # | Qué hacer | Dónde |
|---|---|---|
| 1.5.1 | Pestaña **Reportes**: tabla CDR (fecha, llamante, llamada, duración, coste) y tráfico por AS | `maqueta-ims/interfaz/static/{index.html,app.js,style.css}`, endpoints en `interfaz/app.py` |
| 1.5.2 | Pestaña **Monitoreo**: contadores por AS (`/metrics` estilo Prometheus) y estado de los 13 contenedores | `maqueta-ims/vas/ocs/metrics.py`, `interfaz/app.py` |
| 1.5.3 | Ampliar E2E a ~15-18 checks (registro, IVR DTMF, VMS graba, MCA notifica, CDR presente) | `maqueta-ims/interfaz/app.py` (`api_test`) + `scripts/test_maqueta.sh` |

**1.6 Presentación técnica (14-17/Sep)**

| # | Qué hacer | Dónde |
|---|---|---|
| 1.6.1 | Guion de demo actualizado (MVP voz) | `maqueta-ims/docs/guion_meet.md`, `guion_meet-2.md` |
| 1.6.2 | Ensayo 12-13/Sep con `scripts/demo.sh` + `test_maqueta.sh` | `maqueta-ims/scripts/` |
| 1.6.3 | Material: diagrama arquitectura extendida, matriz de cumplimiento (borrador), roadmap | `maqueta-ims/docs/arquitectura.drawio`, `docs/` |

Criterio de salida (MVP): demo de 20 min con **IVR con menú DTMF → VMS → notificación MCA
→ CDR visible en `mims_ui`**, E2E de 15+ checks verde, presentación preparada.

### Etapa 2 — Familia SMS: SMSC + FDA + SMS Firewall — (post-presentación, semana 3-4/Sep 2026)

Objetivo: incorporar mensajería SIP (SMSoIP), entrega garantizada (FDA) y control
anti-fraude (SMS Firewall).

| # | Qué hacer | Dónde |
|---|---|---|
| 2.1 | Habilitar tránsito de `MESSAGE` en S-CSCF (relay ISC) y en P-CSCF | `maqueta-ims/scscf/kamailio_scscf.cfg`, `pcscf/kamailio_pcscf.cfg` (rutas `MESSAGE`, `t_relay`) |
| 2.2 | iFC para `MESSAGE` originado/terminating → SMSC AS | `maqueta-ims/pyhss/maqueta_ifc.xml` (nuevo `<InitialFilterCriteria>` Priority 60) |
| 2.3 | AS **SMSC (SMSoIP)** en Python: acepta SIP MESSAGE, valida, persiste y entrega | `maqueta-ims/vas/smsc/` (`api.py`, `store.py`, `deliver.py`, imagen `vas_smsc`) |
| 2.4 | **FDA**: cola en redis; entrega inmediata si el destinatario está registrado (usrloc) o **diferida** hasta su próximo registro (hook al S-CSCF) | `maqueta-ims/vas/smsc/deliver.py`, `maqueta-ims/scscf/kamailio_scscf.cfg` (aviso de registro → `sql_pv`/API) |
| 2.5 | **DLR / estados** (deleted/undelivered/delivered) y stats | `maqueta-ims/vas/db/schema.sql` (tabla `sms_store`, `sms_dlr`) |
| 2.6 | **SMS Firewall**: filtros MO/MT (regex, blacklist, rate limit, scoring) | `maqueta-ims/vas/smsfw/` (`policy.py`, imagen `vas_smsfw`), interpuesto en cadena SMSC |
| 2.7 | Stub **SMPP** (ESME externo) para demos e integración futura | `maqueta-ims/vas/smsc/smpp_stub.py` |
| 2.8 | E2E SMS: UE→SMSC→UE con DLR; MCA pasando a SMS real | `maqueta-ims/scripts/test_maqueta.sh` (nuevos checks) |

Criterio de salida: envío UE1→UE2 con DLR, FDA con entrega diferida demostrada y un
filtro de firewall en acción (demo).

### Etapa 3 — USSD Gateway — (octubre 2026, post-award)

| # | Qué hacer | Dónde |
|---|---|---|
| 3.1 | AS **USSD** que recibe `MESSAGE`/`INVITE` con el string USSD y ejecuta menú por etapas | `maqueta-ims/vas/ussd/` (`session.py`, `menu.py`, imagen `vas_ussd`) |
| 3.2 | iFC para enrutar USSD (patrón `*123*NN#`) → USSD AS | `maqueta-ims/pyhss/maqueta_ifc.xml` (Priority 70, condición Request-URI) |
| 3.3 | Contenidos demo (saldo/recarga simulado, opt-in) y persistencia de sesión | `maqueta-ims/vas/ussd/flows.yaml`, `vas/db/schema.sql` |
| 3.4 | Stub de integración con red real (SIGTRAN/MAP) para propuesta | `maqueta-ims/vas/ussd/map_stub.py` |

Criterio de salida: sesión USSD completa `*123*...#` con menú y acción, en E2E.

### Etapa 4 — SCE (Service Creation Environment) y unificación — (octubre-noviembre 2026)

| # | Qué hacer | Dónde |
|---|---|---|
| 4.1 | Diseñador visual de flujos de voz (IVR builder) sobre el motor IVR | `maqueta-ims/vas/sce/` (imagen `vas_sce`, editor web + API de deploy) |
| 4.2 | Deploy de flujos (JSON) a los AS (IVR/USSD/VMS) sin redeploy | `maqueta-ims/vas/sce/deployer.py`, `vas/ivr/` |
| 4.3 | Webhooks/URL-API para lógica externa en flujos | `maqueta-ims/vas/sce/` |
| 4.4 | Plantillas de producto por país y catálogo de servicios | `maqueta-ims/vas/templates/<pais>/` |

Criterio de salida: crear, desplegar y reproducir un flujo IVR nuevo desde el SCE en el
mismo día, sin tocar el Core.

### Etapa 5 — Multi-país, cloud-native y 5G-ready — (diciembre 2026 en adelante)

| # | Qué hacer | Dónde |
|---|---|---|
| 5.1 | **Multi-instancia por país** (CL, UY, CO, EC): valores por `MCC/MNC`, dominio, plan de numeración | `maqueta-ims/.env` → `deploy/helm/values-{cl,uy,co,ec}.yaml`, refactor `pyhss/maqueta_ifc.xml` (generado por país) |
| 5.2 | **Cloud-native**: helm charts de todos los servicios (13) + CI/CD local | `deploy/helm/`, `deploy/k8s/` (añadir bajo `maqueta-ims/`) |
| 5.3 | HA/escalado: réplicas de S-CSCF, SMSC, IVR; SLB; colas tolerantes | `deploy/helm/` (autoscaling), redis cluster |
| 5.4 | Observabilidad: Prometheus + Grafana + Loki (métricas de los 13 contenedores y AS) | `deploy/observability/` (o forja en `vas/monitoring`) |
| 5.5 | **Charging completo**: Ro (stub→OCS) + Rf (CDR a OCS real) + reporte financiero | `maqueta-ims/vas/ocs/` (ampliar) |
| 5.6 | 5G-ready: separación de planos, soporte SBA/NEF (IMS Data Channel), slicing | `docs/arquitectura-5g.md`, roadmap contract |
| 5.7 | Migración y dual-run por país (CL→UY→CO→EC) con rollback | `docs/plan-migracion.md` |

### Etapa 6 — Operación, soporte, seguridad y entrega — (continua)

| # | Qué hacer | Dónde |
|---|---|---|
| 6.1 | Runbooks, MOPs y página de mantenimiento | `docs/runbooks/`, `docs/manual_interfaz.md` |
| 6.2 | Soporte **L3**: números de escalado, horarios (4 países), docto SLA | Propuesta comercial (Anexo C) |
| 6.3 | **Seguridad**: hardening (WAF en `mims_ui`, auth anti-SSRF, secretos en vault), cifrado TLS | `maqueta-ims/interfaz/`, `deploy/helm/` |
| 6.4 | Privacidad/Legal: LGPD y regulación local CO/UY/CL/EC, borrado de datos | `docs/privacidad.md` |
| 6.5 | **Statement of Compliance** completo (Anexo B) y **Tenderer Details** (Anexo A) | Documento de propuesta (inglés) |

---

## 5. Backlog consolidado (vista rápida)

| Fase | Entregable | Componentes | Criterio de salida |
|---|---|---|---|
| E0 (10-11/Sep) | Maqueta robusta y demostrable | compose+healthchecks, `scripts/demo.sh`, `docs/evidencias/` | 11/11 dos veces, build limpio |
| E1 MVP (11-13/Sep) | IVR menú + VMS + MCA + CDR + reportes/monitor | `vas/ivr,vms,mca,ocs`, `asterisk/extensions.conf`, iFC, `mims_ui` | Demo 20 min, E2E 15+ checks |
| E1.6 (14-15/Sep) | Presentación técnica + borrador Anexo B/C | `docs/*`, propuesta en inglés | Envío a Millicom |
| E2 (post-award) | SMSC + FDA + SMS FW | `vas/smsc,smsfw`, rutas MESSAGE, SMPP stub | E2E SMS con DLR |
| E3 | USSD GW | `vas/ussd`, iFC USSD | Sesión USSD completa |
| E4 | SCE | `vas/sce`, deployer, plantillas | Crear flujo en el día |
| E5 | Multi-país, HA, 5G, Ro/Rf | helm, observabilidad, ocs | Instancia por país, cutover |
| E6 | Operación/seguridad/L3/entrega | runbooks, hardening, Anexos | Delivery final |

## 6. Riesgos y mitigaciones

| Riesgo | Mitigación |
|---|---|
| Avenida SMSoIP/SMPP con la red real del operador (SS7/SIGTRAN) | Demostrar con stubs (SMPP/SS7) en maqueta; fase contratada de integración |
| USSD no es estándar IMS | Emular sobre SIP MESSAGE; interfaz MAP/USSDG real en Etapa 3-5 |
| Falta el **Anexo B** (técnico) en el RFP (dice "Document shared in the email") | **Pedirlo por e-mail** a `Irving.Barria` cuanto antes; mantener matriz de trazabilidad |
| Los plazos de la presentación técnica son inmediatos (14-17/Sep) | MVP acotado a voz (E1); SMS/USSD/SCE como roadmap |
| Viernes de demo inestable (contenedores caídos) | `restart: unless-stopped` + healthchecks + `scripts/demo.sh` |
| iFC saturado de reglas | El enrutamiento de cada VAS se aisla con `<Priority>` y `<SessionCase>` |

## 7. Referencias

- RFP: `doc/20260817 uVAS RFP 2026.md`
- Maqueta: `maqueta-ims/` (docs en `maqueta-ims/docs/`)
- Guía de despliegue: `maqueta-ims/docs/paso_a_paso.md` · Interfaz: `maqueta-ims/docs/manual_interfaz.md`
- Diagrama: `maqueta-ims/docs/arquitectura.drawio` (extender en E1.6)