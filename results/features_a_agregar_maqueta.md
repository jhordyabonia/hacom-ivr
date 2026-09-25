# Features a agregar a la maqueta Core IMS/uVAS

> Inventario de **desarrollos a incorporar** a la maqueta `maqueta-ims-3`
> (Core IMS + AS Frontera ISC + FreeSWITCH como AS aplicación) para cubrir las
> funcionalidades del RFP uVAS 2026.
> Base: `results/cruce_RFP_maqueta_FreeSWITCH.md` (trazabilidad F1–F12) y
> estado validado E2E **20/20** (15 base + 3 de FEAT-01/FEAT-01b) + AKA (Digest-AKAv1-MD5)
> demostrado.
>
> **Principio rector:** cada servicio VAS es un **Application Server (AS)**
> enrutado por **iFC del HSS vía ISC**, igual que hoy el INVITE a `asfront`.
> El Core (P/I/S-CSCF, PyHSS, RTPEngine) no cambia de tecnología; se **añaden
> AS** y se **amplían iFC**, dialplan FreeSWITCH, BD y la interfaz `mims_ui`.

---

## 1. Resumen ejecutivo

| ID | Feature | RFP | Tipo | Prioridad | Estado actual |
|----|---------|-----|------|-----------|---------------|
| FEAT-01 | IVR productivo (menú DTMF + BD + flujos por país) | F7 | Ampliación | P0 | **Listo** (E2E 17/17) |
| FEAT-01b | Cambio de contraseña/PIN del suscriptor por IVR | F7 | Ampliación | P0 | **Listo** (E2E 20/20) |
| FEAT-02 | VMS completo (mod_voicemail, MWI, recuperación) | F4 | Ampliación | P0 | VMS básico listo |
| FEAT-03 | MCA — aviso de llamada perdida | F5 | Ampliación nativa | P0 | No |
| FEAT-04 | Charging: CDR → MySQL + API | F9 | Ampliación nativa | P1 | No (CDR ya se genera) |
| FEAT-05 | Reporting + Monitoring en `mims_ui` | F10/F11 | Ampliación | P1 | Interfaz base lista |
| FEAT-06 | SMSC (SMSoIP) + DLR | F1 | Nuevo AS | P1 | No (patrón iFC listo) |
| FEAT-07 | FDA — First Delivery Attempt | F2 | Nuevo AS | P2 | No |
| FEAT-08 | SMS Firewall (MO/MT) | F3 | Nuevo AS | P2 | No |
| FEAT-09 | USSD Gateway (emulación IMS) | F6 | Nuevo AS | P2 | No |
| FEAT-10 | SCE — Service Creation Environment | F8 | Motor + UI | P1 | Módulos nativos listos |
| FEAT-11 | Cloud-native / multi-país / 5G-ready | F12 | Plataforma | P3 | Base contenerizada |

Leyenda: **P0** = MVP de voz (presentación técnica), **P1** = post-award inmediato,
**P2** = familia SMS/USSD, **P3** = cloud-native/5G. "*AS nuevo*" = componente
adicional detrás de su propia iFC, sin tocar el Core.

---

## 2. Feature 01 — IVR productivo (menú DTMF) [RFP F7]

**Objetivo:** que el IVR de la maqueta pase de *playback único* a un **servicio
de menú interactivo** configurable y persistente.

**Comportamiento esperado:**
1. UE llama a un número de servicio (p.ej. `0100002`). FreeSWITCH responde y
   reproduce un saludo + menú de opciones.
2. El usuario pulsa dígitos DTMF; el servicio ejecuta una acción
   (saldo simulado, repetir, transferir, colgar).
3. Los flujos se definen en **JSON/Lua por país** y se consultan en **MySQL**.
4. Cada sesión genera un **CDR** con la opción elegida (enlaza con FEAT-04).

**Cambios en la maqueta:**
- `freeswitch/conf/dialplan/public.xml`: añadir contexto/servicio de IVR
  (apps `answer`, `read` con `inter-digit-timeout`, `playback`, `transfer`).
