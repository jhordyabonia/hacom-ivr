# Verificación de cumplimiento 3GPP — señalización, autenticación y seguridad

**Maqueta:** `maqueta-ims-3` (rama `feature/feat-02`) · **Fecha:** 2026-10-06
**Evidencia:** `../03_iteraciones/iter-28-final/` y `../03_iteraciones/iter-29-confirmacion/`
(capturas `maqueta_ims_sip_only.pcap`, informe `check_3gpp.md`, log `test_maqueta.log`).

## 1. Resultado

| Captura | Reglas 3GPP | E2E (`test_maqueta.sh`) |
|---|---|---|
| Línea base (antes de los cambios, `iter-00-baseline`) | **5/27 (18,5 %)** | 16/20 |
| Final (`iter-28-final`) | **27/27 (100 %)** | **22/22** |
| Confirmación consecutiva (`iter-29-confirmacion`) | **27/27 (100 %)** | **22/22** |

"100 %" se refiere al conjunto de **27 reglas** que verifica `scripts/check_3gpp.py`
(tabla de la sección 3). Es un conjunto explícito y citado por especificación,
no una certificación de conformidad completa de TS 24.229.

## 2. Cómo se verifica (reproducible)

```bash
cd maqueta-ims-3
bash scripts/capture_iteration.sh ../entregables-feat-02/03_iteraciones/iter-NN
```

El script hace exactamente el flujo pedido:

1. `tcpdump -i any -s0 -w maqueta_ims.pcap` — en un contenedor `--net=host` con
   `NET_RAW/NET_ADMIN` (en el host `tcpdump`/`dumpcap` requieren sudo).
2. `bash scripts/test_maqueta.sh` — E2E de 22 checks bajo captura.
3. `tshark -r maqueta_ims.pcap -Y sip -w maqueta_ims_sip_only.pcap` con dos opciones
   añadidas, imprescindibles una vez activado IPsec:
   - `-o esp.enable_null_encryption_decode_heuristic:TRUE`: la señalización de Gm
     viaja dentro de ESP (cifrado NULL, solo integridad); sin la heurística tshark
     no ve el SIP protegido y el filtro lo descartaría.
   - `-d tcp.port==6060,sip -d tcp.port==4060,sip`: los puertos del S-CSCF/I-CSCF
     caen en el rango que Wireshark asigna a X11 (6000-6063) si van por TCP.
4. `python3 scripts/check_3gpp.py maqueta_ims_sip_only.pcap` — verificador propio:
   lee pcap/pcapng sin depender de campos de tshark, desencapsula ESP, valida
   **criptográficamente** la autenticación (Milenage, vectores TS 35.208 conjunto 1
   superados) y la integridad ESP, y evalúa las 27 reglas.

Notas de laboratorio: la red Docker usa **MTU 9000** para que la señalización
(INVITE con SDP AMR, REGISTER con Path/Security-*) no se fragmente y el filtro
`-Y sip -w` conserve mensajes completos; el umbral UDP→TCP (RFC 3261 §18.1.1)
se ajustó en coherencia (P-CSCF `udp_mtu=8800`, pjsua `PJSIP_UDP_SIZE_THRESHOLD`).

## 3. Reglas y estado final

