# Verificación 3GPP — maqueta_ims_sip_only.pcap

| Métrica | Valor |
|---|---|
| Mensajes SIP (deduplicados) | 348 |
| Mensajes en Gm (UE↔P-CSCF) | 136 (ESP: 115) |
| Métodos | ACK=28, INVITE=28, REGISTER=105, SUBSCRIBE=3 |
| Reglas aplicables | 27 |
| **Cumplimiento** | **19/27 (70.4 %)** |

| Regla | Especificación | Verificación | Resultado | Evidencia |
|---|---|---|---|---|
| G1 | RFC 3261 §8.1.1/§20 | Cabeceras obligatorias y branch z9hG4bK en todos los mensajes | **PASS** | 348 mensajes verificados |
| G2 | RFC 3261 §18.3/§20.14 | Mensajes completos (Content-Length = cuerpo, sin fragmentación IP) | **PASS** | 348 mensajes íntegros |
| A1 | TS 24.229 §5.1.1.2.1 / TS 23.003 §13.3 | REGISTER inicial: Authorization con IMPI (IMSI@dominio), realm, uri, nonce="" y response="" | **PASS** | 14 REGISTER iniciales conformes |
| A2 | TS 33.203 §6.1 / RFC 3310 §3.1 / TS 24.229 §5.2.2.1 | 401 al UE: algorithm=AKAv1-MD5, nonce=base64(RAND‖AUTN), qop=auth, sin ck/ik | **PASS** | 14 retos AKA conformes |
| A3 | TS 24.229 §5.4.1.2.1 / TS 33.203 §7.2 | 401 en Mw (S/I-CSCF→P-CSCF) transporta ck/ik para establecer las SA | **PASS** | 14 retos en Mw con ck/ik |
| A4 | TS 33.203 §6.1 | Ningún reto con Digest-MD5 (solo IMS-AKA) | **FAIL** | #56 FreeSWITCH→AS-Front SIP/2.0 407 Proxy Authentication Required<br>#58 AS-Front→S-CSCF SIP/2.0 407 Proxy Authentication Required<br>#60 P-CSCF→UE SIP/2.0 407 Proxy Authentication Required<br>#112 FreeSWITCH→AS-Front SIP/2.0 407 Proxy Authentication Required |
| A5 | TS 33.203 §6.1 / TS 35.206 / RFC 3310 §3.4 | Respuesta Digest-AKAv1-MD5 = f(RES) y AUTN (MAC-A) verificados con Milenage | **PASS** | #9 UE→P-CSCF REGISTER sip:ims.mnc001.mcc001.3gppnetwork.org SIP/2.0 RES ok, AUTN MAC-A ok (SQN=0000000020c7)<br>#25 UE→P-CSCF REGISTER sip:ims.mnc001.mcc001.3gppnetwork.org SIP/2.0 RES ok, AUTN MAC-A ok (SQN=00000000212b)<br>#32 UE→P-CSCF REGISTER sip:ims.mnc001.mcc001.3gppnetwork.org SIP/2.0 RES ok, AUTN MAC-A ok (SQN=00000000212b)<br>#33 UE→P-CSCF REGISTER sip:ims.mnc001.mcc001.3gppnetwork.org SIP/2.0 RES ok, AUTN MAC-A ok (SQN=00000000212b) |
| A6 | TS 24.229 §5.2.2.1 / TS 33.203 §6.1 | P-CSCF marca integrity-protected="no" (inicial) / "yes" (por la SA) hacia el S-CSCF | **FAIL** | #19 P-CSCF→I-CSCF REGISTER sip:ims.mnc001.mcc001.3gppnetwork.org SIP/2.0 integrity-protected=yes (esperado no)<br>#75 P-CSCF→I-CSCF REGISTER sip:ims.mnc001.mcc001.3gppnetwork.org SIP/2.0 integrity-protected=yes (esperado no)<br>#131 P-CSCF→I-CSCF REGISTER sip:ims.mnc001.mcc001.3gppnetwork.org SIP/2.0 integrity-protected=yes (esperado no)<br>#187 P-CSCF→I-CSCF REGISTER sip:ims.mnc001.mcc001.3gppnetwork.org SIP/2.0 integrity-protected=yes (esperado no) |
| S1 | RFC 3329 §2.3.1 / TS 33.203 §7.1 / TS 24.229 §5.1.1.2.1 | REGISTER del UE: Security-Client ipsec-3gpp (alg, spi-c≠, spi-s, port-c≠port-s) + Require/Proxy-Require: sec-agree | **PASS** | 49 REGISTER con sec-agree |
| S2 | RFC 3329 §2.3.1 / TS 33.203 §7.1 | 401 al UE con Security-Server ipsec-3gpp (q, alg, spi-c, spi-s, port-c, port-s) propios del P-CSCF | **PASS** | 14 Security-Server conformes |
| S3 | RFC 3329 §2.3.1 / TS 33.203 §7.2 / TS 24.229 §5.1.1.2.1 | 2º REGISTER: Security-Verify = Security-Server y enviado por la SA (ESP, port-s/spi-s del P-CSCF) | **FAIL** | #25 UE→P-CSCF REGISTER sip:ims.mnc001.mcc001.3gppnetwork.org SIP/2.0 no viaja por la SA (dport=6101 spi=4099; esperado 6100/4097)<br>#32 UE→P-CSCF REGISTER sip:ims.mnc001.mcc001.3gppnetwork.org SIP/2.0 no viaja por la SA (dport=6101 spi=4099; esperado 6100/4097)<br>#33 UE→P-CSCF REGISTER sip:ims.mnc001.mcc001.3gppnetwork.org SIP/2.0 no viaja por la SA (dport=6101 spi=4099; esperado 6100/4097)<br>#34 UE→P-CSCF REGISTER sip:ims.mnc001.mcc001.3gppnetwork.org SIP/2.0 no viaja por la SA (dport=6101 spi=4099; esperado 6100/4097) |
| S4 | TS 33.203 §7.3 / TS 24.229 §5.1.1.2.2 | Tras el acuerdo, todo mensaje SIP en Gm viaja protegido por IPsec ESP | **PASS** | 136 mensajes Gm; 115 en ESP |
| S5 | TS 33.203 §7.1 / RFC 2404 / RFC 4303 | Integridad ESP verificada: ICV HMAC-SHA-1-96 con IK derivada por Milenage | **FAIL** | #9 UE→P-CSCF REGISTER sip:ims.mnc001.mcc001.3gppnetwork.org SIP/2.0 spi=4097<br>#10 P-CSCF→UE SIP/2.0 100 Trying spi=95124<br>#16 P-CSCF→UE SIP/2.0 200 OK spi=95125<br>#17 UE→P-CSCF REGISTER sip:ims.mnc001.mcc001.3gppnetwork.org SIP/2.0 spi=4097 |
| S6 | TS 24.229 §5.2.2.1 / RFC 3329 §2.3.1 | Cabeceras sec-agree solo en Gm (P-CSCF las retira hacia el core) y nunca en 2xx | **PASS** | sin fugas de cabeceras sec-agree |
| R1 | TS 24.229 §5.1.1.2.1 / TS 23.003 §13.4 | REGISTER: R-URI = dominio de red local; From = To = IMPU sip:<MSISDN>@dominio | **PASS** | 49 REGISTER conformes |
| R2 | TS 24.229 §5.1.1.2.1 / RFC 3840 §9 / TS 24.173 §5.2 | Contact: puerto protegido port-s, +g.3gpp.icsi-ref (MMTEL, entre comillas) y +g.3gpp.smsip | **PASS** | 49 Contact conformes |
| R3 | TS 24.229 §5.1.1.2.1 / §7.2A.4 | P-Access-Network-Info del UE (E-UTRAN, utran-cell-id-3gpp) en toda petición salvo ACK/CANCEL | **PASS** | PANI presente y bien formado |
| R4 | TS 24.229 §5.2.2.1 / RFC 3327 | REGISTER en Mw: Path del P-CSCF, Require: path y P-Visited-Network-ID | **PASS** | 28 REGISTER en Mw conformes |
| R5 | TS 24.229 §5.4.1.2.2 / RFC 3608 / RFC 3455 | 200 OK del REGISTER: Service-Route, P-Associated-URI, Path y Contact con expires | **FAIL** | #31 P-CSCF→UE SIP/2.0 200 OK SR=<sip:orig@scscf.ims.mnc001.mcc001.3gppnetwork.org:6060;lr> PAU=<sip:0010100001@ims.mnc001.mcc001.3gppnetwork.org>, <tel:0010100001>, <sip:001011234567890@ims.mnc001.mcc001.3gppnetwork.org><br>#87 P-CSCF→UE SIP/2.0 200 OK SR=<sip:orig@scscf.ims.mnc001.mcc001.3gppnetwork.org:6060;lr> PAU=<sip:0010100001@ims.mnc001.mcc001.3gppnetwork.org>, <tel:0010100001>, <sip:001011234567890@ims.mnc001.mcc001.3gppnetwork.org><br>#143 P-CSCF→UE SIP/2.0 200 OK SR=<sip:orig@scscf.ims.mnc001.mcc001.3gppnetwork.org:6060;lr> PAU=<sip:0010100001@ims.mnc001.mcc001.3gppnetwork.org>, <tel:0010100001>, <sip:001011234567890@ims.mnc001.mcc001.3gppnetwork.org><br>#199 P-CSCF→UE SIP/2.0 200 OK SR=<sip:orig@scscf.ims.mnc001.mcc001.3gppnetwork.org:6060;lr> PAU=<sip:0010100001@ims.mnc001.mcc001.3gppnetwork.org>, <tel:0010100001>, <sip:001011234567890@ims.mnc001.mcc001.3gppnetwork.org> |
| C1 | TS 24.229 §5.1.2A.1.1 / TS 24.173 §5.1 / RFC 3841 | INVITE inicial del UE: Route (P-CSCF + Service-Route), Contact/Accept-Contact y P-Preferred-Service MMTEL | **PASS** | 9 INVITE iniciales conformes |
| C2 | TS 26.114 §5.2.1.2 / §6.2.2 | Oferta SDP del UE (MTSI) incluye AMR-WB/16000, AMR/8000 y telephone-event | **PASS** | 9 ofertas SDP con AMR/AMR-WB |
| C3 | TS 24.229 §5.2.6.3.3 / §5.2.7 / RFC 3325 / RFC 7315 | INVITE P-CSCF→core: P-Asserted-Identity (sin PPI), P-Charging-Vector icid-value y Record-Route | **FAIL** | 0 INVITE en Mw conformes |
| C4 | TS 24.229 §5.4.3.2 / §5.4.3.3 / RFC 5502 | ISC (S-CSCF→AS): Route = AS + S-CSCF (ODI), P-Asserted-Identity y P-Served-User | **PASS** | 9 peticiones ISC conformes |
| C5 | TS 23.218 §6 / TS 29.228 Anexo B (SessionCase 2) / TS 24.604 | Llamada a usuario no registrado desviada por iFC terminating-unregistered al AS de buzón | **FAIL** | sin INVITE terminating-unregistered hacia el AS |
| M1 | TS 24.606 §4.5.2 / RFC 3842 §3 | SUBSCRIBE del UE: Event: message-summary al propio IMPU con Expires | **PASS** | 1 SUBSCRIBE MWI conformes |
| M2 | TS 24.606 §4.5.2 / TS 29.228 Anexo B | SUBSCRIBE MWI enrutado por iFC (ISC) al AS de buzón | **PASS** | #304 S-CSCF→AS-Front SUBSCRIBE sip:0010100002@ims.mnc001.mcc001.3gppnetwork.org S |
| M3 | TS 24.606 §4.5.2 / RFC 3842 §5 / RFC 6665 | NOTIFY message-summary al UE dentro del diálogo (Subscription-State, simple-message-summary) | **FAIL** | 0 NOTIFY MWI; Messages-Waiting= |

ESTADO: NO CUMPLE
