# hacom-ivr — Maqueta Core IMS (3GPP) + uVAS sobre FreeSWITCH

Repositorio del proyecto **IVR / VAS sobre IMS** para la respuesta al
**Request for Proposal uVAS 2026** de Millicom (CL/UY/CO/EC).
Incluye la **maqueta-ims-3** (la maqueta de FreeSWITCH), su documentación de
análisis, el diagnóstico de cumplimiento 3GPP y la trazabilidad RFP ↔ maqueta.

> Este README está pensado para que **otro agente de IA (o persona)** pueda
> levantar el proyecto, entender su propósito y ejecutar los pasos de validación
> sin conocimiento previo del codebase.

---

## 1. Propósito del proyecto

1. **Construir y validar una maqueta de Core IMS 3GPP** (SS7-lite, sin hardware)
   sobre Docker: Kamailio (P/I/S-CSCF) + PyHSS (Cx) + RTPEngine, con un
   **Application Server (AS) de voz basado en FreeSWITCH**.
2. **Demostrar conformidad 3GPP** frente al diagnóstico de incumplimientos
   (`results/diagnostico_cumplimiento_3gpp.md`): autenticación **Digest-AKAv1-MD5**
   de extremo a extremo, identidades IMPU/IMPI formales, cabeceras P-Header,
   negociación de seguridad Gm a nivel SIP.
3. **Sustentar la propuesta comercial al RFP**: demostrar que una plataforma uVAS
   (IVR, VMS, MCA, SMSC/FDA/SMSFW, USSD, SCE, charging, reporting/monitoring)
   puede cumplirse sobre un patrón único de **servicios VAS enrutados por iFC
   hacia FreeSWITCH** (ver `results/cruce_RFP_maqueta_FreeSWITCH.md`).

**Arquitectura (maqueta-ims-3):**

```
 UE1/UE2 (pjsua)             Core IMS (Docker, red 172.32.0.0/24)
 ──────────────────          ──────────────────────────────────────────────
 sip:MSISDN@dominio  ─Gm─>  P-CSCF 172.32.0.8:5060   (RTPEngine ancla medios)
       │                    I-CSCF 172.32.0.6:4060   (UAR/UAA → S-CSCF)
       │                    S-CSCF 172.32.0.7:6060   (MAR/MAA + SAR/SAA + iFC)
       │                    PyHSS  172.32.0.13:3868  (Cx; HSS+Diam + API+diam)
       │ Cx: UAR/MAR/SAR + iFC (maqueta_ifc.xml)
       ▼
 AS Frontera (Kamailio `asfront`, 172.32.0.16:5060) — interworking **ISC → SIP plano**
       │  iFC#1 (INVITE originado) → 0100002 / 0100003
       ▼
 FreeSWITCH (AS aplicación, 172.32.0.15:5060) — dialplan `public`
   • 0100002 → IVR (playback ivr_bienvenida.wav)
   • 0100003 → VMS (graba msg_*.wav en vms/0100003/INBOX)

 Interfaces auxiliares:
   mims3_ui      — panel de operación  http://localhost:8090
   mims3_softphone — UEs pjsua (registro + llamadas deterministas)
```

**14 contenedores:** `dns mysql redis pyhss_api pyhss_hss pyhss_diameter icscf
scscf pcscf rtpengine asfront freeswitch softphone ui`.

---

## 2. Contenido del repositorio

| Ruta | Contenido |
|---|---|
| `README.md` | Este documento. |
| `maqueta-ims-3/` | **La maqueta entregable** (todo el código y configuración). |
| `maqueta-ims-3/docker-compose.yml` + `.env` | Orquestación y parámetros (IPs, dominio, claves de test). |
| `maqueta-ims-3/{dns,mysql,pyhss,icscf,scscf,pcscf,asfront,freeswitch,rtpengine,softphone,interfaz}/` | Configuración de cada servicio. |
| `maqueta-ims-3/scripts/` | `test_maqueta.sh` (E2E 22/22), `capture_iteration.sh` (E2E bajo captura + verificación 3GPP), `check_3gpp.py` (27 reglas, AKA/ESP verificados), `provision_hss.sh`, `ue_aka_probe.py` (AKA), `bench_maqueta.sh`. |
| `maqueta-ims-3/softphone/` | UE IMS: pjsua parcheado (`ims_ext.c`: IMS-AKA + sec-agree), `ims-ipsec.sh` (SA ESP), `scripts/ue.sh` (lanzador del UE). |
| `maqueta-ims-3/pyhss/diameter.py` | Parche persistente de PyHSS (UAR/MAR por MSISDN); montado `:ro` en hss/diameter. |
| `doc/` | **RFP original**: `20260817 uVAS RFP 2026.md`. |
| `results/` | Análisis y evidencia: diagnóstico 3GPP, cruce RFP↔FreeSWITCH, comparativa de maquetas, plan de trabajo, manuales y guiones. |