| Id | Especificación | Qué se comprueba | Base | Final |
|---|---|---|---|---|
| G1 | RFC 3261 §8.1.1 | Cabeceras obligatorias, branch `z9hG4bK` | PASS | PASS |
| G2 | RFC 3261 §18.3 | Mensajes completos (Content-Length, sin fragmentar) | PASS | PASS |
| A1 | TS 24.229 §5.1.1.2.1, TS 23.003 §13.3 | REGISTER inicial con `Authorization` (IMPI = IMSI@dominio, `nonce=""`, `response=""`) | FAIL | PASS |
| A2 | TS 33.203 §6.1, RFC 3310 | 401 al UE: `algorithm=AKAv1-MD5`, nonce = RAND‖AUTN, `qop=auth`, **sin ck/ik** | FAIL | PASS |
| A3 | TS 24.229 §5.4.1.2.1 | 401 en Mw (S/I-CSCF→P-CSCF) con `ck`/`ik` para crear las SA | FAIL | PASS |
| A4 | TS 33.203 §6.1 | Ningún reto Digest-MD5 | FAIL | PASS |
| A5 | TS 33.203 §6.1, TS 35.206 | Respuesta AKA = f(RES) y AUTN (MAC-A) verificados con Milenage | FAIL | PASS |
| A6 | TS 24.229 §5.2.2.1 | P-CSCF marca `integrity-protected="no"/"yes"` hacia el S-CSCF | FAIL | PASS |
| S1 | RFC 3329, TS 33.203 §7.1 | `Security-Client: ipsec-3gpp` (alg, spi-c, spi-s, port-c≠port-s) + `Require`/`Proxy-Require: sec-agree` | FAIL | PASS |
| S2 | RFC 3329, TS 33.203 §7.1 | 401 con `Security-Server` propio del P-CSCF | FAIL | PASS |
| S3 | TS 33.203 §7.2 | 2º REGISTER: `Security-Verify` = `Security-Server` y enviado por la SA | FAIL | PASS |
| S4 | TS 33.203 §7.3 | Tras el acuerdo, **todo** el tráfico Gm en ESP | FAIL | PASS |
| S5 | TS 33.203 §7.1, RFC 2404 | ICV ESP HMAC-SHA-1-96 válido con la IK derivada (103 paquetes) | FAIL | PASS |
| S6 | TS 24.229 §5.2.2.1 | sec-agree solo en Gm; nunca en 2xx | PASS | PASS |
| R1 | TS 24.229 §5.1.1.2.1, TS 23.003 §13.4 | R-URI = dominio; From = To = IMPU `sip:<MSISDN>@dominio` | FAIL | PASS |
| R2 | TS 24.229 §5.1.1.2.1, RFC 3840 | Contact con port-s, `+g.3gpp.icsi-ref` (MMTEL, entre comillas), `+g.3gpp.smsip` | FAIL | PASS |
| R3 | TS 24.229 §7.2A.4 | `P-Access-Network-Info` del UE en toda petición salvo ACK/CANCEL | FAIL | PASS |
| R4 | TS 24.229 §5.2.2.1, RFC 3327 | Mw: `Path` del P-CSCF, `Require: path`, `P-Visited-Network-ID` | PASS | PASS |
| R5 | TS 24.229 §5.4.1.2.2 | 200 OK: `Service-Route`, `P-Associated-URI`, `Path`, expires | PASS | PASS |
| C1 | TS 24.229 §5.1.2A.1.1, TS 24.173 | INVITE del UE: Route (P-CSCF + Service-Route), Accept-Contact y P-Preferred-Service MMTEL | FAIL | PASS |
| C2 | TS 26.114 §5.2.1.2 | Oferta SDP MTSI con AMR-WB/16000, AMR/8000 y telephone-event | FAIL | PASS |
| C3 | TS 24.229 §5.2.6.3.3, RFC 3325, RFC 7315 | P-CSCF→core: PAI (sin PPI), `P-Charging-Vector icid-value`, Record-Route | FAIL | PASS |
| C4 | TS 24.229 §5.4.3.2, RFC 5502 | ISC: Route AS + ODI del S-CSCF, PAI y `P-Served-User` | FAIL | PASS |
| C5 | TS 29.228 Anexo B, TS 24.604 | Llamada a usuario no registrado desviada por iFC *terminating-unregistered* | FAIL | PASS |
| M1 | TS 24.606 §4.5.2, RFC 3842 | SUBSCRIBE `message-summary` del UE a su IMPU | FAIL | PASS |
| M2 | TS 24.606, TS 29.228 | SUBSCRIBE MWI enrutado por iFC (ISC) al AS de buzón | FAIL | PASS |
| M3 | TS 24.606, RFC 6665 | NOTIFY `message-summary` en diálogo (`yes` tras depósito, `no` tras borrado) | FAIL | PASS |

