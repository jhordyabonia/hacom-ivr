# Manual 3.0 — Conexión de dispositivos Android externos a la maqueta IMS (DEV)

**Versión:** 3.0 · 2026-10-27  
**Sustituye a:** `Manual_2.0_conexion_externa_Redmi_13.md`, escrito antes de habilitar el acceso externo.  
**Validado con:**
- Redmi 13 (Android 15, HyperOS 2.0);
- OpenVPN for Android;
- Linphone 6.2.9;
- abonado de prueba UE3 `0010100009`.

**Base técnica:** commits `881dbd0`, `7919444`, `124a62e` y `67d233e` de `feature/dev`. [CODE]

> **Seguridad.** Este manual no contiene contraseñas, claves ni certificados.
> - Las credenciales de la VPN, los archivos del perfil y la contraseña SIP de cada dispositivo se entregan por un canal privado autorizado.
> - Nunca se envían por chat ni por correo abierto, y nunca se guardan en documentos compartidos.

---

## 1. Qué se consigue y cómo funciona

Al terminar este manual, el teléfono:
- se registra en el núcleo IMS de la maqueta como un abonado más;
- llama al IVR (`0100002`), donde además deja mensajes de voz, y al buzón (`0100003`), donde los escucha o los borra;
- recupera su buzón personal (`0100004`).

El camino de la conexión es este:

```text
Android ──OpenVPN (UDP 1195)──► ltc.hacom.com.pe ──► red 192.168.5.0/24 (DEV)
   │
   ├─ SIP  (TCP 5060) ─► P-CSCF publicado en 192.168.5.231 ─► I-CSCF/S-CSCF ─► HSS
   │                                                        └► AS / FreeSWITCH (IVR, VMS)
   ├─ RTP  (UDP 49900–49999) ─► RTPEngine en 192.168.5.231 ─► FreeSWITCH (192.168.5.233)
   └─ Web  (TCP 8090) ─► Interfaz de la maqueta en 192.168.5.233
```

Puntos clave: [CONFIG]
- **Autenticación:** el teléfono usa **SIP Digest (MD5)**, el perfil «no-3GPP» de la maqueta, no IMS-AKA/IPsec. Los UE internos de la maqueta siguen usando IMS-AKA sin cambios.
- **Contraseña SIP:** es la **Ki** que el HSS tiene para ese abonado. La entrega el administrador.
- **Transporte:** obligatoriamente **TCP**. Por UDP, los mensajes SIP grandes se pierden en la VPN y la llamada da `408`.
- **Audio:** todo pasa por RTPEngine en `192.168.5.231`, puertos UDP 49900–49999. El teléfono no necesita abrir puertos.

---

## 2. Requisitos previos

| Requisito | Detalle | Quién lo provee |
|---|---|---|
| Teléfono Android | Android 10 o superior, con Google Play | Usuario |
| Perfil VPN propio | Archivos `.ovpn`, `.p12` y `-tls.key`, más usuario y contraseña de VPN | Administrador de red Hacom |
| Abonado IMS propio | MSISDN, dominio y contraseña SIP (Ki) | Administrador de la maqueta (§9) |
| Red del teléfono | Wi-Fi o datos móviles con salida a Internet por UDP 1195 | Usuario |

> **Un perfil VPN por dispositivo.** Si el teléfono y un PC usan el **mismo** perfil VPN, solo uno puede estar conectado a la vez: al conectar uno se cae el otro, porque el servidor admite una sola sesión por perfil. Para trabajar con el PC y el teléfono al mismo tiempo, pide un perfil para cada equipo. [CONFIG]

---

## 3. Paso 1 — Instalar las aplicaciones

1. En Google Play instala **OpenVPN for Android**, de *Arne Schwabe*.
2. En Google Play instala **Linphone**, de *Belledonne Communications*. Versión validada: 6.2.9.
3. No instales APK de otras fuentes.

---

## 4. Paso 2 — Configurar y conectar la VPN

### 4.1 Copiar los archivos del perfil

1. Recibe por el canal privado los tres archivos del perfil:
   - `<perfil>-config.ovpn`
   - `<perfil>.p12`
   - `<perfil>-tls.key`
2. Cópialos al teléfono, en la misma carpeta (por ejemplo `Descargas/vpn`), por cable USB o por un almacenamiento privado.
3. No los reenvíes por WhatsApp, Telegram ni correo.

