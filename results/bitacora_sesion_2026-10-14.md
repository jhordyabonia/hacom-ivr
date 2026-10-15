# Bitácora de la sesión — maqueta IMS en DEV

**Fecha de actualización:** 14 de octubre de 2026 (prompt 7). [CONFIG]  
**Rama de trabajo observada:** `feature/feat-02`. [CONFIG]  
**Tipo de documento:** bitácora explicativa; distingue citas literales, historia resumida y hechos verificados. [DOC]

## Alcance y límites

Esta bitácora reúne los prompts de usuario que están disponibles en el contexto de esta sesión, las respuestas del asistente recuperables y un resumen verificable de las decisiones tomadas. [INFERENCE]

Parte de la historia anterior se entregó ya resumida, no como transcripción completa; por eso, sus respuestas se describen como resumen y no se presentan como citas textuales. [DOC]

“Razonamiento” se interpreta aquí como el resumen de criterios, evidencias y decisiones. No se reproduce razonamiento interno privado paso a paso. [DOC]

## Prompts del usuario

### Prompts originales disponibles literalmente

1. > divide los componentes (servidores/contenedores) de la maqueta-3, entre los 3 servidores descritos en este archivo:  
   > /media/jhordy/documents/hacom/ivr/doc/hacom - maqueta IMS v1.1 - 10102026.csv  
   > -agrega una colomna al archvio en donde agreges los componente

2. > quedo desplegada la maquta en los ambientes de dev?  
   > dame la url para ingresar a la web, de test E2E (validacion maqueta)?

3. > revise y la maqueta esta teniendo varias fallas (/home/jhordy/Pictures/Screenshots/Screenshot+From+2026-10-14+12-45-26-1.png), reparalas, tambien ejecuta las instrucciones presentes en el archivo /media/jhordy/documents/hacom/ivr/context-X.txt; todo esto para el ambiente en dev (los tres serever)

### Prompts posteriores disponibles literalmente

4. > ya se reestablecio la vpn, continua

5. > continua..

6. > agrega a un archvio md, todos los promts que te he enviado en esta sesion asi como tus respuestas y el razonamiento para llegar a ellas

7. > con base en esta bitacora, revisa la ejecucion de los promts y termina la ejecucion del promt 3

## Respuestas anteriores conservadas como resumen

La historia resumida informa que se distribuyeron 14 contenedores entre Core IMS, Base de Datos y Core IVR+VoiceMail, y se añadió al CSV la columna `COMPONENTES MAQUETA-3`. [DOC]

La historia resumida informa que, en una comprobación anterior, las tres URL de DEV en el puerto 8090 respondían y la interfaz mostraba 14/14 contenedores; en ese momento había 4/5 listeners SIP activos, con FreeSWITCH sin listener. Es un resultado histórico, no el estado final de esta bitácora. [DOC]

La historia resumida informa que el acceso VPN/SSH a los servidores falló en una etapa previa y que por eso quedaron pendientes las reparaciones y validaciones remotas. El usuario indicó después que la VPN se había restablecido. [DOC]

## Resumen de respuestas de progreso recuperables de esta continuación

Se indicó que se continuaría el diagnóstico remoto, integrando el problema de autenticación/seguridad IMS con la configuración en los tres nodos DEV. [INFERENCE]

Se indicó que el estado de cierre dependería de verificar el contrato E2E y no de suponer que una interfaz accesible implicaba funcionamiento IMS. [DOC]

Se comunicó que la UI proxy-aware respondía por los accesos de los tres hosts y podía consultar 14/14 contenedores; a continuación se ejecutó el E2E. [CODE]

Se comunicó que el primer E2E tuvo fallos en DNS, registro de UE, llamada, IVR y VMS, aunque los contenedores y cinco listeners SIP aparecían activos. [CODE]

Se comunicó que el diagnóstico detectó que la IP de P-CSCF configurada no coincidía con la VIP DNS observada y que la IP de tarea era distinta de ambas. [CONFIG]

Se comunicó que se añadiría diagnóstico de registro con cabeceras de autenticación redactadas y se prepararían pruebas locales antes de modificar el servicio. [INFERENCE]

Se comunicó que el usuario recibió un reto `401` desde el P-CSCF, pero no se observaba un registro exitoso `200`; por ello, no se declaró resuelto el E2E. [CODE]

Se comunicó que el P-CSCF escribía en logs la cabecera `WWW-Authenticate` completa y se retiró ese log de la configuración fuente; luego se validó la sintaxis Kamailio y se recargó el servicio. [CODE]

Se comunicó que una actualización de UI comparó el DNS con la VIP del servicio, mientras el cliente UE probó contra la IP de tarea del P-CSCF para que coincidiera con el extremo de las políticas IPsec. [CODE]

Se comunicó que las SA y políticas IPsec aparecían instaladas en el UE, pero que los contadores de tráfico seguían en cero; no se afirmó que el registro estuviera completado. [CODE]

