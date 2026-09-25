# Maqueta IMS — Comparativa técnica y recomendación

> Documento de soporte técnico — proyecto IVR/VAS
> Resultados medidos en este equipo (Docker, núcleo Kamailio 6.2.0-dev1 + PyHSS + RTPEngine).
> Los datos numéricos provienen de `results/comparativa_maquetas.csv` (corridas por maqueta, ejecutadas de forma **secuencial** para no falsear el uso de CPU).

---

## 1. Resumen ejecutivo

Se construyeron y probaron **tres** maquetas del **Core IMS sobre Kamailio + PyHSS + RTPEngine**, con la única diferencia en el **Application Server (AS)**:

| | **maqueta-ims** | **maqueta-ims-2** | **maqueta-ims-3** |
|---|---|---|---|
| Interconexión AS | S-CSCF → **Asterisk directo** (sin B2BUA) | S-CSCF → **FreeSWITCH (B2BUA Frontera)** → Asterisk (gateway) | S-CSCF → **AS Frontera Kamailio (ISC)** → **FreeSWITCH (AS aplicación)** |
| iFC ServerName | `sip:asterisk.ims...:5060` | `sip:freeswitch.ims...:5060` | `sip:asfront.ims...:5060` |
| Rol medio | Asterisk = AS completo | FreeSWITCH = control de sesión; Asterisk = IVR/VMS | **FreeSWITCH = IVR/VMS nativo (sin Asterisk)**; Frontera = interworking ISC → SIP plano |
| Nº contenedores | 13 | 14 (FreeSWITCH adicional) | 14 (asfront + freeswitch) |
| Prueba funcional | 13/13 PASS | 14/14 PASS | **15/15 PASS** |
| Registro IMS (401→200) | ~122 ms | ~117 ms | ~122 ms |
| **Setup de llamada (INVITE→CONFIRMED)** | **~10 ms** | ~32 ms | **~10 ms** |
| IVR reproducido | ✅ | ✅ | ✅ |
| RTPEngine engaged | ✅ | ✅ | ✅ |
| VMS grabado | ✅ (~21 s a grabar) | ✅ (~23 s a grabar) | ✅ (~23 s a grabar) |

**Las tres maquetas son funcionales y estables.** La decisión entre ellas es estratégica, no de "pasa/falla".

---

## 2. Cómo se ejecutó la prueba

- Se apagó **completamente** la maqueta no probada (`docker compose down`), dejando solo una maqueta corriendo a la vez.
- Cada maqueta ejecutó `scripts/bench_maqueta.sh <mims|mims2|mims3>`, que corre:
  1. El test funcional oficial E2E (`test_maqueta.sh`): registro IMS de 2 UEs, llamada UE→AS con IVR, VMS y RTPEngine.
  2. Medición de **latencia de registro** (401→200 ms).
  3. Medición de **setup de llamada** (INVITE → CONFIRMED ms, desde los logs de pjsua).
  4. Muestreo de **CPU/MEM idle y bajo llamada** de scscf/pcscf/icscf/asterisk (+freeswitch en mims2; +asfront/freeswitch en mims3) vía `docker stats`.
  5. Validación del **VMS** (confirmación, grabación de mensaje y tiempo hasta grabar).
- Se repitió 2 veces por maqueta en mims/mims2 (1 en mims3); los valores entre corridas son consistentes.

---

## 3. Resultados detallados

### 3.1 Núcleo IMS (igual en las tres)

Los resuelve el Core IMS, común a todas:

- Registro IMS completo `100 → 401 (Digest MD5) → 100 → 200 OK` con Service-Route en S-CSCF. ✅
- Selección de S-CSCF en I-CSCF (UAR/UAA, LIR/LIA, MAR/MAA). ✅
- iFC#1 (`INVITE` + `SessionCase 0`) → enrutado de la sesión al AS de la maqueta. ✅
- Plano de medios anclado en **RTPEngine** (P-CSCF): `RTPEngine engaged for Application Server`. ✅
- VMS: buzoneo `0100003`; mensajes `msg*.wav` en `INBOX` (Asterisk en mims/2, FreeSWITCH `/var/lib/freeswitch/storage/vms` en mims-3). ✅

### 3.2 Diferencias medidas entre maquetas