- Nuevas apps del motor: `mod_lua` (flujos) y `mod_httapi` (webhooks/API).
- BD: usar `mims3_mysql` con esquema `vas` (tablas `ivr_flow`, `ivr_option`).
- UI `mims_ui`: pestaña IVR para listar/validar flujos.

**Definición de hecho (aceptación):**
- E2E nuevo check: "IVR modúa opción DTMF → acción ejecutada (check en log FS)".
- Un flujo nuevo se puede desplegar **sin reiniciar FreeSWITCH**.
- CDR de la sesión aparece en BD/UI.

> **ESTADO: LISTO** (ramas `feature/feat-01-ivr-dtmf` + `feature/feat-01b-cambio-password`,
> E2E **20/20**).
> Implementado en `maqueta-ims-3/freeswitch`:
> - `conf/dialplan/public.xml`: extensión `ivr_menu_0100002` (answer →
>   `set ivr_flow=<pais>` → `lua ivr_flow.lua ${ivr_flow}` → hangup).
> - `scripts/ivr_flow.lua`: motor Lua — parser JSON embebido, saludo, menú
>   `play_and_get_digits` (vía `session:execute`, que sí consume el RFC 2833 que
>   el binding `session:playAndGetDigits` descartaba), acciones playback/bye y
>   persistencia del CDR de opción en `logs/ivr_cdr.jsonl` + log `IVR_ACTION`.
> - `flows/cl.json` (`1`=saldo, `2`=ayuda, `9`=colgar) y `flows/co.json`
>   (`1`=recarga): desplegable sin reiniciar FreeSWITCH (bind-mount).
> - `audio/{menu,saldo,ayuda,invalido}.wav` (8 kHz).
> - Check E2E (PASO 5b de `scripts/test_maqueta.sh`): "FEAT-01: menú DTMF
>   (opción 1)" y "FEAT-01: CDR de opción persistido" → ambos PASS.
> - Apto posteriormente para FEAT-09 (menu USSD) y FEAT-10 (SCE).

### 2b. Feature 01b — Cambio de contraseña/PIN del suscriptor por IVR [RFP F7]

**Objetivo:** que el usuario cambie su **contraseña de servicio (PIN)** con el
mismo menú DTMF, sin tocar el Core (ni PyHSS/SIP-AKA ni el PIN del VMS).

**Comportamiento esperado:**
1. Opción del menú IVR (p.ej. `3` = "cambiar contraseña") por país en los flujos.
2. El IVR captura el **nuevo PIN (4 dígitos)** y su **confirmación** (2 intentos).
3. Si coincide, persiste en BD (`vas.subscriber_pin`) vía API REST del `mims_ui`.
4. Reproduce audio de éxito/fallo y vuelve al menú; log de servicio `IVR_PIN`.

**Cambios en la maqueta:**
- BD: esquema `vas` → tabla `subscriber_pin` (`msisdn` PK, `pin`, `updated_at`);
  creada también en `mysql/mysql_init.sh` (idempotente) para despliegues limpios.
- `interfaz/app.py`: API `POST /api/pin/change` (upsert), `GET /api/pin`
  (listado) y vista `GET /pin`; escritura por docker-exec a MySQL (sin lib de BD).
- `freeswitch/scripts/ivr_flow.lua`: acción `password` — captura 4+4 dígitos con
  `session:execute("play_and_get_digits", …)`, POST JSON con **busybox wget**
  (el wget GNU de la imagen segfaulta) y log `IVR_PIN caller=… result=ok|fail`.
- `freeswitch/flows/{cl,co}.json`: opción `3` → `action:"password"` + prompts y
  URL de la API (claves `pin_prompt/confirm/ok/fail`, `pin_api`).
- `freeswitch/audio/pin_*.wav` (8 kHz): prompt, confirmación, éxito, fallo.

**Definición de hecho (aceptación):**
- E2E (PASO 5c de `scripts/test_maqueta.sh`): cambio de contraseña (opción 3)
  → `IVR_PIN result=ok`; PIN persistido en `vas.subscriber_pin`; y
  confirmación distinta → `result=fail` **sin** persistir. → 3 checks PASS.

