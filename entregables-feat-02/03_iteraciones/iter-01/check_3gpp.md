# Verificación 3GPP — maqueta_ims_sip_only.pcap

| Métrica | Valor |
|---|---|
| Mensajes SIP (deduplicados) | 211 |
| Mensajes en Gm (UE↔P-CSCF) | 111 (ESP: 84) |
| Métodos | REGISTER=111 |
| Reglas aplicables | 27 |
| **Cumplimiento** | **15/27 (55.6 %)** |

| Regla | Especificación | Verificación | Resultado | Evidencia |
|---|---|---|---|---|
| G1 | RFC 3261 §8.1.1/§20 | Cabeceras obligatorias y branch z9hG4bK en todos los mensajes | **PASS** | 211 mensajes verificados |
| G2 | RFC 3261 §18.3/§20.14 | Mensajes completos (Content-Length = cuerpo, sin fragmentación IP) | **PASS** | 211 mensajes íntegros |
| A1 | TS 24.229 §5.1.1.2.1 / TS 23.003 §13.3 | REGISTER inicial: Authorization con IMPI (IMSI@dominio), realm, uri, nonce="" y response="" | **PASS** | 7 REGISTER iniciales conformes |
| A2 | TS 33.203 §6.1 / RFC 3310 §3.1 / TS 24.229 §5.2.2.1 | 401 al UE: algorithm=AKAv1-MD5, nonce=base64(RAND‖AUTN), qop=auth, sin ck/ik | **PASS** | 13 retos AKA conformes |
| A3 | TS 24.229 §5.4.1.2.1 / TS 33.203 §7.2 | 401 en Mw (S/I-CSCF→P-CSCF) transporta ck/ik para establecer las SA | **PASS** | 13 retos en Mw con ck/ik |
| A4 | TS 33.203 §6.1 | Ningún reto con Digest-MD5 (solo IMS-AKA) | **PASS** | 0 retos MD5 |
| A5 | TS 33.203 §6.1 / TS 35.206 / RFC 3310 §3.4 | Respuesta Digest-AKAv1-MD5 = f(RES) y AUTN (MAC-A) verificados con Milenage | **FAIL** | #119 UE→P-CSCF REGISTER sip:ims.mnc001.mcc001.3gppnetwork.org SIP/2.0 response= esperado=2292f35550ece61d2965eafb64efe661 MAC-ok=True<br>#120 UE→P-CSCF REGISTER sip:ims.mnc001.mcc001.3gppnetwork.org SIP/2.0 response= esperado=2292f35550ece61d2965eafb64efe661 MAC-ok=True<br>#121 UE→P-CSCF REGISTER sip:ims.mnc001.mcc001.3gppnetwork.org SIP/2.0 response= esperado=2292f35550ece61d2965eafb64efe661 MAC-ok=True<br>#122 UE→P-CSCF REGISTER sip:ims.mnc001.mcc001.3gppnetwork.org SIP/2.0 response= esperado=2292f35550ece61d2965eafb64efe661 MAC-ok=True |
| A6 | TS 24.229 §5.2.2.1 / TS 33.203 §6.1 | P-CSCF marca integrity-protected="no" (inicial) / "yes" (por la SA) hacia el S-CSCF | **PASS** | 20 REGISTER en Mw conformes |
| S1 | RFC 3329 §2.3.1 / TS 33.203 §7.1 / TS 24.229 §5.1.1.2.1 | REGISTER del UE: Security-Client ipsec-3gpp (alg, spi-c≠, spi-s, port-c≠port-s) + Require/Proxy-Require: sec-agree | **PASS** | 71 REGISTER con sec-agree |
| S2 | RFC 3329 §2.3.1 / TS 33.203 §7.1 | 401 al UE con Security-Server ipsec-3gpp (q, alg, spi-c, spi-s, port-c, port-s) propios del P-CSCF | **PASS** | 13 Security-Server conformes |
| S3 | RFC 3329 §2.3.1 / TS 33.203 §7.2 / TS 24.229 §5.1.1.2.1 | 2º REGISTER: Security-Verify = Security-Server y enviado por la SA (ESP, port-s/spi-s del P-CSCF) | **PASS** | #9 UE→P-CSCF REGISTER sip:ims.mnc001.mcc001.3gppnetwork.org SIP/2.0 ESP spi=4103 → P-CSCF:6103<br>#17 UE→P-CSCF REGISTER sip:ims.mnc001.mcc001.3gppnetwork.org SIP/2.0 ESP spi=4103 → P-CSCF:6103<br>#18 UE→P-CSCF REGISTER sip:ims.mnc001.mcc001.3gppnetwork.org SIP/2.0 ESP spi=4103 → P-CSCF:6103<br>#26 UE→P-CSCF REGISTER sip:ims.mnc001.mcc001.3gppnetwork.org SIP/2.0 ESP spi=4103 → P-CSCF:6103 |
| S4 | TS 33.203 §7.3 / TS 24.229 §5.1.1.2.2 | Tras el acuerdo, todo mensaje SIP en Gm viaja protegido por IPsec ESP | **FAIL** | #25 P-CSCF→UE SIP/2.0 401 Unauthorized - Challenging the UE<br>#54 P-CSCF→UE SIP/2.0 401 Unauthorized - Challenging the UE<br>#83 P-CSCF→UE SIP/2.0 401 Unauthorized - Challenging the UE<br>#113 P-CSCF→UE SIP/2.0 401 Unauthorized - Challenging the UE |
| S5 | TS 33.203 §7.1 / RFC 2404 / RFC 4303 | Integridad ESP verificada: ICV HMAC-SHA-1-96 con IK derivada por Milenage | **FAIL** | #16 P-CSCF→UE SIP/2.0 200 OK spi=46853<br>#45 P-CSCF→UE SIP/2.0 200 OK spi=46853<br>#74 P-CSCF→UE SIP/2.0 200 OK spi=46853<br>#104 P-CSCF→UE SIP/2.0 200 OK spi=46853 |
| S6 | TS 24.229 §5.2.2.1 / RFC 3329 §2.3.1 | Cabeceras sec-agree solo en Gm (P-CSCF las retira hacia el core) y nunca en 2xx | **FAIL** | #3 P-CSCF→I-CSCF REGISTER sip:ims.mnc001.mcc001.3gppnetwork.org SIP/2.0<br>#5 I-CSCF→S-CSCF REGISTER sip:scscf.ims.mnc001.mcc001.3gppnetwork.org:6060;tr<br>#11 P-CSCF→I-CSCF REGISTER sip:ims.mnc001.mcc001.3gppnetwork.org SIP/2.0<br>#13 I-CSCF→S-CSCF REGISTER sip:scscf.ims.mnc001.mcc001.3gppnetwork.org:6060;tr |
| R1 | TS 24.229 §5.1.1.2.1 / TS 23.003 §13.4 | REGISTER: R-URI = dominio de red local; From = To = IMPU sip:<MSISDN>@dominio | **PASS** | 71 REGISTER conformes |
| R2 | TS 24.229 §5.1.1.2.1 / RFC 3840 §9 / TS 24.173 §5.2 | Contact: puerto protegido port-s, +g.3gpp.icsi-ref (MMTEL, entre comillas) y +g.3gpp.smsip | **PASS** | 71 Contact conformes |
| R3 | TS 24.229 §5.1.1.2.1 / §7.2A.4 | P-Access-Network-Info del UE (E-UTRAN, utran-cell-id-3gpp) en toda petición salvo ACK/CANCEL | **PASS** | PANI presente y bien formado |
| R4 | TS 24.229 §5.2.2.1 / RFC 3327 | REGISTER en Mw: Path del P-CSCF, Require: path y P-Visited-Network-ID | **PASS** | 20 REGISTER en Mw conformes |
| R5 | TS 24.229 §5.4.1.2.2 / RFC 3608 / RFC 3455 | 200 OK del REGISTER: Service-Route, P-Associated-URI, Path y Contact con expires | **PASS** | 7 200 OK conformes |
| C1 | TS 24.229 §5.1.2A.1.1 / TS 24.173 §5.1 / RFC 3841 | INVITE inicial del UE: Route (P-CSCF + Service-Route), Contact/Accept-Contact y P-Preferred-Service MMTEL | **FAIL** | 0 INVITE iniciales conformes |
| C2 | TS 26.114 §5.2.1.2 / §6.2.2 | Oferta SDP del UE (MTSI) incluye AMR-WB/16000, AMR/8000 y telephone-event | **FAIL** | 0 ofertas SDP con AMR/AMR-WB |
| C3 | TS 24.229 §5.2.6.3.3 / §5.2.7 / RFC 3325 / RFC 7315 | INVITE P-CSCF→core: P-Asserted-Identity (sin PPI), P-Charging-Vector icid-value y Record-Route | **FAIL** | 0 INVITE en Mw conformes |
| C4 | TS 24.229 §5.4.3.2 / §5.4.3.3 / RFC 5502 | ISC (S-CSCF→AS): Route = AS + S-CSCF (ODI), P-Asserted-Identity y P-Served-User | **FAIL** | 0 peticiones ISC conformes |
| C5 | TS 23.218 §6 / TS 29.228 Anexo B (SessionCase 2) / TS 24.604 | Llamada a usuario no registrado desviada por iFC terminating-unregistered al AS de buzón | **FAIL** | sin INVITE terminating-unregistered hacia el AS |
| M1 | TS 24.606 §4.5.2 / RFC 3842 §3 | SUBSCRIBE del UE: Event: message-summary al propio IMPU con Expires | **FAIL** | 0 SUBSCRIBE MWI conformes |
| M2 | TS 24.606 §4.5.2 / TS 29.228 Anexo B | SUBSCRIBE MWI enrutado por iFC (ISC) al AS de buzón | **FAIL** | sin SUBSCRIBE en ISC |
| M3 | TS 24.606 §4.5.2 / RFC 3842 §5 / RFC 6665 | NOTIFY message-summary al UE dentro del diálogo (Subscription-State, simple-message-summary) | **FAIL** | 0 NOTIFY MWI; Messages-Waiting= |

ESTADO: NO CUMPLE