## Resumen de decisiones y evidencias

| Decisión | Evidencia observada | Resultado |
|---|---|---|
| Reanudar el trabajo remoto tras el aviso de VPN restablecida. | La sesión consiguió ejecutar comandos SSH y consultar Docker en `192.168.5.231` y `192.168.5.233`. [CONFIG] | Se reanudó la inspección de DEV. [INFERENCE] |
| Corregir la ruta Docker de la UI para Swarm y añadir pruebas de esa búsqueda. | La UI en Swarm necesitaba consultar contenedores distribuidos entre proxies de Core, Base de Datos e IVR. [CODE] | Se preparó y desplegó una imagen UI con tests ejecutados dentro de la imagen de DEV. [CODE] |
| Comparar la resolución DNS con la VIP real del servicio, no con una IP antigua fija. | El dominio IMS y el alias `mims3_pcscf` resolvieron a `172.32.0.3`; la IP de la tarea P-CSCF observada fue `172.32.0.133`. [CONFIG] | La UI reportó DNS esperado `172.32.0.3`; el contrato DNS dejó de fallar por el valor estático anterior. [CODE] |
| Enviar el UE a la IP de tarea del P-CSCF, separándola de la VIP usada por DNS. | La VIP observada fue `172.32.0.3`, la IP de tarea P-CSCF observada fue `172.32.0.133` y la IP del UE fue `172.32.0.15`. [CONFIG] La fuente reportada para las políticas XFRM era `172.18.0.3`, discrepante de la dirección real observada del UE. [CONFIG] | Se probó el envío a `172.32.0.133`, pero el `REGISTER` autenticado no llegó a completar el diálogo. [CODE] |
| Eliminar la escritura de material de desafío AKA en el log del P-CSCF. | La configuración anterior registraba la cabecera completa `WWW-Authenticate`; la nueva reemplazó ese log por un mensaje no sensible. [CODE] | La configuración pasó la comprobación `kamailio -c`; el servicio P-CSCF se actualizó con la nueva configuración. [CODE] |
| No dar por resuelto el registro usando solo el primer `401`. | El registro controlado obtuvo `100 Trying` y `401 Unauthorized`; los intentos posteriores del segundo `REGISTER` no recibieron `200`, y los contadores XFRM observados quedaron en cero. [CODE] | IMS-AKA/IPsec, llamadas y Feature 2 continúan sin validación E2E aprobada. [INFERENCE] |

## Revisión de la ejecución de los prompts (prompt 7)

| Prompt | Estado antes del prompt 7 | Estado al cierre |
|---|---|---|
| 1 — repartir componentes en 3 servidores y columna en el CSV | Hecho (columna `COMPONENTES MAQUETA-3`). [DOC] | Sin cambios. [CONFIG] |
| 2 — despliegue en DEV y URL E2E | Hecho: `http://192.168.5.231|232|233:8090`. [DOC] | Responden HTTP 200 los tres. [CODE] |
| 3 — reparar fallas (captura 8/14) y ejecutar `context-X.txt` | Incompleto: registro IMS fallaba tras el `401`; sin pcap, sin commit. [DOC] | Ver tabla siguiente. [CODE] |
| 4–5 — continuar | Continuación del 3. [DOC] | Cerrado con el prompt 7. [INFERENCE] |
| 6 — bitácora | Hecho. [DOC] | Actualizada con esta sección. [CODE] |

### Prompt 3 / `context-X.txt` al cierre

| Paso | Resultado | Evidencia |
|---|---|---|
| Fallas de la captura | UI E2E **14/14** (antes 6/14) dos veces seguidas. [CODE] | `POST /api/test` en `192.168.5.233:8090` |
| 1) Señalización 3GPP, autenticación y seguridad | IMS-AKA (RES/AUTN verificados con Milenage) e IPsec ESP (97 ICV válidos) cumplen en DEV. [CODE] | `entregables-feat-02/03_iteraciones/iter-31-dev-swarm-final/check_3gpp.md` |
| 2) Feature 2 | Los 5 checks FEAT-02 pasan en DEV (depósito por iFC no registrado, buzón, MWI yes/no, PIN). [CODE] | `iter-31-dev-swarm-final/test_maqueta.log` (22/22) |
| 3.a) tcpdump → tshark → 3GPP hasta reparar | 2 iteraciones de captura; **27/28 reglas**. Falla solo G3 (RFC 3261 §18.1.1): la overlay de Swarm hereda MTU 1450 y las peticiones UDP > 1250 B se fragmentan. No se puede corregir sin jumbo frames en la red física del hipervisor o SIP/TCP en Gm. [CODE] | `03_iteraciones/BITACORA_ITERACIONES.md` (pasos D1–D11, iter-30/31) |
| 3) commit + push a la rama | Commit `ab2958f` en `feature/feat-02`. **Push rechazado**: la clave SSH local autentica como `jhordy-amaris`, sin permiso en `jhordyabonia/hacom-ivr`. [CODE] | `git log -1`, salida de `git push` |
| 4) Cronograma/PMV y tutorial en pptx | Deck de avance actualizado con el estado DEV; tutorial regenerado sin cambios de contenido. [CODE] | `04_presentaciones/FEAT-02_avance_PMV_ruta_DEV.pptx` (+ PDF) |
| 5) Entregables ordenados | `entregables-feat-02/` con README actualizado. [CODE] | `entregables-feat-02/README.md` |