> **ESTADO: LISTO** (rama `feature/feat-01b-cambio-password`, E2E **20/20**).
> Notas: el contenedor FS no tiene curl y su `wget` GNU aborta (segv); se usa
> `/bin/busybox timeout <n> /bin/busybox wget --post-data …`. En el test, pjsua
> puede perder un bloque de stdin (la confirmación); el PASO 5c reenvía la
> confirmación para hacerlo determinista.

---

## 3. Feature 02 — VMS completo (mod_voicemail) [RFP F4]

**Objetivo:** evolucionar el buzón actual a **VMS estándar** (prompts,
bienvenida del dueño, MWI, recuperación y borrado por el usuario).

**Comportamiento esperado:**
- Destino no registrado / ocupado / sin respuesta → iFC *terminating* enruta a
  VMS (`0100003`); el AS solicita el tono y graba.
- Notificación **MWI** (`SIP NOTIFY message-summary`) al suscriptor cuando tiene
  mensaje nuevo.
- Recuperación: el dueño llama al buzón, autentica (PIN), escucha/borra mensajes.

**Cambios en la maqueta:**
- Activar `mod_voicemail` con mailbox por MSISDN (`voicemail.conf` + dialplan).
- Nueva **iFC terminating** (`Priority` 50, `SessionCase` 2) en
  `pyhss/maqueta_ifc.xml` → `sip:asfront…:5060` para llegar a FreeSWITCH.
- MWI: `NOTIFY` retornado por el S-CSCF al UE registrado (callback en
  `scscf/kamailio_scscf.cfg`).

**Definición de hecho:**
- UE1 deja mensaje en el buzón de UE2 (desregistrado) y UE2 recibe MWI.
- UE2 recupera y borra el mensaje.
- E2E: +2 checks (MWI, recovery).

---

## 4. Feature 03 — MCA (aviso de llamada perdida) [RFP F5]

**Objetivo:** notificar al suscriptor cuando recibe una llamada que no contesta.

**Comportamiento esperado:**
- El AS detecta llamadas con `no answer`/`busy` (eventos/CDR).
- Genera el aviso "Llamada perdida de <MSISDN> a las <HH:MM>" y lo entrega como
  **SMS** (una vez exista FEAT-06) o como notificación **MWI**/SIP en primer
  corte (vía FEAT-02).
- Estado del aviso (entregado/no) en BD para reporte.

**Cambios en la maqueta:**
- `mod_event_socket` para subscribirse a eventos de llamada, o lectura de CDR
  (`mod_cdr_csv`/`mod_xml_cdr`) con `disposition=NO ANSWER|BUSY`.
- AS ligero `vas/mca` (Python/Flask) que correlaciona CDR → aviso.
- Primera entrega: MWI; con SMSC (FEAT-06) la entrega pasa a SMS real.

**Definición de hecho:**
- UE1 llama a UE2 (no contesta) → aviso "llamada perdida" visible en la BD y
  entregado por el medio activo (MWI o SMS).
- E2E: check "MCA genera aviso".

---

## 5. Feature 04 — Charging: CDR → MySQL + API [RFP F9]

**Objetivo:** monetizar los servicios: **toda** sesión (IVR, VMS, MCA, SMS)
deja un CDR persistido y consultable.

**Comportamiento esperado:**
- FreeSWITCH emite CDR (ya con `mod_cdr_csv`); se añade `mod_xml_cdr` (JSON)
  hacia una API común.
- La API `vas/ocs` ingresa el CDR, calcula coste (tarifa por servicio/pais) y lo
  persiste en MySQL (tabla `cdr`).
- Preparado para futuros **Ro** (OCS online) y **Rf** (forwards a OCS).

**Cambios en la maqueta:**
- `freeswitch/conf/autoload_configs/xml_cdr.conf.xml` (módulo en disco) → POST a
  la API de CDR.
