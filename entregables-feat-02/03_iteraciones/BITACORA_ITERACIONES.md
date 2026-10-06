# Bitácora de iteraciones — captura → análisis 3GPP → corrección

Cada carpeta `iter-NN/` contiene: `test_maqueta.log` (E2E), `maqueta_ims_sip_only.pcap`
(filtro SIP) y `check_3gpp.md` (informe del verificador). La captura completa
`maqueta_ims.pcap` se conserva solo en `iter-00-baseline`, `iter-28-final` e
`iter-29-confirmacion` (las intermedias ocupaban ~700 MB y se regeneran con
`scripts/capture_iteration.sh`).

El verificador evolucionó durante el trabajo (iteraciones 01–03): sus informes
reflejan la versión de ese momento. La línea base se re-evaluó con la versión final.

| Iter | E2E | 3GPP | Reglas en FAIL | Hallazgo | Corrección aplicada |
|---|---|---|---|---|---|
| 00 base | 16/20 | 5/27 | A1–A6, S1–S5, R1–R3, C1–C5, M1–M3 | Digest MD5, sec-agree simulado, sin ESP, sin AMR; INVITE fragmentados (`-Y sip` perdía fragmentos); FEAT-02: iFC originante secuestraba UE1→UE2, dialplan obsoleto en la imagen de FS, PIN de 1 dígito | Plan completo (secciones siguientes) |
| 01 | 8/22 | 15/27 | A5 S4 S5 S6 C1–C5 M1–M3 | Primer registro AKA+IPsec OK; el P-CSCF responde por SA obsoletas de sesiones previas del UE (mismo puerto, `kill -9` sin des-registro) | Puertos protegidos nuevos por sesión, des-registro ordenado (`q`); P-CSCF retira sec-agree hacia el core |
| 02 | 9/22 | 19/27 | A4 A6 S3 S5 R5 C3 C5 M3 | FreeSWITCH reta con 407: pjsip (`initial_auth`) añade `Authorization` también al INVITE; `Security-Verify` obsoleto en el reenvío autenticado | `Authorization` solo en REGISTER; `Security-Verify` se renueva; verificador: A6 por SA real |
| 03 | 16/22 | 24/27 | S4 C5 M3 | SIP sobre TCP:6060 decodificado como X11; P-CSCF pasa a TCP >1300 B; ACK no sale (EPERM) | `-d tcp.port==6060,sip`; `udp_mtu=8800` (MTU 9000); diagnóstico del ACK |
| 04–05 | 10→17/22 | 24/27 | S4 C5 M3 | NAT con conntrack colapsa dos flujos (EPERM); al re-autenticar el UE borraba la SA vigente (503 en des-registro); alias NAT rompe el Contact; `Require: 0` (420) | Reescritura de puertos **sin estado** (nftables, `meta mark` para re-evaluar xfrm); dos generaciones de SA y SPI/port_uc nuevos (TS 33.203 §7.4); sin alias para IPsec; `STRIP_SECAGREE` |
| 06–09 | 17/22 | 25/27 | C5 M3 | UE2 sigue "registrado" tras des-registrarse; el S-CSCF no hacía SAR de no registrado; `isc_match_filter` no admite variables | Espera al barrido de usrloc (`timer_interval 5`); SAR `UNREGISTERED_USER` |
| 10–12 | 8→17/22 | 19→25/27 | S3 S4 S5 C3 C4 C5 M2 M3 | Tras reconstruir Kamailio el P-CSCF reinicia SPI en 4096 y chocan con SA residuales del UE (`File exists`) | `ims-ipsec.sh` idempotente (borra antes de añadir) |
| 13 | 17/22 | 26/27 | M3 | `ims_isc` evaluaba SessionCase 1 para usuarios no registrados (bug de 6.2.0-dev1) | Parche de `ims_isc` en `kamailio/Dockerfile`; C5 en verde |
| 14–15 | 19→20/22 | 25→26/27 | A4 M3 / S4 | FreeSWITCH con config vieja (`init.sh` en la imagen); 407 al SUBSCRIBE; API de PIN en puerto equivocado | Reconstrucción de FS; `auth-subscriptions=false`; API `:8888`; M3 (MWI yes) en verde |
| 16–19 | 18→20/22 | 25/27 | S4 M3 | NOTIFY/BYE hacia el UE fuera de la SA; el P-CSCF reenviaba al core desde el puerto protegido; residuos de suscripciones MWI de corridas anteriores; menú de mod_voicemail cuelga por falta de prompts | Mw siempre desde 5060; P-CSCF nunca envía en claro a un UE IPsec (480); AS sin estado al arrancar; menú propio en Lua sobre la API de mod_voicemail |
| 20–23 | 21/22 | 26/27 | S4 | `ipsec_forward` elegía el contacto pendiente (sin `port_pc` → socket 5060) | Flags de petición sin `USEVIA` |
| 24 | 21/22 | **27/27** | — | + `IPSEC_REVERSE_SEARCH` (contacto vigente): todo Gm en ESP. Falta NOTIFY "no" tras borrar | `vm_delete` no emite MWI → evento `MESSAGE_WAITING` desde Lua |
| 25 | 21/22 | 27/27 | — | mod_sofia no asocia el dominio IMS a un perfil | `Sofia-Profile` + alias del dominio |
| 26 | **22/22** | **27/27** | — | — | — |
| 27 | 22/22 | 25/27 | S5 M3 | Corrida inmediata tras la 26: NOTIFY a la suscripción MWI del UE2 de la corrida anterior (pjsua no la cancela al salir) | Paso 0 del test reinicia el AS |
| 28 final | **22/22** | **27/27** | — | — | Tras añadir el perfil Digest opcional (desactivado) y recompilar el softphone |
| 29 confirmación | **22/22** | **27/27** | — | Corrida consecutiva a la 28 | — |
