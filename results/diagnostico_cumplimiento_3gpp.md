# Diagnóstico de Cumplimiento 3GPP — maqueta-ims-3 (estado tras corrección)

Documento vivo: diagnóstico original del tráfico SIP/IMS + estado de corrección
por incumplimiento, con evidencia reproducible en la maqueta.

---

## 1. Incumplimientos Críticos (puntos de fallo) — Estado tras corrección

### 1.1 Algoritmo de autenticación (`TS 33.203`) → **CORREGIDO**

- **Problema original:** `401 Unauthorized` exigía `algorithm=MD5`.
- **Violación:** 3GPP exige **AKA-v1-MD5 / AKA-v2-SHA-256** con vector USIM/ISIM.
- **Corrección aplicada:**
  - `scscf/kamailio_scscf.cfg` (ruta REGISTER): si la petición trae `Security-Client`
    se autentica con `AKAv1-MD5`; si no (clientes no-IMS) cae a `MD5` como fallback.
  - `scscf/scscf.cfg`: activado `#!define REG_AUTH_DEFAULT_ALG "AKAv1-MD5"` y
    desactivado `HSS-Selected`.
  - `interfaz/app.py` (provisión): el vector `auc` ahora se crea con `opc` y
    `sqn` correctos (antes `opc=0000…` / `sqn=NULL` hacían fallar la generación
    MAA en PyHSS → `504`). Re-provisión OK (auc_id 6/8, opc `61f0…`, sqn 7091).
  - PyHSS `diameter.py` **UAR y MAR**: si el `username` del Cx no es un IMSI de
    15 dígitos se mapea por **MSISDN** (identidad pública) → el `REGISTER` con
    IMPU normalizado ya no falla con `403 HSS User Unknown`.
- **Evidencia (sonda):**
  `scripts/ue_aka_probe.py` completa **Digest-AKAv1-MD5 extremo a extremo**:

  ```
  WWW-Authenticate: Digest realm="…", nonce="RAND||AUTN…", algorithm=AKAv1-MD5, ck=…, ik=…, qop="auth"
  ...
  RESULTADO: AUTHENTICACIÓN AKAv1-MD5 COMPLETADA (200 OK)
  ```
  - El reto se calcula con `Milenage.f2(K, RAND, OPc)` (RES/XRES);
    `ims_auth` confirma `UE said: … and we expect …` y emite `Authentication-Info`.
  - **Limitación clientes PJSUA:** pjsua (2.14, build sin IPsec) computa su
    respuesta con `password=KI` en lugar de `XRES` → no puede completar AKA
    (403 Authentication Failed). La vía estándar corregida para la demo es la
    sonda; el E2E 15/15 sigue en MD5 (fallback).

### 1.2 Seguridad de la interfaz Gm / IPSec (`TS 33.203`) → **PARCIAL (nivel SIP)**

- **Problema original:** ausencia de `Security-Client` / `Security-Server` / `Security-Verify`.
- **Estado:** la negociación **SIP-level** ahora ocurre:
  - UE envía `Security-Client: ipsec-3gpp; alg=hmac-sha-1-96; spi…; port…`
    (sonda y pjsua `--use-ims`).
  - P-CSCF responde en el **401** con `Security-Server` y confirma con
    `Security-Verify` en el **200 OK** (RFC 3329):
    mecanismo añadido en `pcscf/route/register.cfg` (onreply `REGISTER_reply`).
  - **Ck/ik ya no se filtran al UE:** el `strip` que estaba dentro de
    `#!ifdef WITH_IPSEC` se movió fuera (TS 33.203): la 401 hacia el UE llega
    `algorithm=AKAv1-MD5, qop="auth"` **sin** `ck=`/`ik=`.
  - **Colateral corregido:** en la 401 ya no se filtran las claves del túnel.
- **Pendiente (documentado, no abordable en el contenedor):** el túnel **IPsec ESP**
  real no se materializa por falta de privilegios de kernel (NET_ADMIN) en Docker.
  La negociación Gm queda soportada a nivel de señalización, no de plano de datos.

### 1.3 Formato de `Contact` y parámetros IMS (`TS 24.229`) → **CORREGIDO**

- **Problema original:** `Contact` con IP directa `…:5061;ob`, sin características.
- **Estado:** la sonda y pjsua `--use-ims` envían
  `Contact: <sip:…>;+g.3gpp.icsi-ref="urn:urn-7:3gpp-service.ims.icsi.mmtel";+g.3gpp.smsip`.
  P-CSCF las procesa y guarda el contacto con las feature-tags.

### 1.4 Identidades SIP en `REGISTER` (`TS 23.003` / `TS 24.229`) → **CORREGIDO**

- **Problema original:** `From`/`To` usaban el IMSI como URI (`sip:001011234567890@…`).
- **Estado:** el registro ahora usa el **IMPU normalizado**
  `sip:0010100001@ims.mnc001.mcc001.3gppnetwork.org` (MSISDN) en `From`/`To`
  (y `tel:0010100001` en HSS), mientras que la identidad privada
  (IMPI = IMSI@dominio) se declara en el `Authorization`.
  `scripts/test_maqueta.sh` migró a `--id sip:$MSISDN@…` + `--username $MSISDN`.
- **Caveat pjsua (documentado):** pjsua, al no enviar la identidad privada
  (IMPI) en el primer REGISTER, obliga a que reto y respuesta compartan la
  clave → en el camino MD5 el `--username` (identidad usada en digest) es el
  MSISDN. La vía AKA conforme (IMPI real en digest + pre-auth) la demuestra
  `ue_aka_probe.py`.