### 4.2 Importar el perfil

1. Abre **OpenVPN for Android** y toca el botón **+** (o el icono de importar).
2. Elige **Importar** y selecciona `<perfil>-config.ovpn`.
3. Si la aplicación pide el certificado `.p12` o la clave TLS, selecciona los archivos de la misma carpeta.
4. Comprueba los datos del servidor: `ltc.hacom.com.pe`, puerto **1195**, protocolo **UDP**.
5. Guarda el perfil con un nombre reconocible, por ejemplo «Hacom DEV».

### 4.3 Conectar

1. Toca el perfil. Android pregunta si permites que la aplicación cree una conexión VPN: toca **Aceptar**.
2. Escribe el usuario y la contraseña de la VPN, y la contraseña del certificado si la pide.
3. Espera el estado **Conectado**, con la llave de VPN en la barra de estado.

> Si aparece un diálogo de «control por aplicación externa» que no esperabas, **cancélalo**. Ninguna aplicación de este procedimiento lo necesita. [CONFIG]

### 4.4 Ajustes recomendados de Android

- **Batería:** en *Ajustes → Aplicaciones → OpenVPN y Linphone → Ahorro de batería*, elige **Sin restricciones**. HyperOS/MIUI cierra las aplicaciones en segundo plano y el teléfono deja de recibir llamadas.
- **Inicio automático (HyperOS/MIUI):** activa *Inicio automático* para las dos aplicaciones.

### 4.5 Comprobar el acceso

Con la VPN conectada, abre Chrome y entra en **http://192.168.5.233:8090/**.

- **Si carga la interfaz de la maqueta**, la VPN llega a DEV. Continúa con el paso 3.
- **Si no carga:**
  1. comprueba que OpenVPN sigue en **Conectado**;
  2. desconecta y vuelve a conectar;
  3. cambia entre Wi-Fi y datos móviles;
  4. revisa que ningún otro equipo use el mismo perfil (§2).

---

## 5. Paso 3 — Datos de la cuenta SIP

Pide al administrador tu ficha de abonado. Tiene esta forma (los valores de ejemplo son los de UE3):

| Dato | Ejemplo (UE3) | Comentario |
|---|---|---|
| Número (MSISDN) | `0010100009` | Será tu usuario SIP |
| Dominio | `ims.mnc001.mcc001.3gppnetwork.org` | Igual para todos |
| ID de autenticación | `0010100009@ims.mnc001.mcc001.3gppnetwork.org` | **MSISDN@dominio**; no uses el IMSI |
| Contraseña SIP | *(se entrega por canal privado)* | Es la Ki del abonado en el HSS |
| Servidor / proxy | `192.168.5.231`, puerto `5060` | P-CSCF publicado |
| Transporte | **TCP** | No uses UDP |

---

## 6. Paso 4 — Configurar Linphone

Hay dos métodos. Usa el **A (aprovisionamiento remoto)** cuando el administrador te dé un enlace o un código QR: aplica todos los ajustes de golpe, incluido uno que no aparece en los menús. Si no, usa el **B (manual)**.

### 6.A Aprovisionamiento remoto (recomendado)

1. Abre Linphone. En el asistente inicial, o en *Menú → Asistente*, elige **Obtener configuración remota** (o *Escanear código QR*).
2. Pega la URL o escanea el QR que te dio el administrador. La URL debe ser accesible por la VPN y de un solo uso.
3. Acepta. Linphone se reinicia con la cuenta ya creada.
4. Si la plantilla no incluye la contraseña, Linphone la pide en el primer registro.
5. Continúa en el paso 5 (§7).

La plantilla de aprovisionamiento está en el anexo A.

### 6.B Configuración manual

1. Abre Linphone y acepta los permisos de **micrófono**, **notificaciones** y **teléfono**.
2. En el asistente elige **Usar una cuenta SIP** (cuenta SIP de terceros). Acepta el aviso de que no es una cuenta de Linphone.
3. Completa los campos:
   - **Nombre de usuario:** tu MSISDN, por ejemplo `0010100009`.
   - **ID de autenticación:** `MSISDN@ims.mnc001.mcc001.3gppnetwork.org`.
   - **Contraseña:** la contraseña SIP recibida.
   - **Dominio:** `ims.mnc001.mcc001.3gppnetwork.org`.
   - **Nombre visible:** el que quieras, por ejemplo «Redmi Juan».
   - **Transporte:** **TCP**.