| Métrica | maqueta-ims | maqueta-ims-2 | maqueta-ims-3 | Lectura |
|---|---|---|---|---|
| Latencia registro 401→200 | 122.5 ms | 117 ms | 122 ms | Igual en la práctica (±5 %). El B2BUA/Frontera no penaliza el registro. |
| **Setup de llamada INVITE→CONFIRMED** | **~10 ms** | ~32 ms | **~10 ms** | mims-3 es **relay puro** (sin B2BUA): la Frontera re-origina SIN re-invitar, con la misma latencia que mims. El coste B2BUA de mims-2 lo asumía FreeSWITCH al volver a sesionar con Asterisk. |
| IVR reproducido | 1 | 1 | 1 | Igual. |
| RTPEngine engaged | 1 | 1 | 1 | Igual: el ancla de medios es RTPEngine en **todas**. |
| VMS (grabado) | ✅ 21.5 s | ✅ 23 s | ✅ 23 s | Igual en mims-2/3 (recuperación + tono de grabación). |
| CPU bajo llamada — scscf | 0.07 % | 0.06 % | 0.25 % | Igual (muestreo puntual). |
| CPU bajo llamada — pcscf | 0.06–1.07 % | 0.04–0.09 % | 0.41 % | Igual (reserva de Kamailio domina). |
| CPU bajo llamada — icscf | ~1.2 % | ~0.06 % | 0.07 % | Muestreo puntual; ambos ~nulos. |
| **CPU bajo llamada — asterisk** | 0.51–3.45 % | 0.38–0.50 % | **eliminado** | En mims3 el IVR/VMS lo hace FreeSWITCH nativo. |
| **CPU bajo llamada — freeswitch** | — | 1.07–3.41 % | 1.16 % | mims-3 solo IVR/VMS nativo (sin re-invite a Asterisk) → ~1.2 %. |
| **CPU bajo llamada — AS Frontera (asfront)** | — | — | **0.04 %** | Relay Kamailio puro: coste casi nulo. |
| MEM bajo llamada — pcscf | ~1.10 GiB | ~1.09 GiB | ~1.14 GiB | **Reserva `-M 1024` de Kamailio** (memoria compartida), igual en todas. |
| MEM bajo llamada — freeswitch | — | ~50.7 MiB | ~46.5 MiB | mims-3 reduce ~4 MiB (sin leg a Asterisk). |
| MEM bajo llamada — AS Frontera (asfront) | — | — | ~14 MiB | Kamailio mínimo (relay). |
| Duración test funcional | 33 s | 53 s | 53 s | mims-3 añade checks extra (15) y el paso de tono VMS vía host. |

---

## 4. Análisis técnico de la diferencia fundamental

### 4.1 maqueta-ims: S-CSCF → Asterisk directo (sin B2BUA)

- **Ventajas**: menor latencia de setup (~10 ms), un contenedor menos, ruta de sesión simple, menos CPU agregada.
- **Limitaciones**:
  - El S-CSCF entrega el INVITE **tal cual** a Asterisk; Asteroid responde IVR como AS, pero **no hay re-originación** hacia el S-CSCF (no es B2BUA).
  - Como recoge `results/conclusiones.md`, **las llamadas UE→UE no son posibles**: el iFC#1 desvía *todo* INVITE originado al AS y éste no puede devolver la sesión al Core. Para UE→UE haría falta que el AS actuase como B2BUA (reescribir y re-originar) — justo lo que **no** es en esta variante.

### 4.2 maqueta-ims-2: FreeSWITCH como AS Frontera (B2BUA)

- **Ventajas**:
  - **FreeSWITCH es un B2BUA nativo**: recibe el INVITE del S-CSCF, controla sesión y medios, y **re-origina** hacia Asterisk vía `bridge sofia/gateway/asterisk`.
  - Estructura de **dos planos**: FreeSWITCH = plano de control de sesión (Frontera del AS), Asterisk = plano de reproducción IVR/VMS. Es el patrón 3GPP del **MRFC/TAS** típico en operadores.
  - Soporta de forma natural: llamada **UE→UE (3PCC)**, conferencia, MSRP, fork/transcodificación y servicios VAS que requieren sesión persistente.
  - Libera a Asterisk: en mims2 Asterisk queda en ~0.4 % CPU bajo llamada vs 0.5–3.5 % en mims.
- **Coste**: ~20 ms extra de setup, ~50.7 MiB de memoria y ~2.2 % CPU promedio bajo llamada, además del contenedor 14 y el docker-compose dedicado. Valores **asumibles** para una plataforma de producción.

### 4.3 maqueta-ims-3: AS Frontera Kamailio (ISC) + FreeSWITCH como AS aplicación

- **Ventajas**:
  - **Desacopla roles con el coste más bajo**: la Frontera Kamailio (`sip:asfront...:5060`, iFC del S-CSCF) hace el **interworking ISC → SIP plano** como **relay puro** (~0.04 % CPU, ~14 MiB), y FreeSWITCH pasa a ser **AS aplicación** (IVR/VMS nativo) sin Asterisk y sin re-leg a un gateway.
  - **Mejor latencia que mims-2**: setup de llamada **~10 ms** (igual a mims, el relay no añade B2BUA). El INVITE ISC se re-origina a FreeSWITCH con `$du` y la transacción la resuelve TM del propio Kamailio; nunca hay una segunda sesión B2BUA.
  - **Menos superficie**: se elimina Asterisk (337 MB de imagen) del plano de sesión; FreeSWITCH queda solo con dialplan public (playback + record).
  - **Patrón 3GPP correcto sin sobredimensionar**: la Frontera puede exporer el marcado ISC (módulo `ims_isc` disponible en la imagen) y su rol de relay es extensible (filtrar cabeceras P-Charging/P-Served-User, re-etiquetar a futuro), dejando el VAS puro a FreeSWITCH.
  - **Doble verificación en el test E2E**: además del RTPEngine engaged, se valida el log de la Frontera (`AS-Front: re-origina a FreeSWITCH`).