- Nuevo servicio `vas/ocs` (Python/Flask) + esquema `vas` (tablas `cdr`,
  `tariff`).
- Extensiones hacia `mims_ui` (reportes usa estos datos — FEAT-05).

**Definición de hecho:**
- Tras una llamada IVR/VMS, aparece el CDR (fecha, llamante, destino, duración,
  coste) en BD y en la UI.
- E2E: check "CDR generado".

---

## 6. Feature 05 — Reporting + Monitoring en `mims_ui` [RFP F10/F11]

**Objetivo:** convertir la interfaz en el panel de operación: informes de
tráfico, estado de servicios en vivo y gestión.

**Comportamiento esperado:**
- Pestaña **Reportes**: CDR (por servicio, llamante, país), tráfico por hora,
  ingresos estimados.
- Pestaña **Monitoreo**: contadores por AS (`/metrics` Prometheus), estado de
  los 14 contenedores (ya hoy), listeners, últimas alarmas.
- Métricas en vivo: `mod_event_socket` (estadísticas de FreeSWITCH) + `docker stats`.

**Cambios en la maqueta:**
- `interfaz/app.py` + frontend (endpoints `/api/reports/*`, `/api/metrics/*`).
- Exporter ligero por AS (`vas/ocs/metrics.py`) o `mims_ui` agregando `docker stats`.
- Dashboard HTML/CSS/JS (pestañas nuevas).

**Definición de hecho:**
- La UI muestra CDR del día y contadores de cada nodo sin comandos manuales.
- E2E: check "endpoints de reporte responden".

---

## 7. Feature 06 — SMSC (SMSoIP) + DLR [RFP F1]

**Objetivo:** habilitar el dominio de mensajería SIP sobre la misma maqueta:
enviar/replicar SMS end-to-end (UE→SMSC→UE) con estados de entrega.

**Comportamiento esperado:**
1. UE1 envía `SIP MESSAGE` → P-CSCF → S-CSCF evalúa iFC `Method=MESSAGE` →
   enruta al **AS SMSC**.
2. El AS persiste el mensaje, aplica cadena de entrega (ver FEAT-08), y lo
   entrega como `MESSAGE` al destinatario (registrado) vía S-CSCF.
3. Registro de estado **DLR**: `delivered / undelivered / deleted`.

**Cambios en la maqueta:**
- `scscf/kamailio_scscf.cfg` + `pcscf/kamailio_pcscf.cfg`: rutas de `MESSAGE`
  (relay y anclaje de PANI también para MESSAGE).
- `pyhss/maqueta_ifc.xml`: iFC nueva (`<RequestURI>`/metodo MESSAGE,
  `Priority` 60) → `sip:asfront…:5060` → FreeSWITCH o AS `vas/smsc`.
- Nuevo AS `vas/smsc` (Python/Flask + cola redis + BD `sms_store`) o
  `mod_sms` si se prefiere FreeSWITCH como terminal SMS.
- Stub **SMPP** (ESME) para integrar el SMSC del operador en la propuesta.

**Definición de hecho:**
- UE1→UE2 con DLR `delivered` y mensaje visible en BD y UI.
- E2E: +3 checks (envío, DLR, persistencia).

---

## 8. Feature 07 — FDA (First Delivery Attempt) [RFP F2]

**Objetivo:** garantizar la entrega: si el destinatario está **desregistrado**,
el mensaje se encola y se entrega en su **primer intento** al registrarse.

**Comportamiento esperado:**
- SMSC consulta estado del destinatario (registrado o no).
- Si no está registrado → mensaje a cola persistente (redis/MySQL) con vencimiento.
- El S-CSCF avisa al SMSC en el `REGISTER` del destinatario → el SMSC realiza el
  **primer intento de entrega** (FDA) inmediato.

**Cambios en la maqueta:**
- `vas/smsc/deliver.py`: planificación/cola (redis) + reintentos limitados.
- Hook en S-CSCF (`REGISTER` → notifica al SMSC vía HTTP/redis) o consulta
  periódica (usrloc del S-CSCF vía api_htable o `sql_pv`).