---

## 2. Desviaciones en el establecimiento de llamada (`INVITE`)

### 2.1 Cabeceras P-Header (`TS 24.229`) → **CORREGIDO**

- **Problema original:** INVITE saliente sin `P-Preferred-Identity` ni `P-Access-Network-Info`.
- **Corrección aplicada (P-CSCF, `pcscf/kamailio_pcscf.cfg` ruta MO):** si el UE
  no las envía, el P-CSCF inserta:
  - `P-Access-Network-Info: 3GPP-E-UTRAN-FDD; utran-cell-id-3gpp=0020100000f101`
  - `P-Preferred-Identity: <sip:$fu@dominio>`
  También se inserta PANI en el `REGISTER` (`pcscf/route/register.cfg`).

### 2.2 Parámetros SDP / codecs (`TS 26.114`) → **PARCIAL / limitación de cliente**

- **Problema original:** SDP sin AMR/AMR-WB.
- **Estado:** la red **puede** servir AMR:
  - FreeSWITCH incluye y carga `mod_amr.so` / `mod_amrwb.so`
    (`/usr/lib/freeswitch/mod/mod_amr*.so`, autoload en `modules.conf.xml`).
  - RTPEngine/FS permiten transcodificar a/de AMR.
- **Limitación:** el softphone pjsua de la maqueta se compiló **sin códec AMR**
  (solo iLBC/GSM/G722) → el SDP de los tests E2E continúa sin AMR por parte del
  UE. Se requiere un cliente MTSI (p.ej. Linphone/UCRaw con AMR) para probar
  AMR extremo a extremo.

---

## Resumen de Evaluación (actualizado)

| Elemento | Estado 3GPP original | Estado tras corrección | Evidencia |
| :--- | :--- | :--- | :--- |
| Flujo Registrar (P-I-S CSCF) | Cumple | Cumple | test 15/15 |
| Cabeceras `Path` / `Service-Route` | Cumple | Cumple | test 15/15 |
| Autenticación AKA (AKAv1-MD5) | No Cumple | **Cumple** | sonda `ue_aka_probe.py` → 200 OK |
| Algoritmo 401 por defecto | MD5 | **AKAv1-MD5** (MD5 solo fallback) | 401 capturada |
| Cabeceras `Security-Client/Server/Verify` | No Cumple | Cumple (nivel SIP; sin túnel ESP) | 401 Security-Server + 200 Security-Verify |
| `ck`/`ik` no llegan al UE | N/A (filtraban) | **Cumple** (strip en P-CSCF) | 401 hacia el UE |
| `Contact` + `+g.3gpp.icsi-ref/smsip` | No Cumple | **Cumple** | REGISTER capturado |
| IMPU formal (sin IMSI en URI) | No Cumple | **Cumple** | `--id sip:$MSISDN@…` |
| UAR/MAR con identidad pública (MSISDN) | N/A (403) | **Cumple** (fallback en PyHSS) | logs UAR/MAR |
| INVITE `P-Preferred-Identity` / `P-Access-Network-Info` | No Cumple | **Cumple** (P-CSCF inserta) | `kamailio_pcscf.cfg` MO |
| Codecs AMR/AMR-WB (MTSI) | No Cumple | Parcial (red sí, cliente no) | `mod_amr*` en FS; pjsua sin AMR |

**Resultado E2E:** `scripts/test_maqueta.sh` → **PASS 15 / FAIL 0**

---

## Recomendaciones de Corrección — Seguimiento

1. ~~Configurar AKA / Digest-AKAv1-MD5~~ → Hecho (S-CSCF + PyHSS + sonda).
2. ~~Negociación IPSec Gm~~ → Nivel SIP hecho; túnel ESP pendiente (requiere
   kernel con IPsec / Pod con NET_ADMIN). Revisar `ck`/`ik` cuando se active el
   tunel (el strip ya está fuera de WITH_IPSEC).
3. ~~AMR / AMR-WB en SDP~~ → Parcial: la red lo soporta (`mod_amr`, `mod_amrwb`);
   falta un cliente MTSI con AMR para el E2E real.
4. ~~`P-Access-Network-Info`/`P-Preferred-Identity`~~ → Hecho (P-CSCF inserta
   en REGISTER e INVITE).

## Reproducción de evidencia

```bash
# 1) Sonda AKA (completa Digest-AKAv1-MD5 contra la red):
docker cp maqueta-ims-3/scripts/ue_aka_probe.py mims3_pyhss_hss:/tmp/
docker exec mims3_pyhss_hss python3 /tmp/ue_aka_probe.py
# → "RESULTADO: AUTHENTICACIÓN AKAv1-MD5 COMPLETADA (200 OK)"

# 2) E2E completo de la maqueta:
bash maqueta-ims-3/scripts/test_maqueta.sh
# → PASS: 15   FAIL: 0   ESTADO: OK
```

## Notas de persistencia

- El parche de PyHSS (`diameter.py`, UAR/MAR por MSISDN) se persiste en el repo
  en `maqueta-ims-3/pyhss/diameter.py` y se monta `:ro` en los servicios
  `pyhss_hss` y `pyhss_diameter` (docker-compose.yml).
- `ue_aka_probe.py` vive en `maqueta-ims-3/scripts/`; debe copiarse al contenedor
  en cada `compose up` (no está montado).