### Causas raíz corregidas en DEV (resumen)

1. pjsua y FreeSWITCH tomaban la IP de `docker_gwbridge` (ruta por defecto) en vez de la overlay. [CODE]
2. El P-CSCF instalaba las SA IPsec sobre la VIP de Swarm; ESP no atraviesa IPVS. [CODE]
3. MSISDN `0100001` en el entorno del softphone frente a `0010100001` en el HSS (SAR fallaba). [CONFIG]
4. S-CSCF y AS-Front sin socket en la red ISC/IMS respectivamente; añadido `mhomed=1`. [CODE]
5. El DNS embebido de Docker no tiene el SRV del dominio → el S-CSCF enviaba al P-CSCF los destinos terminantes. [CODE]
6. `docker restart` sobre tareas Swarm dejó 3 FreeSWITCH tras la misma VIP; eliminados los huérfanos. [CODE]
7. El AS-Front no hacía Record-Route; el NOTIFY MWI iba a una red inalcanzable para FreeSWITCH. [CODE]
8. Archivos locales truncados a 0 bytes (`docker-compose.swarm.yml`, `patch_ims_aka.py`, `docker_swarm_lib.sh`, `.env.swarm`): recuperados desde DEV o reconstruidos. [CODE]

## Estado verificado al cerrar esta bitácora

- DEV: 17 servicios del stack `mims3` 1/1, sin contenedores huérfanos; UI `mims3_ui:feature2-ui-fix-v5-20261014`. [CONFIG]
- `SWARM_MODE=1 bash maqueta-ims-3/scripts/test_maqueta.sh` → **22/22** (el contrato creció de 15 a 22 checks con FEAT-01/02). [CODE]
- Captura DEV → **27/28 reglas 3GPP**; regla abierta G3 por MTU de infraestructura. [CODE]
- Pendientes del usuario: push con la cuenta con permisos; decidir jumbo frames en la red DEV; acceso de softphones externos (el P-CSCF no se publica fuera de la overlay). [INFERENCE]
- Copias de seguridad de configuración previa en DEV: `*.pre-v3-20261014` y `*.pre-v5-20261014` en `~/maqueta-ims-3` de los nodos. [CONFIG]

## Estado previo a la continuación del prompt 7 (histórico)

- El repositorio está en `feature/feat-02` y ya contenía modificaciones de trabajo previas a esta actualización. No se hizo commit ni push en esta continuación. [CONFIG]
- En DEV, la UI activa era `mims3_ui:feature2-ui-fix-v4-20261014`; el servicio mostraba política de rollback y estado de actualización completado. [CONFIG]
- Las tres URL de DEV en puerto 8090 respondieron durante los smoke tests; `/api/status` mostró 14/14 contenedores y 5/5 listeners SIP activos. [CONFIG]
- `/api/status` mostró el dominio IMS resolviendo a la VIP observada `172.32.0.3`, aunque la variable de configuración antigua indicaba `172.32.0.8`. [CONFIG]
- El registro IMS de UE1 todavía fallaba después de recibir el reto inicial `401`; no se comprobó `200 OK` ni `Service-Route`. [CONFIG]
- Se observaron políticas y estados IPsec instalados en el cliente, pero sin contadores de paquetes distintos de cero en la consulta realizada. [CONFIG]
- No se completó la captura entregable `.pcap`, el filtrado `tshark` ni el análisis 3GPP de 100% de compatibilidad solicitados en `context-X.txt`. [DOC]
- El test completo de la maqueta no se cerró como aprobado; por ello no se reporta finalización de Feature 2, commit ni push. [INFERENCE]

## Archivos relevantes

- [context-X.txt](../context-X.txt) — instrucciones del trabajo solicitado. [DOC]
- [app.py](../maqueta-ims-3/interfaz/app.py) — lógica de UI, acceso Docker Swarm y diagnósticos de registro. [CODE]
- [test_app.py](../maqueta-ims-3/interfaz/test_app.py) — pruebas focalizadas de la interfaz. [CODE]
- [register.cfg](../maqueta-ims-3/pcscf/route/register.cfg) — respuesta del P-CSCF al registro y sanitización del reto AKA. [CODE]
- [ue.sh](../maqueta-ims-3/softphone/scripts/ue.sh) — lanzamiento de UE IMS y destino P-CSCF. [CODE]
- [test_maqueta.sh](../maqueta-ims-3/scripts/test_maqueta.sh) — contrato E2E declarado para la maqueta. [CODE]