- BD: estado `FDE` (first delivery event) en `sms_dlr`.

**Definición de hecho:**
- UE1 envía a UE2 (desregistrado); se registra UE2 → mensaje entregado en el
  primer intento; DLR `delivered`.
- E2E: check "FDA: entrega diferida ejecutada".

---

## 9. Feature 08 — SMS Firewall [RFP F3]

**Objetivo:** control MO/MT anti-fraude y anti-spam interpuesto en la cadena del SMSC.

**Comportamiento esperado:**
- Toda trama MO (del UE) y MT (al UE) pasa por la política: blacklist/whitelist,
  regex de contenido, rate-limit por emisor, scoring.
- Rechazo/reescritura antes de la persistencia/entrega; evento auditado en BD.

**Cambios en la maqueta:**
- Nuevo `vas/smsfw` (`policy.py`) interpuesto entre SMSC y entrega (dentro de la
  misma cadena `vas/smsc`).
- BD: `sms_policy`, `sms_log`.
- UI: sección de configuración de reglas (alta/edición de filtros).

**Definición de hecho:**
- Demo: un mensaje con contenido prohibido se bloquea (log análisis + DLR no
  entregado); un rate-limit por número salta tras N envíos.
- E2E: check "SMSFW bloquea trama de prueba".

---

## 10. Feature 09 — USSD Gateway (emulación IMS) [RFP F6]

**Objetivo:** exponer servicios tipo USSD (`*123*NN#`) sobre SIP, reutilizando
el motor de menú del IVR, con stub de integración real.

**Comportamiento esperado:**
- El UE envía el string USSD vía `MESSAGE` (o INVITE) → iFC → **AS USSD**.
- Sesión por etapas (USSD es interactivo): menú → acción → resultado, con
  persistencia de sesión (redis).
- Contenidos demo: saldo simulado, recarga, opt-in.

**Cambios en la maqueta:**
- `vas/ussd` (`session.py`, `menu.py`, `flows.yaml`) — reutiliza el SCE/FEAT-10.
- iFC con patrón `*123*N` (`Priority` 70).
- `map_stub.py` para la interfaz MAP/SIGTRAN del operador (solo propuesta).

**Definición de hecho:**
- Sesión USSD completa `*123*…#` con menú y acción, en E2E.
- E2E: check "sesión USSD completada".

---

## 11. Feature 10 — SCE (Service Creation Environment) [RFP F8]

**Objetivo:** crear y desplegar servicios sin tocar el Core NI FreeSWITCH:
motor + editor + despliegue de flujos.

**Comportamiento esperado:**
- Un operador define un flujo de voz/SMS/USSD (JSON/Lua) desde la UI.
- El SCE lo valida y lo despliega al AS correspondiente **sin reinicio**.
- Webhooks para lógica externa (consultas HTTP durante el flujo).

**Cambios en la maqueta:**
- Motor: `mod_lua`/`mod_httapi` (cargados) + repositorio de flujos en BD/volumen.
- `vas/sce` (Python): editor web, API de deploy, validación de esquema.
- Plantillas por país (CL/UY/CO/EC) y catálogo de servicios en `vas/templates/`.
- UI: pestaña **SCE** (listar/crear/desplegar flujos).

**Definición de hecho:**
- Crear, desplegar y ejecutar un flujo IVR nuevo desde la SCE **en el mismo día**.
- E2E: check "flujo desplegado vía API se ejecuta".

---

## 12. Feature 11 — Cloud-native / multi-país / 5G-ready [RFP F12]

**Objetivo:** a partir del stack contenerizado actual, llevar la maqueta a
entorno de operador: por país, escalable y observable.

**Cambios en la maqueta:**
- **Multi-país:** parametrización por instancia (`MCC/MNC`, dominio, plan de
  numeración, tarifas) — la maqueta ya parametriza MCC/MNC en `.env`.
- **Cloud-native:** helm charts de los 14 servicios + CI/CD; réplicas
  escalables de S-CSCF/SMSC/IVR detrás de un SLB; redis cluster.