> Las maquetas anteriores (`maqueta-ims`, `maqueta-ims-2`) NO se versionan;
> su análisis comparativo está en `results/argumentacion_AS_kamailio_vs_freeswitch.md`.

---

## 3. Requisitos del entorno

- **Docker** 20.10+ con plugin **docker compose** (v2).
- ~5 GB de disco libres (construcción de imágenes propia: dns, mysql, freeswitch…).
- Red interna `172.32.0.0/24` (¡no debe colisionar con la red del host/docker!).
- CPU x86_64 (binarios precompilados de FreeSWITCH/Kamailio/RTPEngine).
- `git` y acceso SSH a este repositorio (`git@github.com:jhordyabonia/hacom-ivr.git`).
- **Puertos libres** (mapeados a host): `8090` (UI), `4443` (no requerido por mims3), etc.

> ⚠️ El atajo `docker compose up` construye o descarga imágenes; la primera vez
> toma varios minutos. IPsec ESP en Gm usa el `xfrm` del kernel del host: el
> P-CSCF corre `privileged` y el softphone con `NET_ADMIN`/`NET_RAW` (módulos
> `esp4`/`xfrm_user`, se cargan solos en kernels Linux estándar). La red
> `mims3_network` usa **MTU 9000** (solo afecta al bridge del laboratorio).

---

## 4. Levantar el proyecto — paso a paso

### Paso 1 — Clonar y comprobar Docker

```bash
git clone git@github.com:jhordyabonia/hacom-ivr.git
cd hacom-ivr/maqueta-ims-3
docker --version && docker compose version
```

### Paso 2 — (Opcional) revisar parámetros

`.env` define: dominio `ims.mnc001.mcc001.3gppnetwork.org`, IPs fijas de la red
`172.32.0.0/24`, y suscriptores UE1/UE2 (IMSI, MSISDN, KI digest).
No contiene secretos reales (es material de laboratorio).

### Paso 3 — Arrancar toda la maqueta

```bash
cd maqueta-ims-3
docker compose up --build -d
```

Esperar hasta que los 14 contenedores estén **Up** y *healthy* si definidos:

```bash
docker compose ps
```
Los nombres: `mims3_dns … mims3_ui` (ver §1). El `softphone` arranca solo como
agente de prueba (no bloquea). Comprobar que ya escuchan los listeners SIP:
`scscf:6060`, `icscf:4060`, `pcscf:5060`, `asfront:5060`, `freeswitch:5060`.

### Paso 4 — Provisionar suscriptores en PyHSS

El HSS necesita UE1/UE2 (au + subscriber + ims_subscriber + iFC). La interfaz
expone el endpoint; hay script idempotente:

```bash
bash scripts/provision_hss.sh            # usa http://127.0.0.1:8090 (UI)
```

Verificación (lista filas de `ims_subscriber`):
```bash
docker exec mims3_pyhss_hss sh -c "python3 -c \"import sqlite3; c=sqlite3.connect('/var/lib/pyhss/hss.db'); [print(r) for r in c.execute('SELECT imsi,msisdn,ifc_path,scscf FROM ims_subscriber')]\""
```

> El **parche de PyHSS** (`UAR/MAR con fallback a MSISDN para identidad pública`)
> ya viene montado `:ro` en los servicios `pyhss_hss`/`pyhss_diameter` desde el
> repo (`pyhss/diameter.py`) — sobrevive a `compose up` sin pasos extra.

### Paso 5 — Verificación funcional E2E (15 checks)

```bash
bash scripts/test_maqueta.sh
# Esperado al final:
#   PASS: 15   FAIL: 0
#   ESTADO: OK — la maqueta supera la prueba
```