4. En **Avanzado** (o, después, en *Cuenta → Parámetros*):
   - **Proxy de salida / Servidor proxy:** `sip:192.168.5.231:5060;transport=tcp`.
   - **Enrutar todas las llamadas por el proxy (outbound proxy):** activado.
   - **Caducidad del registro:** `600` s.
   - **AVPF:** desactivado.
   - **Publicar presencia:** desactivado.
   - **Prefijo internacional / convertir «+»:** desactivado, porque los números de la maqueta no llevan «+».
5. En *Ajustes → Red*:
   - **STUN/ICE:** desactivado.
   - Si existe la opción de mantener el Contact sin reescribirlo por NAT, déjala desactivada (equivale a `enable_nat_helper=0`).
6. En *Ajustes → Audio*, deja activados **PCMU (G.711 µ-law)** y **PCMA**. Los demás códecs pueden quedar activos: RTPEngine y FreeSWITCH negocian G.711.
7. Guarda los cambios.

> **Ajuste crítico (QA-05):** si Linphone reescribe su Contact con la dirección NAT de la VPN, el registro sale bien pero **las llamadas fallan con `403 Forbidden – You must register first with a S-CSCF`**. La solución es `enable_nat_helper=0` en la sección `[net]`. Si tu versión no muestra esa opción en los menús, usa el método A. [CODE]

---

## 7. Paso 5 — Verificar el registro

1. Abre el menú lateral de Linphone. La cuenta debe aparecer en **Conectado / Registrado**, con el punto verde.
2. Si falla, consulta la tabla de §10 antes de cambiar nada.
3. (Opcional) El administrador puede confirmar el registro en la interfaz web, en la pestaña *Estado*, o en los logs del P-CSCF y del S-CSCF.

---

## 8. Paso 6 — Pruebas de llamada

Haz las pruebas en este orden. Marca los números **exactos**: tienen 7 dígitos y empiezan por `01000`.

| # | Marca | Qué debe pasar | Cómo se comprueba |
|---|---|---|---|
| 1 | `0100002` y marca una opción | Contesta el **IVR**: suena la bienvenida (unos 9 s) y después el menú DTMF (1 saldo, 2 ayuda, 9 colgar) | Lo oyes. Pulsa una opción del menú: debe responder |
| 2 | `0100002` (dejar mensaje) **sin marcar nada** | Tras la bienvenida y el menú, a los 3 s: «Para dejar un mensaje de voz, hable después del tono». Suena un **tono**; habla y cuelga (la grabación también se corta tras 7 s de silencio) | En la web, pestaña **VMS**, buzón `0100003`: tu mensaje aparece y se reproduce con tu voz |
| 2b | `0100003` y marca **1** (escuchar) | Menú «Buzón de voz. Para escuchar sus mensajes, marque uno…». Con **1** se oyen **todos** los mensajes, del más reciente al más antiguo, separados por «Siguiente mensaje», y al final «No hay más mensajes»; luego vuelve al menú | Oyes el mensaje que dejaste en la prueba 2 |
| 2c | `0100003` y marca **3** (contraseña) | «La contraseña del buzón todavía no está disponible» y vuelve al menú (solo existe la entrada del menú) | Lo oyes |
| 2d | `0100003` y marca **2** (borrar) — **opcional** | «Todos sus mensajes han sido borrados» y vuelve al menú. **Borra todos los mensajes del buzón compartido, sin confirmación** | La pestaña **VMS** muestra el buzón `0100003` vacío |
| 3 | `00101xxxxx` (un abonado **no registrado**) | La llamada se desvía al buzón personal de ese abonado. Deja un mensaje | El dueño del buzón lo recupera en la prueba 4. Si está suscrito, recibe aviso de mensaje en espera (MWI) |
| 4 | `0100004` | Recuperación del buzón **propio**: pide un PIN de 4 dígitos y luego 1 = escuchar; tras escuchar, 7 = borrar, 2 = guardar, # = siguiente | Solo funciona si tu número tiene PIN dado de alta (§9). Tras **5 PIN erróneos en 15 min** el buzón se bloquea 15 minutos |