- **Observabilidad:** Prometheus + Grafana + Loki (métricas de los nodos y AS).
- **5G-ready:** separación de planos, soporte SBA/NEF (camino documentado),
  opcional IMS Data Channel.

**Definición de hecho:**
- Segunda instancia (país) levantada solo con valores en el `values`/`.env`.
- Healthcheck + autoscaling de un AS; dashboards de monitoreo.

---

## 13. Transversales (requisitos comunes)

| Transversal | Requisito | Dónde |
|---|---|---|
| T-1 | Tránsito de `MESSAGE` en P/S-CSCF | `pcscf/kamailio_pcscf.cfg`, `scscf/kamailio_scscf.cfg` |
| T-2 | iFC por método/sesión (INVITE, MESSAGE, REGISTER-notify, terminating) | `pyhss/maqueta_ifc.xml` (Priorities 30/40/50/60/70) |
| T-3 | Esquema `vas` (ivr, cdr, sms_store, sms_dlr, sms_policy, ussd_session, flows) | `mims3_mysql` (init) |
| T-4 | Colas y estados con redis | `mims3_redis` (ya en la maqueta) |
| T-5 | API común de CDR/aviso (`vas/ocs`) | `vas/ocs` |
| T-6 | Ampliación E2E: de 15 a ~22 checks | `maqueta-ims-3/scripts/test_maqueta.sh` |
| T-7 | UI: pestañas IVR, Reportes, Monitoreo, SCE, SMS | `interfaz/app.py` + frontend |

---

## 14. Roadmap sugerido

| Fase | Features | Entregable / criterio de salida |
|---|---|---|
| **Fase 0 (hoy)** | Base validada | E2E 15/15, AKA 200 OK, sonda + parche PyHSS ordenados en git |
| **Fase 1 — MVP voz** | FEAT-01, FEAT-02, FEAT-03, FEAT-04, FEAT-05 | Demo: IVR con menú → VMS + MWI → MCA → CDR en UI; E2E ~20 |
| **Fase 2 — Mensajería** | FEAT-06, FEAT-07, FEAT-08 | UE→SMSC→UE con DLR, FDA diferida, un filtro SMSFW; E2E +3 |
| **Fase 3 — USSD + SCE** | FEAT-09, FEAT-10 | Sesión USSD y flujo creado/desplegado desde la UI |
| **Fase 4 — Operador** | FEAT-11 (+T-7) | Instancia por país, Helm, observabilidad, L3/runbooks |

**Orden de dependencia clave:** FEAT-03 y FEAT-07 necesitan a FEAT-06 (SMSC) para
la entrega SMS; FEAT-05 necesita a FEAT-04 (CDR); FEAT-09 y FEAT-01 comparten el
motor de menú del SCE (FEAT-10).

---

## 15. Contrato de no-regresión (aplicar en cada feature)

1. `bash scripts/test_maqueta.sh` → **20/20** sobre la versión actual (15 base +
   FEAT-01/FEAT-01b); al añadir features, el contador asciende (no baja).
2. Si se toca PyHSS/S-CSCF: re-ejecutar la sonda AKA
   (`ue_aka_probe.py` → 200 OK).
3. No se modifica la red `172.32.0.0/24` ni los puertos Cx sin actualizar
   `.env` y el README.
4. Cada AS nuevo se adhiere al patrón **iFC → asfront → servicio**, sin cambiar
   el Core.
5. Cada feature entrega: cambio de código, esquema BD (si aplica), check E2E y
   fila en este documento (estado = En desarrollo / Listo).

---

## 16. Referencias

- Trazabilidad: `results/cruce_RFP_maqueta_FreeSWITCH.md`
- Plan de trabajo/RFP: `results/plan_trabajo_uVAS_2026.md`
- Estado 3GPP: `results/diagnostico_cumplimiento_3gpp.md`
- Maqueta: `maqueta-ims-3/` (scripts de verificación en `maqueta-ims-3/scripts/`)