Valida: contenedores arriba → DNS (dominio → P-CSCF) → listeners SIP →
registro IMS UE1/UE2 (401 → 200 OK + Service-Route) → llamada UE1→AS iFC
(CONFIRMED + IVR `ivr_bienvenida.wav` en FreeSWITCH + log `asfront` re-origina +
`RTPEngine engaged`) → VMS graba mensaje en buzón `0100003`.

### Paso 6 — Autenticación IMS AKA (Digest-AKAv1-MD5) e IPsec

Desde FEAT-02 el propio E2E registra los UEs con **IMS-AKA + IPsec ESP** (pjsua
parcheado, `softphone/scripts/ue.sh`). Para verificar las capturas:

```bash
bash scripts/capture_iteration.sh ../entregables-feat-02/03_iteraciones/iter-NN
# -> test_maqueta.log (22/22), maqueta_ims_sip_only.pcap, check_3gpp.md (27/27)
```

La **sonda** independiente sigue disponible (AKA sin IPsec):

```bash
# Copiar la sonda y ejecutarla (Dockerfile no la monta; se copia en cada compose up)
docker cp scripts/ue_aka_probe.py mims3_pyhss_hss:/tmp/
docker exec mims3_pyhss_hss python3 /tmp/ue_aka_probe.py
# Esperado:
#   WWW-Authenticate: Digest …, algorithm=AKAv1-MD5, …
#   RESULTADO: AUTHENTICACION AKAv1-MD5 COMPLETADA (200 OK)
```

---

## 5. Operación y manualidad

- **Interfaz de operación** (`mims3_ui`): abrir `http://localhost:8090`.
  Permite: estado de los 14 contenedores, prueba E2E (POST `/api/test`),
  registro/llamada de los UEs, provisión (`/api/config/provision`), y
  reproducción de mensajes VMS (`GET /api/vms/media`).
- **Registro manual de un UE** (desde `mims3_softphone`):
  ```bash
  docker exec mims3_softphone sh -c \
    "timeout 20 pjsua --id sip:0010100001@ims.mnc001.mcc001.3gppnetwork.org \
     --registrar sip:ims.mnc001.mcc001.3gppnetwork.org:5060 --realm ims.mnc001.mcc001.3gppnetwork.org \
     --no-tcp --null-audio --log-level 4 --username 0010100001 --password 8baf473f2f8fd09487cccbd7097c6862 \
     --local-port 5061 > /tmp/pj.log 2>&1"
  ```
  Buscar `registration success, status=200` en `/tmp/pj.log`.
- **VMS / grabaciones**: aparecen en `maqueta-ims-3/freeswitch/vms/0100003/INBOX/msg_*.wav`.

---

## 6. Cómo funciona por dentro (mapa de la maqueta)

| Servicio | Archivo clave | Rol |
|---|---|---|
| DNS | `dns/` | BIND del dominio `ims.mnc001.mcc001.3gppnetwork.org` (A → P-CSCF; SRV `_sip._udp` → icscf:4060). |
| MySQL / Redis | `mysql/`, `.env` | BD (`icscf`, …) y colas/caché. |
| PyHSS | `pyhss/{diameter.py,maqueta_ifc.xml}` | HSS: Cx UAR/UAA, MAR/MAA, SAR/SAA; **iFC#1** (INVITE originado → `sip:asfront…:5060`). Parche MSISDN en UAR/MAR. |
| I-CSCF | `icscf/` | UAR→selección S-CSCF; LIR/LIA; aviso de registro. |
| S-CSCF | `scscf/{kamailio_scscf.cfg,scscf.cfg}` | MAR/MAA (AKAv1-MD5), SAR/SAA, Service-Route, evaluación de iFC. |
| P-CSCF | `pcscf/{kamailio_pcscf.cfg,route/*}` | ANCLA de medios (RTPEngine), PANI/P-Preferred-Identity, strip ck/ik en 401, negociación `Security-Server/Verify`. |
| AS Frontera | `asfront/{asfront.cfg,kamailio_asfront.cfg}` | Interworking **ISC → SIP plano** (relay ligero; `AS-Front: re-origina a FreeSWITCH`). |
| FreeSWITCH | `freeswitch/conf/` | **AS aplicación**: dialplan `public` = IVR (`0100002`) + VMS (`0100003`); módulos para roadmap (Lua/HTTAPI/AMR/CDR…). |
| RTPEngine | `rtpengine/` | Medio de plano: reemplaza el SDP del UE por sus puertos (`RTPEngine engaged`). |
| Softphone | `softphone/` | pjsua (UE1/UE2) y herramienta de test. |
| UI | `interfaz/app.py` | Flask + Docker SDK: `http://localhost:8090`. |