- **Limitaciones**:
  - La Frontera actual es un relay **sin estado de B2BUA propio**: no sirve por sí misma UE→UE ni conferencia; eso seguiría recayendo en FreeSWITCH (con tendencia B2BUA nativa si se quieren esos servicios).
  - No re-etiqueta el diálogo (sin `record_route`): es transparente; el ACK in-dialog lo resuelve TM y el retorno vía Contact/Core. Correcto para el flujo actual (A→terminating AS), a revisar si el AS pasa a actuar como *tromboning* (salidas hacia otro dominio).

### 4.4 Qué aporta cada variante al proyecto

| Necesidad | ¿Cuál la satisface mejor? |
|---|---|
| Demostración mínima IVR/VMS de un AS | mims (menos recursos) o mims-3 (sin Asterisk) |
| IVR/VMS como **plataforma de servicio** extensible (VAS) | **mims-2** (B2BUA) o **mims-3** (Frontera ISC + FreeSWITCH app) |
| Llamadas UE→UE pasando por el AS (3PCC) | **mims-2** (FreeSWITCH lo hace nativo) |
| Bajo consumo de recursos | **mims-3** (relay ~14 MiB / 0.04 %, sin Asterisk) |
| Conformidad con patrón de operador (TAS/MRFC delante de un media server) | **mims-2** y **mims-3** (ambos un AS Frontera delante de la app) |
| Separación Frontera ⇄ aplicación con menor latencia | **mims-3** (~10 ms) |
| Camino a producción con IPsec/Gm, Rx/PCRF, Ro | Todas (es trabajo del Core, no del AS) |

---

## 5. Recomendación

**Se recomienda maqueta-ims-3 (AS Frontera Kamailio ISC + FreeSWITCH como AS aplicación)** como base de la propuesta técnica:

1. **Patrón de operador con el coste correcto**: la Frontera Kamailio cumple el rol de interworking ISC delante de la aplicación (patrón TAS/MRFC de 3GPP) pero como **relay puro**: ~14 MiB y ~0.04 % CPU, y la latencia de setup vuelve a **~10 ms** (la de mims sin B2BUA). mims-2 logra el mismo patrón a un precio mayor (B2BUA, ~32 ms).
2. **Elimina dependencia de Asterisk en el plano de AS**: el IVR y el VMS son **nativos de FreeSWITCH** (dialplan public: `playback` + `record`, 8 kHz PCM16), lo que simplifica el despliegue, reduce una imagen de 337 MB y un punto de media.
3. **Extensibilidad sin re-trabajo**: la Frontera puede crecer (iFC adicionales, filtrado y re-etiquetado de cabeceras ISC, balanceo) sin tocar FreeSWITCH; y FreeSWITCH conserva su capacidad B2BUA si mañana se necesitan servicios UE→UE.
4. **Costo asumible y medido**: ~122 ms de registro y ~10 ms de setup; memoria del AS ~47 MiB (FreeSWITCH) + ~14 MiB (Frontera) = ~61 MiB vs ~51 MiB de mims-2 — coste **menor o igual** y sin doble leg de media.
5. **Separación de responsabilidades clara**: Core IMS (S-CSCF) → Frontera (interworking ISC/SIP) → AS aplicación (FreeSWITCH IVR/VMS). Es la composición más próxima al modelo de operador (S-CSCF → AS → media server) manteniendo la maqueta ligera.

**Matiz**: si el objetivo fuese estrictamente una demo IVR/VMS mínima, **maqueta-ims** (directo) sigue siendo la más simple; y si la propuesta exigiera desde el primer día servicios B2BUA (3PCC, conferencia), **maqueta-ims-2** la incluye nativamente en FreeSWITCH. Para una propuesta a operadores con visión de plataforma VAS y coste/latencia optimizados, **maqueta-ims-3 es la opción a argumentar**. La maqueta-ims-3 queda como entregable principal junto a mims-2 como alternativa B2BUA.

---

## 6. Limitaciones reconocidas (a incluir en la propuesta)

- IPsec en Gm desactivado (UEs softphone en red Docker; flujo + RTPEngine como sustituto).
- Autenticación Digest MD5 (no AKAv1/AKAv2).
- Sin Rx/PCRF (QoS) ni Ro/Rf (charging); sin iFC de tipo copiar hacia el AS.
- El AS valida el origen por IP del S-CSCF (Frontera) por `src_ip` (identify por IP de red interna, no por certificados/ICS).
- Frontera (mims-3) como relay sin B2BUA propio: UE→UE/conferencia requieren que FreeSWITCH suba de rol a B2BUA (capacidad ya presente).
- En mims-2, la media cruza dos saltos internos (RTPEngine → FreeSWITCH → Asterisk); en mims-3 un solo salto de media a FreeSWITCH (RTPEngine → FreeSWITCH). Debe re-validarse con carga en un entorno de VLAN de producción.