Para que la llamada sea correcta: [CODE]
- se oye audio en los dos sentidos;
- la grabación del buzón dura lo que hablaste;
- en la web, el tamaño del mensaje es mayor de 44 bytes (44 bytes es una cabecera WAV sin audio).

> El audio se graba en WAV G.711 de 8 kHz. Cada mensaje se guarda como `msg_AAAAMMDD_HHMMSS_<uuid>.wav`, así que dos mensajes del mismo segundo no se pisan (QA-10). [CODE]

---

## 9. Para el administrador — alta de un dispositivo nuevo

Haz estos pasos una vez por teléfono. **No reutilices** el abonado ni la contraseña de otro dispositivo.

1. **Perfil VPN propio.** Solicítalo a redes. Comparte los archivos y las credenciales solo por canal privado.
2. **Abonado en el HSS (PyHSS):**
   - asigna un IMSI `00101…` y un MSISDN `00101xxxxx` libres;
   - genera una **Ki aleatoria** de 32 caracteres hexadecimales;
   - usa la iFC `maqueta_ifc.xml`;
   - aplica el mismo alta que `scripts/stress/provision_load_ues.py` o la pestaña *Configuración* de la UI.
   La Ki es la contraseña Digest del teléfono. [CODE]
3. **PIN de buzón (opcional, para `0100004`):** inserta la fila del MSISDN en `vas.subscriber_pin` con el PIN en la columna `pin`. La UI lo convierte en hash PBKDF2 al arrancar, vacía la columna `pin`, y `/api/pin` ya no expone el valor (QA-12). [CODE]
4. **Comprobar los requisitos del servidor** (ya aplicados en DEV): [CONFIG]
   - `NON3GPP_DIGEST=1` en S-CSCF;
   - P-CSCF publicado en 5060 TCP/UDP con `advertise 192.168.5.231`;
   - RTPEngine con la interfaz `ext` en 49900–49999 y `offer-timeout=60`.
5. **Entregar la ficha** de §5 y, si se usa, la URL o QR de aprovisionamiento (anexo A). Borra el archivo de aprovisionamiento del servidor después de que el teléfono lo descargue.
6. **Baja:**
   - borra el abonado del HSS y su PIN;
   - revoca el perfil VPN.

**Capacidad:** el S-CSCF admite hasta **5 contactos** por abonado (`max_contacts=5`). Varios teléfonos con el mismo abonado funcionan, pero no es recomendable. [CODE]

---

## 10. Solución de problemas

| Síntoma | Causa probable | Solución |
|---|---|---|
| OpenVPN no pasa de «Conectando» | Credenciales, certificado o red que bloquea UDP 1195 | Revisa las credenciales; prueba con datos móviles; pide a redes revisar el perfil |
| La VPN conecta pero se cae al rato, o se cae la del PC | El mismo perfil está activo en otro equipo | Usa un perfil por dispositivo (§2) |
| `http://192.168.5.233:8090` no carga | La VPN no está activa o no tiene la ruta a 192.168.5.0/24 | Reconecta la VPN; si sigue igual, pide revisar las rutas |
| Registro: `401` en bucle / *Authentication failed* | ID de autenticación incorrecto (IMSI en lugar de MSISDN@dominio) o contraseña errónea | Pon `MSISDN@dominio` como ID de autenticación; confirma la contraseña |
| Registro: `403` | El abonado no existe en el HSS o el perfil Digest está desactivado | El administrador revisa el alta (§9) |
| Registro o llamada: `408 Request Timeout` | Transporte **UDP** (mensajes grandes fragmentados en la VPN, QA-04) | Cambia el transporte a **TCP** |
| Llamada: `403 You must register first with a S-CSCF` | Linphone reescribió el Contact con la IP NAT (QA-05) o la llamada salió justo tras un cambio de red (QA-21) | `enable_nat_helper=0`, por aprovisionamiento remoto (§6.A). Desde el 2026-10-28 el P-CSCF espera hasta 3 s a que termine el registro tras un cambio de red; si aún aparece, espera a ver el punto verde y vuelve a llamar |
| Llamada: `407` y luego `403` | El servidor validaba las credenciales que Linphone añade al INVITE (QA-22) | Corregido en el servidor el 2026-10-28; no requiere cambios en el teléfono |
| La llamada se corta sola en menos de 1 s («0/null») | La VPN del teléfono se cortó o cambió de red durante la llamada | Comprueba que OpenVPN siga en **Conectado** y que ningún otro equipo use el mismo perfil (§2) |
| Llamada: `604 Does not exist anywhere` | Número mal marcado (por ejemplo `010002`) | Marca `0100002`, con 7 dígitos |
| La llamada conecta pero no hay audio, o el mensaje se graba vacío | Ruta RTP bloqueada o puertos de RTPEngine agotados (QA-07) | Verifica la VPN; el administrador revisa RTPEngine (49900–49999) |
| No recibe llamadas en segundo plano | Ahorro de batería de Android | Ver §4.4 |
| `0100004` rechaza un PIN correcto | Buzón bloqueado tras 5 fallos | Espera 15 min o pide al administrador que reinicie el contador |