---

## 7. Solución de problemas (los fallos clásicos y su causa)

| Síntoma | Causa | Solución |
|---|---|---|
| `401` se repite y nunca `200 OK` | PyHSS sin suscriptores o iFC incompleta | Ejecutar `scripts/provision_hss.sh`; comprobar `ims_subscriber` (§4-paso 4). |
| `403 Forbidden - HSS User Unknown` (I-CSCF) | UAR con identidad pública (MSISDN) sin parche | Confirmar que `pyhss/diameter.py` (fallback MSISDN) está montado y el HSS reiniciado. |
| `500 Error forwarding to SCSCF` / `bad_uri` | Pool S-CSCF mal configurado en I-CSCF | Ver options: pool como URI completa `sip:scscf.<dominio>:6060`, `use_dns_cache=off`. |
| pjsua `403 - You must register first` | La llamada se ordena antes de completar el REGISTER | Ordenar la llamada tras `200/REGISTER` (patrón del pipe en `test_maqueta.sh` paso 5). |
| `PJSIP_ENOCREDENTIAL (no suitable credential)` | Falta `--realm` | Siempre incluir `--realm <dominio>`. |
| VMS: `Recording was 0 seconds long` | pjsua con `--null-audio` no emite RTP | Generar audio real (tono 45 s) e inyectarlo (`test_maqueta.sh` paso 6). |
| `RTPEngine engaged` ausente | El INVITE bypasa el P-CSCF | Forzar `--outbound=sip:172.32.0.8:5060;lr`. |
| Tras recrear contenedores, la sonda AKA no existe | `ue_aka_probe.py` no está montado | Re-ejecutar `docker cp scripts/ue_aka_probe.py mims3_pyhss_hss:/tmp/`. |
| IPsec: `delete_unused_sa(): ... netlink` en el P-CSCF | Limpieza de SA no usadas de `ims_ipsec_pcscf` | Ruido sin efecto funcional; las SA ESP reales se crean (`ip xfrm state` en `mims3_pcscf`). |
| UE: `sec-agree: fallo instalando SA` | SA residuales en el softphone | `docker exec mims3_softphone sh -c "ip xfrm state flush; ip xfrm policy flush"`. |
| Softphone comercial (Zoiper/Linphone) no registra (403) | Solo se admite IMS-AKA | Perfil Digest no-3GPP opcional: `WITH_NON3GPP_DIGEST` en `scscf/scscf.cfg` (solo DEV). |
| Red `172.32.0.0/24` colisiona con otra | .env | Cambiar `TEST_NETWORK` y las IPs de `.env` (ocuparse de que DNS/compose coincidan). |

---

## 8. Estado de conformidad 3GPP (resumen)

Ver detalle y evidencia en `entregables-feat-02/01_verificacion_3gpp/INFORME_CUMPLIMIENTO_3GPP.md` (y el histórico en `results/diagnostico_cumplimiento_3gpp.md`).

| Elemento | Estado |
|---|---|
| Autenticación **Digest-AKAv1-MD5** E2E (Cx MAR/MAA + Milenage) | ✅ (`ue_aka_probe.py` → 200 OK) |
| `ck`/`ik` no llegan al UE en la 401 | ✅ (strip en P-CSCF) |
| sec-agree `Security-Client/Server/Verify` + **IPsec ESP real** en Gm (TS 33.203) | ✅ (ICV verificado en la captura) |
| IMPU formal `sip:<MSISDN>@dominio`, IMPI en `Authorization` | ✅ |
| UAR/MAR con identidad pública (MSISDN) en PyHSS | ✅ (parche montado) |
| INVITE con `P-Access-Network-Info` / `P-Preferred-Identity` / MMTEL | ✅ (las aporta el UE; P-CSCF asierta PAI) |
| `Contact` con `+g.3gpp.icsi-ref`/`+g.3gpp.smsip` | ✅ |
| Codecs AMR/AMR-WB (TS 26.114) | ✅ (oferta del UE con AMR-WB/AMR + telephone-event) |
| MWI SUBSCRIBE/NOTIFY (TS 24.606) y desvío a buzón de no registrado | ✅ (FEAT-02) |

