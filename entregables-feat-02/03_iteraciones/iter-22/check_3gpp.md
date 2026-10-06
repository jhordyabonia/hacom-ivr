# Verificación 3GPP — maqueta_ims_sip_only.pcap

| Métrica | Valor |
|---|---|
| Mensajes SIP (deduplicados) | 349 |
| Mensajes en Gm (UE↔P-CSCF) | 118 (ESP: 95) |
| Métodos | ACK=15, BYE=15, INVITE=22, NOTIFY=3, REGISTER=84, SUBSCRIBE=4 |
| Reglas aplicables | 27 |
| **Cumplimiento** | **26/27 (96.3 %)** |

| Regla | Especificación | Verificación | Resultado | Evidencia |
|---|---|---|---|---|
| G1 | RFC 3261 §8.1.1/§20 | Cabeceras obligatorias y branch z9hG4bK en todos los mensajes | **PASS** | 349 mensajes verificados |
| G2 | RFC 3261 §18.3/§20.14 | Mensajes completos (Content-Length = cuerpo, sin fragmentación IP) | **PASS** | 349 mensajes íntegros |
| A1 | TS 24.229 §5.1.1.2.1 / TS 23.003 §13.3 | REGISTER inicial: Authorization con IMPI (IMSI@dominio), realm, uri, nonce="" y response="" | **PASS** | 14 REGISTER iniciales conformes |
| A2 | TS 33.203 §6.1 / RFC 3310 §3.1 / TS 24.229 §5.2.2.1 | 401 al UE: algorithm=AKAv1-MD5, nonce=base64(RAND‖AUTN), qop=auth, sin ck/ik | **PASS** | 14 retos AKA conformes |
| A3 | TS 24.229 §5.4.1.2.1 / TS 33.203 §7.2 | 401 en Mw (S/I-CSCF→P-CSCF) transporta ck/ik para establecer las SA | **PASS** | 14 retos en Mw con ck/ik |
| A4 | TS 33.203 §6.1 | Ningún reto con Digest-MD5 (solo IMS-AKA) | **PASS** | 0 retos MD5 |
| A5 | TS 33.203 §6.1 / TS 35.206 / RFC 3310 §3.4 | Respuesta Digest-AKAv1-MD5 = f(RES) y AUTN (MAC-A) verificados con Milenage | **PASS** | #9 UE→P-CSCF REGISTER sip:ims.mnc001.mcc001.3gppnetwork.org SIP/2.0 RES ok, AUTN MAC-A ok (SQN=0000000071a3)<br>#25 UE→P-CSCF REGISTER sip:ims.mnc001.mcc001.3gppnetwork.org SIP/2.0 RES ok, AUTN MAC-A ok (SQN=000000007207)<br>#41 UE→P-CSCF REGISTER sip:ims.mnc001.mcc001.3gppnetwork.org SIP/2.0 RES ok, AUTN MAC-A ok (SQN=00000000726b)<br>#78 UE→P-CSCF REGISTER sip:ims.mnc001.mcc001.3gppnetwork.org SIP/2.0 RES ok, AUTN MAC-A ok (SQN=0000000072cf) |
| A6 | TS 24.229 §5.2.2.1 / TS 33.203 §6.1 | P-CSCF marca integrity-protected="no" (inicial) / "yes" (por la SA) hacia el S-CSCF | **PASS** | 28 REGISTER en Mw conformes |
| S1 | RFC 3329 §2.3.1 / TS 33.203 §7.1 / TS 24.229 §5.1.1.2.1 | REGISTER del UE: Security-Client ipsec-3gpp (alg, spi-c≠, spi-s, port-c≠port-s) + Require/Proxy-Require: sec-agree | **PASS** | 28 REGISTER con sec-agree |
| S2 | RFC 3329 §2.3.1 / TS 33.203 §7.1 | 401 al UE con Security-Server ipsec-3gpp (q, alg, spi-c, spi-s, port-c, port-s) propios del P-CSCF | **PASS** | 14 Security-Server conformes |
| S3 | RFC 3329 §2.3.1 / TS 33.203 §7.2 / TS 24.229 §5.1.1.2.1 | 2º REGISTER: Security-Verify = Security-Server y enviado por la SA (ESP, port-s/spi-s del P-CSCF) | **PASS** | #9 UE→P-CSCF REGISTER sip:ims.mnc001.mcc001.3gppnetwork.org SIP/2.0 ESP spi=4125 → P-CSCF:6104<br>#25 UE→P-CSCF REGISTER sip:ims.mnc001.mcc001.3gppnetwork.org SIP/2.0 ESP spi=4127 → P-CSCF:6105<br>#41 UE→P-CSCF REGISTER sip:ims.mnc001.mcc001.3gppnetwork.org SIP/2.0 ESP spi=4129 → P-CSCF:6106<br>#78 UE→P-CSCF REGISTER sip:ims.mnc001.mcc001.3gppnetwork.org SIP/2.0 ESP spi=4131 → P-CSCF:6107 |
| S4 | TS 33.203 §7.3 / TS 24.229 §5.1.1.2.2 | Tras el acuerdo, todo mensaje SIP en Gm viaja protegido por IPsec ESP | **FAIL** | #309 P-CSCF→UE NOTIFY sip:0010100002@172.32.0.10:35984;ob SIP/2.0<br>#330 P-CSCF→UE BYE sip:0010100002@172.32.0.10:35984;ob SIP/2.0 |
| S5 | TS 33.203 §7.1 / RFC 2404 / RFC 4303 | Integridad ESP verificada: ICV HMAC-SHA-1-96 con IK derivada por Milenage | **PASS** | 95 paquetes ESP con ICV válido (14 IK distintas) |
| S6 | TS 24.229 §5.2.2.1 / RFC 3329 §2.3.1 | Cabeceras sec-agree solo en Gm (P-CSCF las retira hacia el core) y nunca en 2xx | **PASS** | sin fugas de cabeceras sec-agree |
| R1 | TS 24.229 §5.1.1.2.1 / TS 23.003 §13.4 | REGISTER: R-URI = dominio de red local; From = To = IMPU sip:<MSISDN>@dominio | **PASS** | 28 REGISTER conformes |
| R2 | TS 24.229 §5.1.1.2.1 / RFC 3840 §9 / TS 24.173 §5.2 | Contact: puerto protegido port-s, +g.3gpp.icsi-ref (MMTEL, entre comillas) y +g.3gpp.smsip | **PASS** | 28 Contact conformes |
| R3 | TS 24.229 §5.1.1.2.1 / §7.2A.4 | P-Access-Network-Info del UE (E-UTRAN, utran-cell-id-3gpp) en toda petición salvo ACK/CANCEL | **PASS** | PANI presente y bien formado |
| R4 | TS 24.229 §5.2.2.1 / RFC 3327 | REGISTER en Mw: Path del P-CSCF, Require: path y P-Visited-Network-ID | **PASS** | 28 REGISTER en Mw conformes |
| R5 | TS 24.229 §5.4.1.2.2 / RFC 3608 / RFC 3455 | 200 OK del REGISTER: Service-Route, P-Associated-URI, Path y Contact con expires | **PASS** | 14 200 OK conformes |
| C1 | TS 24.229 §5.1.2A.1.1 / TS 24.173 §5.1 / RFC 3841 | INVITE inicial del UE: Route (P-CSCF + Service-Route), Contact/Accept-Contact y P-Preferred-Service MMTEL | **PASS** | 5 INVITE iniciales conformes |
| C2 | TS 26.114 §5.2.1.2 / §6.2.2 | Oferta SDP del UE (MTSI) incluye AMR-WB/16000, AMR/8000 y telephone-event | **PASS** | 5 ofertas SDP con AMR/AMR-WB |
| C3 | TS 24.229 §5.2.6.3.3 / §5.2.7 / RFC 3325 / RFC 7315 | INVITE P-CSCF→core: P-Asserted-Identity (sin PPI), P-Charging-Vector icid-value y Record-Route | **PASS** | 5 INVITE en Mw conformes |
| C4 | TS 24.229 §5.4.3.2 / §5.4.3.3 / RFC 5502 | ISC (S-CSCF→AS): Route = AS + S-CSCF (ODI), P-Asserted-Identity y P-Served-User | **PASS** | 6 peticiones ISC conformes |
| C5 | TS 23.218 §6 / TS 29.228 Anexo B (SessionCase 2) / TS 24.604 | Llamada a usuario no registrado desviada por iFC terminating-unregistered al AS de buzón | **PASS** | #248 S-CSCF→AS-Front INVITE sip:0010100002@ims.mnc001.mcc001.3gppnetwork.org SIP/ P-Served-User=<sip:0010100002@ims.mnc001.mcc001.3gppnetwork.org>;sescase=term;regstate=unreg |
| M1 | TS 24.606 §4.5.2 / RFC 3842 §3 | SUBSCRIBE del UE: Event: message-summary al propio IMPU con Expires | **PASS** | 1 SUBSCRIBE MWI conformes |
| M2 | TS 24.606 §4.5.2 / TS 29.228 Anexo B | SUBSCRIBE MWI enrutado por iFC (ISC) al AS de buzón | **PASS** | #301 S-CSCF→AS-Front SUBSCRIBE sip:0010100002@ims.mnc001.mcc001.3gppnetwork.org S |
| M3 | TS 24.606 §4.5.2 / RFC 3842 §5 / RFC 6665 | NOTIFY message-summary al UE dentro del diálogo (Subscription-State, simple-message-summary) | **PASS** | 1 NOTIFY MWI; Messages-Waiting=yes |

ESTADO: NO CUMPLE
