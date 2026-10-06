# FEAT-02 — VMS completo (mod_voicemail + MWI + recuperación) · RFP F4

Estado: **LISTO** · rama `feature/feat-02` · E2E **22/22** · verificación 3GPP **27/27**.

## 1. Definición de hecho (de `results/features_a_agregar_maqueta.md`)

| Criterio | Evidencia (E2E `scripts/test_maqueta.sh`, PASO 6b) |
|---|---|
| UE1 deja mensaje en el buzón de UE2 (desregistrado) | `FEAT-02: llamada UE1 -> UE2 no registrado desviada al buzón` (iFC terminating-unregistered → `VMS_DEPOSIT id=0010100002`) y `FEAT-02: mensaje en buzón mod_voicemail de UE2` (`vm_boxcount 0 → 1`) |
| UE2 recibe MWI | `FEAT-02: MWI (SUBSCRIBE/NOTIFY message-summary) al UE2` (`Messages-Waiting: yes`) |
| UE2 recupera y borra el mensaje | `FEAT-02: recuperación con PIN (0100004), escucha y borrado` (`VMS_PIN ok; buzón 1 → 0`) y `FEAT-02: MWI actualizado tras borrar` (`Messages-Waiting: no`) |
| E2E +2 checks (MWI, recovery) | +5 checks FEAT-02 y +1 de SA IPsec: 15 base + 2 FEAT-01 → **22** |

## 2. Flujos (todos sobre IMS-AKA + IPsec en Gm)

```
Depósito (TS 24.604 CDIV → VMS)
UE1 ─INVITE→ P-CSCF ─→ S-CSCF(orig, sin iFC: no es nº de servicio) ─→ I-CSCF (LIR)
    ─→ S-CSCF(term): UE2 no registrado → SAR UNREGISTERED_USER → iFC P40 (SessionCase 2)
    ─ISC→ AS-Front ─→ FreeSWITCH: voicemail default <dominio> <MSISDN> (mod_voicemail)

MWI (TS 24.606)
UE2 ─SUBSCRIBE Event: message-summary→ P-CSCF ─→ S-CSCF(orig) ─iFC P10→ AS-Front ─→ FreeSWITCH (202)
FreeSWITCH ─NOTIFY (Messages-Waiting: yes/no)→ S-CSCF ─→ P-CSCF ─(SA ESP)→ UE2

Recuperación
UE2 ─INVITE 0100004→ … iFC P30 → FreeSWITCH: vm_pin.lua
    PIN (DTMF RFC 4733) validado contra vas.subscriber_pin (API UI :8888)
    1 = escuchar · 7 = borrar · 2 = guardar  (vm_list / vm_read / vm_delete de mod_voicemail)
    → evento MESSAGE_WAITING → NOTIFY Messages-Waiting: no
```

## 3. Cambios por componente

| Componente | Cambio |
|---|---|
| `pyhss/maqueta_ifc.xml` | iFC **P10** SUBSCRIBE+`Event: message-summary` (orig) → AS; **P30** INVITE a `sip:010000[2-4]@` (antes cualquier INVITE originado: secuestraba UE1→UE2); **P40** INVITE terminating-unregistered → AS |
| `scscf/kamailio_scscf.cfg` | SAR `UNREGISTERED_USER` para destino no registrado (la lógica estaba invertida); fuera el MWI no estándar (NOTIFY sin suscripción, entrega directa al contacto); IMS-AKA obligatorio; `timer_interval 5` de usrloc |
| `kamailio/Dockerfile` | Parche de `ims_isc`: SessionCase 2 cuando el IMPU no está registrado (comparaba el valor equivocado) |
| `asfront/kamailio_asfront.cfg` | Relay ISC también de SUBSCRIBE |
| `freeswitch/init.sh` + `conf/` | La configuración versionada se superpone al arrancar (antes la imagen tenía un dialplan obsoleto); arranque sin diálogos SIP persistidos |
| `freeswitch/conf/directory/ims.xml` | Buzón `mod_voicemail` por MSISDN |
| `freeswitch/conf/dialplan/public.xml` | Depósito con `voicemail default` (antes `record` a un directorio que mod_voicemail no indexa; regex de 11 dígitos para MSISDN de 10) |
| `freeswitch/conf/sip_profiles/external.xml` | `manage-presence` (MWI), `auth-subscriptions=false` (ya autenticado por el core), `force-subscription-expires=60`, alias del dominio IMS |
| `freeswitch/scripts/vm_pin.lua` | PIN de 4 dígitos (antes 1), API en `:8888` (antes :80), menú escuchar/borrar sobre la API de mod_voicemail y publicación de MWI |
| `scripts/test_maqueta.sh` | UEs con `ue.sh` (AKA+IPsec), des-registro real de UE2, MWI por SUBSCRIBE, DTMF `#`+`5678`, borrado tras la reproducción, paso 0 de estado limpio |
| Eliminados | `scripts/deregister_ue2.py` (Digest MD5) y `freeswitch/scripts/mwi_notify.sh` (NOTIFY no solicitado) |

## 4. Pendientes conocidos (fuera del alcance de FEAT-02)

- Desvío por **ocupado / no contesta** (CFB/CFNR) al buzón: hoy solo *no registrado*.
- Prompts de voz del buzón: la imagen de FreeSWITCH no incluye los de `mod_voicemail`
  (por eso el menú es propio en Lua). Para DEV, añadir el paquete de sonidos
  `en-us-callie`/`es` o grabaciones propias.
- Cambio de PIN desde el teléfono (hoy por la UI/API).