**E2E:** `bash scripts/test_maqueta.sh` → **PASS 22 / FAIL 0** · verificación de captura `check_3gpp.py` → **27/27** (ver `entregables-feat-02/`).

---

## 9. RFP uVAS 2026 — trazabilidad (resumen)

Cruce completo y por-funcionalidad en `results/cruce_RFP_maqueta_FreeSWITCH.md`.

| Funcionalidad RFP | Estado en la maqueta | Cómo |
|---|---|---|
| IVR | ✅ Implementado | dialplan `public`, playback; roadmap: menú DTMF (`mod_dptools`/Lua/HTTAPI). |
| VMS | ✅ Implementado | `record` + `mod_voicemail` cargado; bandejas por MSISDN. |
| SCE | 🟡 Nativo | `mod_lua`, `mod_httapi`, `mod_xml_curl` → flujos sin redeploy. |
| MCA | 🟡 Nativo | CDR (`mod_cdr_csv`) + ESL para no-answer; aviso vía SMS con `mod_sms`. |
| Charging / Reporting / Monitoring | 🟡 Ampliable | CDR/MySQL + `mims_ui` (`:8090`) + ESL. |
| SMSC / FDA / SMSFW / USSD | 🟠 AS mensajería | Extensión del patrón **iFC** (ruta `MESSAGE`) + AS SMS sobre la misma maqueta; FDA con cola redis/MySQL. |
| Cloud-native / 5G-ready | 🟡 Base | Contenedores parametrizados por país (MCC/MNC); roadmap Helm/K8s. |

**Plan de etapas** de la respuesta al RFP: `results/plan_trabajo_uVAS_2026.md`.

---

## 10. Reproducción de evidencias

```bash
# E2E completo
bash maqueta-ims-3/scripts/test_maqueta.sh                       # 22/22

# Autenticación AKA (Digest-AKAv1-MD5)
docker cp maqueta-ims-3/scripts/ue_aka_probe.py mims3_pyhss_hss:/tmp/
docker exec mims3_pyhss_hss python3 /tmp/ue_aka_probe.py          # → 200 OK

# Benchmark (opcional; corre E2E + latencias + CPU/MEM)
bash maqueta-ims-3/scripts/bench_maqueta.sh mims3
```

---

## 11. Notas de mantenimiento para agentes posteriores

- **No añadir comentarios ni reempaquetar configs del Core** sin conocer el
  historial de fixes (lista en §7 y en `results/paso_a_paso.md`).
- **Persistencia del HSS**: el único archivo que sobrevive entre `compose up` es
  el montaje `:ro` de `pyhss/diameter.py`; el resto de cambios (p.ej. reinicios
  de CSCF) es declarativo en `docker-compose.yml`.
- **El E2E es el contrato**: cualquier cambio en PCSCF/S-CSCF/PyHSS debe cerrar
  con `test_maqueta.sh` → 22/22 (y `capture_iteration.sh` → 27/27) y, si toca autenticación, repetir la sonda AKA.
- La rama principal es el estado "demo-ready"; los cambios se prueban primero
  contra la maqueta local antes de commitear.

---

## 12. Referencias dentro del repositorio

- RFP original: `doc/20260817 uVAS RFP 2026.md`
- Diagnóstico 3GPP: `results/diagnostico_cumplimiento_3gpp.md`
- Cruce RFP↔FreeSWITCH: `results/cruce_RFP_maqueta_FreeSWITCH.md`
- Comparativa de maquetas y recomendación: `results/argumentacion_AS_kamailio_vs_freeswitch.md`
- Plan de trabajo/RFP: `results/plan_trabajo_uVAS_2026.md`
- Despliegue detallado y pitfalls: `results/paso_a_paso.md`
- Interfaz: `results/manual_interfaz.md`
- Guiones de demo: `results/guion_meet.md`, `results/guion_meet-2.md`