## 4. Autenticación y seguridad: qué se corrigió

| Antes | Ahora | Dónde |
|---|---|---|
| E2E en Digest **MD5** (fallback para clientes sin `Security-Client`) | **IMS-AKA obligatorio** (Digest-AKAv1-MD5); sin fallback | `scscf/kamailio_scscf.cfg` |
| pjsua no podía hacer AKA (pasaba la K en ASCII, sin OP/OPc) | UE con IMS-AKA real: K/OPc/AMF, IMPI desde el 1er REGISTER, verificación de AUTN | `softphone/ims_ext.c`, `softphone/Dockerfile` |
| `Security-Server`/`Security-Verify` **simulados** en el P-CSCF (eco de los SPI del UE; `Security-Verify` en el 200 OK) | `ims_ipsec_pcscf` real (`WITH_IPSEC`): SPI/puertos propios del P-CSCF y SA ESP en kernel; nada sec-agree en 2xx | `pcscf/pcscf.cfg`, `pcscf/route/register.cfg` |
| Sin IPsec ESP en Gm | 4 SA ESP UE↔P-CSCF (hmac-sha-1-96, ealg NULL), re-autenticación con juego de SA nuevo (TS 33.203 §7.4) | `softphone/ims-ipsec.sh` |
| Sin `integrity-protected` | `"no"` en el REGISTER inicial, `"yes"` por la SA | `pcscf/route/register.cfg` |
| sec-agree y `Security-*` se filtraban al core; `Require: 0` | Retirados en el P-CSCF para toda petición (route `STRIP_SECAGREE`) | `pcscf/kamailio_pcscf.cfg` |
| Peticiones hacia el UE (NOTIFY, BYE) salían en claro | `ipsec_forward` con flags de petición + búsqueda del contacto vigente; sin SA → 480, nunca en claro | `pcscf/route/mo.cfg`, `mt.cfg`, `pcscf/pcscf.cfg` |
| Alias de NAT en el Contact rompía el des-registro | Sin alias para clientes IPsec | `pcscf/kamailio_pcscf.cfg` |
| PANI/PPI inventadas por el P-CSCF | Las aporta el UE; el P-CSCF asierta PAI y retira PPI | `pcscf/kamailio_pcscf.cfg`, `ims_ext.c` |

## 5. Limitaciones y decisiones explícitas

- **Cifrado ESP NULL** (`ealg=null`): TS 33.203 permite integridad sin confidencialidad;
  facilita el análisis de las capturas. `ims-ipsec.sh` ya soporta `aes-cbc` si el
  P-CSCF lo prefiere (`ipsec_preferred_ealg`).
- **Claves de prueba**: K de `.env`, OPc `61f0…db0c1`, AMF `8000` (las provisionadas en
  PyHSS). El verificador las usa para validar RES y la integridad ESP.
- **Perfil no-3GPP (SIP Digest, TS 33.203 Anexo N)** para softphones comerciales:
  existe como `WITH_NON3GPP_DIGEST` en `scscf/scscf.cfg`, **desactivado**. Activarlo
  hace que A4 deje de cumplir para esos clientes (es su naturaleza).
- **pjsua no cancela su suscripción MWI al salir**: el test reinicia el AS en el paso 0
  para no arrastrar suscripciones de ejecuciones previas.
- **El P-CSCF acepta un 2º REGISTER no protegido** cuando el cliente no establece SA
  (lo usa la sonda `ue_aka_probe.py`, que sigue dando 200 OK). Endurecerlo es una
  mejora pendiente (no afecta a las capturas del E2E: S3/S4 lo verificarían).
- **Kamailio 6.2.0-dev1** traía un defecto en `ims_isc` (SessionCase de usuario no
  registrado); se parcheó en `kamailio/Dockerfile` igual que en upstream.