---

## 11. Alcance y limitaciones

- **Qué valida:** una llamada desde Linphone valida el acceso SIP Digest, el enrutamiento IMS (P/I/S-CSCF, HSS, iFC), RTPEngine y los servicios IVR y VMS. **No** valida IMS-AKA, `sec-agree`, IPsec ni la conformidad 3GPP completa: eso lo cubre la prueba E2E `test_maqueta.sh` con los UE internos. [DOC]
- **Sin cifrado:** no hay SRTP ni TLS. La confidencialidad depende del túnel VPN.
- **Llamadas entrantes al teléfono (MT):** fuera del alcance validado.
- **Pendiente en el servidor:**
  - QA-04: SIP por UDP;
  - QA-05: soportar el Contact reescrito por NAT;
  - QA-18: sacar las Ki del repositorio.
  Detalle en `08_qa/INFORME_QA.md`.

---

## Anexo A — Plantilla de aprovisionamiento remoto de Linphone

Sustituye `MSISDN` y `NOMBRE`. La contraseña **no** se incluye: Linphone la pide en el primer registro. El administrador puede añadirla en un archivo de un solo uso que se borra tras la descarga. [CONFIG]

```xml
<?xml version="1.0" encoding="UTF-8"?>
<config xmlns="http://www.linphone.org/xsds/lpconfig.xsd">
  <section name="net">
    <entry name="enable_nat_helper">0</entry>
  </section>
  <section name="proxy_0">
    <entry name="reg_identity">"NOMBRE" &lt;sip:MSISDN@ims.mnc001.mcc001.3gppnetwork.org&gt;</entry>
    <entry name="reg_proxy">&lt;sip:192.168.5.231:5060;transport=tcp&gt;</entry>
    <entry name="reg_route">&lt;sip:192.168.5.231:5060;transport=tcp;lr&gt;</entry>
    <entry name="reg_expires">600</entry>
    <entry name="reg_sendregister">1</entry>
    <entry name="publish">0</entry>
    <entry name="avpf">0</entry>
    <entry name="dial_escape_plus">0</entry>
  </section>
  <section name="auth_info_0">
    <entry name="username">MSISDN</entry>
    <entry name="userid">MSISDN@ims.mnc001.mcc001.3gppnetwork.org</entry>
    <entry name="realm">ims.mnc001.mcc001.3gppnetwork.org</entry>
    <entry name="domain">ims.mnc001.mcc001.3gppnetwork.org</entry>
  </section>
</config>
```

Para publicarla:
1. Sírvela por HTTP **dentro de la VPN**.
2. Pasa la URL al teléfono como enlace `linphone-config:http://…` o como código QR.
3. Borra el archivo del servidor después de la descarga.

## Anexo B — Lista de comprobación rápida

- [ ] OpenVPN en **Conectado**, con un perfil exclusivo para este teléfono
- [ ] `http://192.168.5.233:8090` carga
- [ ] Linphone: usuario = MSISDN; ID de autenticación = MSISDN@dominio; transporte **TCP**; proxy `192.168.5.231:5060`
- [ ] `enable_nat_helper=0` (aprovisionamiento remoto)
- [ ] Cuenta **Registrada**
- [ ] `0100002`: se oye la bienvenida y el menú responde
- [ ] `0100002` sin marcar: tras el tono se graba; el mensaje aparece en la pestaña VMS y se reproduce
- [ ] `0100003` + `1`: se escuchan todos los mensajes por teléfono
- [ ] `0100003` + `3`: avisa que la contraseña aún no está disponible
- [ ] Batería sin restricciones para OpenVPN y Linphone
