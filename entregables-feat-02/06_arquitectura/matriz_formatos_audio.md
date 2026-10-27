# Matriz de formatos de audio — Almacenamiento de buzón de voz e IVR (FEAT-02 VMS)

> Proyecto: maqueta IMS/FreeSWITCH — RFP uVAS 2026 · Fecha: 2026-10-26
> Alcance: análisis **solo a base de conocimiento**. No se ha ejecutado ninguna prueba, conversión de audio ni cambio en la maqueta. Todo lo que se marca como «a validar» sigue pendiente de verificar. [ASSUMPTION]

## 0. Ficha de routing (protocolo amaris-harness)

| Campo | Valor |
|---|---|
| Paráfrasis | Elegir el formato de almacenamiento de mensajes de voz que mejor equilibre calidad y espacio en disco para una operación IMS de cientos de miles de buzones, y dejar la matriz que justifica la decisión. |
| Modo | Análisis / arquitectura (documental, sin ejecución). |
| Supuestos | Carga: 300 000 buzones, 500 000 mensajes/día, 30 s de media, retención de 30 días. [ASSUMPTION] |
| Huecos | Versión exacta de FreeSWITCH y librerías en DEV (libopusenc, libsndfile), política legal de retención y perfil real del tráfico (porcentaje NB y WB). [ASSUMPTION] |
| Perfil | amaris (por defecto). [CONFIG] |
| Skill | Ninguna específica: es un entregable documental de arquitectura. [INFERENCE] |
| Plan | Matriz → dimensionamiento → criterios de descarte → implementación de alto nivel → riesgos y validaciones → referencias. |
| Gate | Existencia de este archivo en `entregables-feat-02/06_arquitectura/`. [CONFIG] |

---

## 1. Resumen ejecutivo

**Recomendación: almacenar los mensajes de voz en Opus, en contenedor Ogg (`.opus`), mono, 16 kbit/s VBR, a la frecuencia nativa de la llamada (8 kHz si entra en NB, 16 kHz si entra en WB), con tramas de 20 ms y `application=voip`.**

- Ocupa 120 KB/min frente a 960 KB/min del WAV PCM16 8 kHz actual: **8 veces menos (−87,5 %)**. Con la carga supuesta, la retención de 30 días pasa de 7,2 TB a 0,9 TB. [INFERENCE] (cálculo en §3)
- El RFC 6716 sitúa la voz WB en 16–20 kbit/s y la voz NB en 8–12 kbit/s. Con 16 kbit/s cubrimos el tráfico G.711 (NB) con margen y no recortamos el WB de VoLTE (AMR-WB), G.722 y Opus. [DOC]
- Es libre de regalías (IETF, licencia BSD), funciona en los navegadores modernos y en Android, y los motores STT lo aceptan directamente. [DOC]
- FreeSWITCH lo reproduce con `mod_opusfile`. Para grabar directamente en `.opus` se necesita `mod_opusfile` compilado con `libopusenc`, algo que hay que validar. Mientras tanto, la vía segura es grabar en WAV y transcodificar de forma asíncrona (§5). [INFERENCE]
- Los prompts del IVR se quedan en WAV PCM16 (8 kHz y 16 kHz) o en formato nativo G.711: son pocos archivos y así no hay coste de CPU al reproducirlos. [INFERENCE]

---

## 2. Matriz comparativa

Fórmulas: **KB/min = bitrate (kbit/s) / 8 × 60** · **GB por 1 M min = KB/min × 10⁶ / 10⁶ = KB/min** (en unidades decimales, KB = 10³ B y GB = 10⁹ B, el valor numérico coincide). Las cabeceras se desprecian. [INFERENCE]

Anchos de banda: NB = 300–3400 Hz (fs 8 kHz) · WB = 50–7000 Hz (fs 16 kHz) · SWB = 50–14 000 Hz (fs 32 kHz). [DOC]

Calidad: los valores **Ie** (factor de degradación del equipo del E-model) proceden de ITU-T G.113, Apéndice I. Cuanto más bajo, mejor; G.711 es la referencia NB con Ie = 0. Las escalas NB y WB **no son comparables entre sí**. [DOC]

La matriz se divide en dos tablas (2A: métricas · 2B: operación), unidas por la columna «ID», para que se pueda leer.

### 2A. Métricas de tamaño y calidad

| ID | Formato | Bitrate (kbit/s) | Banda | Calidad perceptual orientativa | KB/min | GB / 1 M min |
|---|---|---|---|---|---|---|
| 1 | WAV PCM16 8 kHz mono (actual) | 128 | NB | Sin pérdida respecto a un origen G.711; es la referencia NB [INFERENCE] | 960 | 960 |
| 2 | WAV PCM16 16 kHz mono | 256 | WB | Sin pérdida; solo aporta algo si el origen es WB [INFERENCE] | 1 920 | 1 920 |
| 3 | G.711 µ-law/A-law (WAV) | 64 | NB | Ie = 0; MOS típico ≈ 4,1–4,4 [DOC] | 480 | 480 |
| 4 | G.722 (64k) | 64 (48/56) | WB | Referencia WB clásica; MOS-WB alto [DOC] | 480 | 480 |
| 5 | G.729 / G.729A | 8 | NB | Ie = 10 / 11 (≈ MOS 3,9) [DOC] | 60 | 60 |
| 6 | GSM 06.10 (FR) | 13 | NB | Ie = 20 (≈ MOS 3,5–3,7) [DOC] | 97,5 | 97,5 |
| 7 | AMR-NB 12.2 | 12,2 (12,8 en archivo .amr) | NB | Ie ≈ 5, equivalente a GSM-EFR [DOC] | 91,5 (96 en .amr) | 91,5 (96) |
| 8 | AMR-WB 12.65 | 12,65 (13,2 en .awb) | WB | Equivalente a G.722 64k según la caracterización de 3GPP (TR 26.976) [DOC] | 94,9 (99 en .awb) | 94,9 (99) |
| 9 | AMR-WB 23.85 | 23,85 (24,4 en .awb) | WB | Algo por encima de 12.65; mejora marginal para voz [INFERENCE] | 178,9 (183 en .awb) | 178,9 (183) |
| 10 | Opus 8 kbit/s (Ogg) | 8 | NB | Adecuado para voz NB, con artefactos audibles [DOC RFC 6716 §2.1.1 / INFERENCE] | 60 | 60 |
| 11 | Opus 12 kbit/s (Ogg) | 12 | NB (MB) | Prácticamente transparente frente a un origen G.711 [INFERENCE] | 90 | 90 |
| 12 | **Opus 16 kbit/s (Ogg)** | 16 | WB | Rango WB recomendado por el RFC; ≥ AMR-WB 12.65 en tests de escucha públicos [DOC / INFERENCE] | **120** | **120** |
| 13 | Opus 24 kbit/s (Ogg) | 24 | WB/SWB | Muy alta para voz; sobredimensionado si el origen es NB [INFERENCE] | 180 | 180 |
| 14 | MP3 16 kbit/s mono | 16 | NB (fs 8 kHz, MPEG-2.5) | Pobre: suena metálico y con pre-eco [INFERENCE] | 120 | 120 |
| 15 | MP3 32 kbit/s mono | 32 | ≈ WB (fs 16 kHz) | Aceptable, claramente inferior a Opus 16 [INFERENCE] | 240 | 240 |
| 16a | AAC-LC 32 kbit/s mono | 32 | WB | Buena, aunque es un códec genérico, no de voz [INFERENCE] | 240 | 240 |
| 16b | HE-AAC v1 16 kbit/s mono | 16 | WB (SBR) | Su SBR está afinado para música; en voz es irregular [INFERENCE] | 120 | 120 |
| 17 | FLAC 8 kHz mono | ≈ 60–80 (variable) | NB | Sin pérdida (idéntico al PCM) [DOC] | ≈ 450–600 [INFERENCE] | ≈ 450–600 |
| 18a | Speex NB 8 kbit/s | 8 | NB | Inferior a Opus a igual bitrate; Xiph lo declaró obsoleto en favor de Opus [DOC] | 60 | 60 |
| 18b | Speex WB 16,8 kbit/s | 16,8 | WB | Inferior a Opus 16 [INFERENCE] | 126 | 126 |

Notas sobre la tabla 2A:
- AMR (filas 7–9): el bitrate que se guarda en archivo (RFC 4867, almacenamiento) es algo mayor que el del códec, porque cada trama de 20 ms lleva 1 byte de cabecera y se rellena hasta completar el byte. Por ejemplo, AMR-WB 12.65 ocupa 33 B por trama de 20 ms, es decir, 13,2 kbit/s. [DOC]
- Ogg Opus: la sobrecarga del contenedor es del orden del 1–3 % a 16 kbit/s, así que es despreciable. [INFERENCE]
- FLAC: la compresión sin pérdida de una voz G.711 expandida a PCM16 suele quedar entre el 45 % y el 60 % del PCM. Es una estimación que no se ha medido. [INFERENCE]

### 2B. Operación, ecosistema y licencias

| ID | Soporte en FreeSWITCH | Navegador (HTML5) / móvil | CPU cod./decod. | Licencias / patentes | Robustez para STT | Transcodificación a G.711 al reproducir |
|---|---|---|---|---|---|---|
| 1 | Nativo, `mod_sndfile` [DOC] | Universal / universal [INFERENCE] | Nula | Libre | Óptima (referencia; LINEAR16) [DOC] | Solo compresión µ/A (trivial) |
| 2 | Nativo, `mod_sndfile` [DOC] | Universal / universal | Nula | Libre | Óptima | Remuestreo 16→8 kHz + compresión µ/A |
| 3 | `mod_sndfile` lee WAV µ/A-law; grabarlo en crudo exige `mod_native_file` (`.PCMU`/`.PCMA`, sin cabecera) [INFERENCE] | WAV µ-law: soporte parcial (no en todos los navegadores) / Android sí [INFERENCE] | Nula | Libre | Muy buena (MULAW nativo en STT) [DOC] | Ninguna si coincide la ley; µ↔A es trivial |
| 4 | Códec G.722 incluido (spandsp); se almacena solo en crudo con `mod_native_file` (`.G722`) [INFERENCE] | No / no [INFERENCE] | Baja | Libre (patentes expiradas) [INFERENCE] | Buena (WB), pero con poco soporte directo en STT | Decodificar + remuestrear |
| 5 | `mod_g729` es solo passthrough; transcodificar exige `mod_com_g729` (licencia comercial por canal) o bcg729 de terceros [DOC / INFERENCE] | No / no | Media | Patentes expiradas (≈ 2017); la licencia del módulo comercial sigue aplicando [INFERENCE] | Degradada (más WER) [INFERENCE] | Decodificar |
| 6 | Códec `mod_gsm`; archivo vía libsndfile (WAV GSM610), según compilación [INFERENCE] | No / no | Baja | Libre | Degradada | Decodificar |
| 7 | `mod_amr`: passthrough por defecto; transcodificar requiere compilar con opencore-amr. Sin escritor nativo de `.amr` [INFERENCE] | No en navegador / Android sí (.amr/.3gp) [INFERENCE] | Media | Pool de patentes AMR (licencia necesaria) [INFERENCE] | Aceptable (AMR nativo en Google STT) [DOC] | Decodificar |
| 8–9 | `mod_amrwb`: passthrough por defecto; transcodificar requiere vo-amrwbenc / opencore. Sin escritor `.awb` [INFERENCE] | No / Android sí [INFERENCE] | Media | Pool de patentes AMR-WB (licencia necesaria) [INFERENCE] | Buena (AMR_WB nativo en Google STT) [DOC] | Decodificar + remuestrear |
| 10–13 | RTP con `mod_opus`. Archivo con `mod_opusfile`: lectura estable; escritura `.opus` con libopusenc en FS 1.10.x, **a validar** [INFERENCE] | Chrome/Edge/Firefox sí; Safari solo en versiones recientes (**a validar**) / Android sí; iOS con reproductor de app [INFERENCE] | Media (complejidad ajustable 0–10) | Libre de regalías, BSD (IETF) [DOC] | Buena con ≥ 12–16 kbit/s; OGG_OPUS es nativo en STT [DOC / INFERENCE] | Decodificar (libopusfile entrega 48 kHz) + remuestrear 48→8 kHz [INFERENCE] |
| 14–15 | `mod_shout` (LAME/mpg123) lee y escribe `.mp3` [DOC] | Universal / universal | Media | Patentes expiradas (2017) [INFERENCE] | 16k degradada; 32k aceptable | Decodificar + remuestrear |
| 16 | Sin módulo de archivo de audio dedicado; solo de forma indirecta con `mod_av` (orientado a vídeo) o con una herramienta externa [INFERENCE] | Universal (.m4a) / universal | Media-alta (HE-AAC) | Pool de patentes AAC vigente [INFERENCE] | Aceptable | Decodificar + remuestrear |
| 17 | `mod_sndfile` si libsndfile tiene FLAC [INFERENCE] | Navegadores modernos sí / móviles sí [INFERENCE] | Baja | Libre (BSD) | Óptima (FLAC nativo en STT) [DOC] | Decodificar (sin pérdida) |
| 18 | Códec RTP con `mod_speex`; sin contenedor Ogg Speex nativo [INFERENCE] | No / no | Media | Libre (BSD) | Aceptable / degradada | Decodificar |

---

## 3. Dimensionamiento

### 3.1 Supuestos

| Parámetro | Valor |
|---|---|
| Buzones | 300 000 [ASSUMPTION] |
| Mensajes/día | 500 000 (≈ 1,67 por buzón y día) [ASSUMPTION] |
| Duración media | 30 s [ASSUMPTION] |
| Retención | 30 días [ASSUMPTION] |
| Unidades | Decimales: 1 TB = 10¹² B [ASSUMPTION] |
| Réplicas | No incluidas (para R réplicas, multiplicar por R) [ASSUMPTION] |

### 3.2 Fórmulas

```
S  (s de audio/día)       = 500 000 × 30            = 15 000 000 s/día  (= 250 000 min/día)
B  (bytes/s)              = R_kbit/s × 1000 / 8
TB/día                    = B × S / 10¹²
TB retenido (30 d)        = TB/día × 30
TB/año (generado)         = TB/día × 365
MB retenidos por buzón    = TB retenido × 10⁶ / 300 000
```

### 3.3 Resultados

| Formato | B (B/s) | TB/día | TB retenido 30 d | TB/año generado | MB/buzón retenido | Ahorro vs PCM16 8k |
|---|---|---|---|---|---|---|
| WAV PCM16 8 kHz (128k) | 16 000 | 0,240 | 7,200 | 87,600 | 24,00 | — |
| G.711 WAV (64k) | 8 000 | 0,120 | 3,600 | 43,800 | 12,00 | 50,0 % |
| MP3 32 kbit/s | 4 000 | 0,060 | 1,800 | 21,900 | 6,00 | 75,0 % |
| **Opus 16 kbit/s** | 2 000 | **0,030** | **0,900** | **10,950** | **3,00** | **87,5 %** |
| AMR-WB 12.65 (códec) | 1 581,25 | 0,0237 | 0,7116 | 8,657 | 2,37 | 90,1 % |
| AMR-WB 12.65 (archivo .awb, 13,2k) | 1 650 | 0,0248 | 0,7425 | 9,034 | 2,48 | 89,7 % |
| Opus 12 kbit/s | 1 500 | 0,0225 | 0,675 | 8,213 | 2,25 | 90,6 % |

Comprobación de la fila Opus 16: 2 000 B/s × 15 000 000 s = 3,0 × 10¹⁰ B = 0,030 TB/día; × 30 = 0,9 TB; × 365 = 10,95 TB. [INFERENCE]

Con 3 réplicas (por ejemplo, Ceph u objeto S3), la retención en Opus 16 ocupa 2,7 TB, frente a 21,6 TB en PCM16 8 kHz. [INFERENCE]

### 3.4 Concurrencia de grabación (para CPU e I/O)

- Media: 15 000 000 s / 86 400 s ≈ **174 grabaciones simultáneas**. [INFERENCE]
- Hora cargada: si se concentra el 10 % del tráfico diario [ASSUMPTION], salen 1 500 000 s / 3 600 s ≈ **417 grabaciones simultáneas**. Escribirlas en PCM16 son ≈ 6,7 MB/s; en Opus 16, ≈ 0,83 MB/s. [INFERENCE]
- Un núcleo moderno codifica Opus de voz mono a decenas de veces tiempo real con complejidad 10. Unos 417 flujos en paralelo caben holgadamente en pocos núcleos. Hay que medirlo (§5.4). [INFERENCE]

---

## 4. Criterios de decisión y descarte

1. **La calidad de origen limita la calidad almacenada.** La mayoría de las llamadas llegan en G.711 (NB, 300–3400 Hz). Guardarlas en un formato WB (PCM16 16 kHz, G.722, Opus a 16 kHz) **no recupera** la banda que se perdió en la red: solo ocupa más. La frecuencia de grabación debe ser la nativa de la llamada. [DOC / INFERENCE]
2. **Por qué Opus 16 y no Opus 12.** Para NB puro, 12 kbit/s es suficiente. Con 16 kbit/s se usa un único perfil que también sirve para las llamadas WB (AMR-WB de VoLTE, G.722 y Opus de softphones) sin recortarlas, y da margen para STT y para la codificación en tándem. El coste extra es de 0,225 TB retenidos (0,9 frente a 0,675 TB), que es despreciable. [INFERENCE] Una alternativa válida sería un perfil adaptativo (12k si la llamada es NB y 16k si es WB).
3. **Por qué no WAV (PCM16 ni G.711) como almacenamiento.** Ocupa entre 4 y 8 veces más que Opus 16 sin mejorar lo que el usuario percibe al reproducir por el canal de voz G.711. Sí sirve como formato temporal de captura (§5) y para los prompts. [INFERENCE]
4. **Cuándo conservar G.711.** (a) Si se exige una prueba fiel al bit de lo que llegó por la red (requisito legal o forense). (b) Si la CPU del media server es el cuello de botella y el almacenamiento sobra, porque G.711 en crudo se reproduce sin transcodificar. (c) En los prompts de alta frecuencia. Si el requisito es «sin pérdida», es mejor FLAC (≈ 45–60 % del PCM) que WAV G.711. [INFERENCE]
5. **Por qué no MP3.** A 16 kbit/s fuerza fs = 8 kHz (MPEG-2.5) y suena peor que Opus 12. Para igualar a Opus 16 necesita ≈ 32 kbit/s, el doble de espacio. Es un códec perceptual genérico, no de voz, con latencia y pre-eco. Su única ventaja es que se reproduce en todas partes, y eso se resuelve transcodificando al vuelo solo cuando se descarga desde web o correo. [INFERENCE]
6. **Por qué no G.729.** El tamaño es muy bajo (60 KB/min), pero la calidad es inferior (Ie = 10), empeora el STT, no se reproduce en web ni en móviles, transcodificar requiere licencia comercial en FreeSWITCH (`mod_com_g729`) y solo se guarda en crudo (`mod_native_file`). Además, sería una segunda codificación con pérdida sobre G.711. [DOC / INFERENCE]
7. **Por qué no AMR-NB/AMR-WB como almacenamiento.** Su eficiencia es parecida a la de Opus, pero tiene patentes en pool, en FreeSWITCH es solo passthrough salvo que se recompile, no tiene escritor de archivo nativo y no se reproduce en navegador. Solo tendría sentido guardar en passthrough las llamadas que ya llegan en AMR, y eso complica el pipeline. [INFERENCE]
8. **Por qué no AAC/HE-AAC.** Tiene licencias de pool, no hay módulo de archivo en FreeSWITCH y no supera a Opus en voz. [INFERENCE]
9. **Por qué no Speex ni GSM.** Están obsoletos o superados por Opus a igual bitrate. [DOC]
10. **Codificación en tándem.** Una llamada AMR-WB o G.729 que se recodifica a Opus pasa por dos códecs con pérdida. A 16 kbit/s la degradación adicional debería ser pequeña, pero hay que medirla con POLQA/PESQ (§5.4). [INFERENCE]

---

## 5. Implementación en FreeSWITCH (alto nivel, sin cambios en la maqueta)

### 5.1 Opciones de grabación

| Opción | Descripción | Ventajas | Inconvenientes |
|---|---|---|---|
| **A. Grabación directa en `.opus`** | `mod_voicemail` con `<param name="file-extension" value="opus"/>` en el perfil (hoy usa `wav`) y `mod_opusfile` con escritura (libopusenc) [DOC / INFERENCE] | Una sola escritura, sin worker ni archivos temporales | Depende de que el build de FS tenga escritura Opus estable (**a validar**). La codificación consume CPU del media server en tiempo real |
| **B. Grabación en WAV + transcodificación asíncrona** (recomendada para la fase 1) | Se graba como hoy (WAV PCM16 a la frecuencia nativa). Un worker (opusenc/ffmpeg con libopus: `-c:a libopus -b:a 16k -ac 1 -application voip`) convierte a `.opus`, verifica el resultado, actualiza la ruta del mensaje y borra el WAV | Saca la CPU del camino de medios, usa herramientas maduras y permite reintentos; el WAV sirve de respaldo hasta validar | La BD de `mod_voicemail` (`voicemail_msgs.file_path`) referencia el `.wav`: hay que reescribir la ruta y la extensión de forma atómica, con una ventana de inconsistencia. Necesita un buffer local (≈ 6,7 MB/s de escritura en hora cargada) [INFERENCE] |

**Recomendación:** empezar con la **opción B** y pasar a la **A** cuando las pruebas confirmen que `mod_opusfile` escribe bien (con seek, duración y concurrencia). [INFERENCE]

### 5.2 Parámetros orientativos

- `record_sample_rate`: no forzarlo a 16000 en llamadas NB. Hay que dejar la frecuencia nativa del códec leído (8000 en G.711, 16000 en AMR-WB/G.722). [DOC / INFERENCE]
- Opus: mono, 16 kbit/s VBR, `application=voip`, tramas de 20 ms, complejidad entre 5 y 10 según el benchmark de CPU. [DOC RFC 6716 / INFERENCE]
- Extensión `.opus` (Ogg Opus, RFC 7845). Es preferible a `.ogg`, que es ambigua con Vorbis. [DOC]
- Correo de voz a email (si se usa): adjuntar `.opus` puede no reproducirse en algunos clientes (Outlook, iOS Mail antiguos). Conviene transcodificar al vuelo a MP3 32k o M4A solo para el adjunto, o enviar un enlace. [INFERENCE]

### 5.3 Prompts del IVR y reproducción por el canal de voz

- Los prompts (bienvenida, menús) son pocos archivos, así que el espacio da igual. Se mantienen en WAV PCM16 en las subcarpetas por frecuencia que usa FreeSWITCH (`.../8000/`, `.../16000/`), para que cada llamada reproduzca la variante NB o WB sin remuestrear. Para eliminar del todo la CPU en los prompts más usados se puede usar el formato nativo (`.PCMA`/`.PCMU` con `mod_native_file`). [DOC / INFERENCE]
- Reproducción de mensajes: archivo Opus → `mod_opusfile` decodifica (libopusfile entrega 48 kHz) → remuestreo a 8 kHz → codificación al códec negociado (PCMA/PCMU). Toda la transcodificación la hace FreeSWITCH; RTPEngine no necesita transcodificar porque el AS ya entrega el códec negociado en el SDP. [INFERENCE]
- La reproducción también tiene que funcionar con DTMF de avance y retroceso (seek en Ogg) y con el cálculo de duración del mensaje (granule position). Ambos casos deben validarse. [INFERENCE]

### 5.4 Riesgos y validaciones pendientes (NO ejecutadas)

| # | Riesgo | Validación propuesta |
|---|---|---|
| R1 | El build de FS en DEV no tiene `mod_opusfile` con escritura (libopusenc) | Revisar módulos cargados y formatos de archivo registrados; grabar 1 mensaje en `.opus` y reproducirlo |
| R2 | CPU por codificar y decodificar con ~417 grabaciones simultáneas, más reproducciones con remuestreo 48→8 kHz | Benchmark de carga (SIPp + grabación) midiendo CPU por flujo y complejidad |
| R3 | Pérdida de calidad en tándem (G.711, AMR-WB o G.729 → Opus) | POLQA (ITU-T P.863) o PESQ (P.862) sobre un corpus de llamadas reales en NB y WB |
| R4 | Degradación del STT | Medir el WER del motor STT elegido con WAV y con Opus 12/16 sobre el mismo corpus |
| R5 | Seek (DTMF avance/retroceso) y duración en Ogg | Prueba funcional del menú de recuperación de `mod_voicemail` |
| R6 | Inconsistencia de BD en la opción B (rutas `.wav` → `.opus`) | Prueba de reemplazo atómico y de reintentos del worker; reconciliación de huérfanos |
| R7 | Reproducción en clientes web y móviles (sobre todo Safari/iOS) | Matriz de navegadores y dispositivos; si falla, transcodificar al vuelo a M4A/MP3 en el portal o correo |
| R8 | Requisito legal de fidelidad o retención | Confirmar con el cliente; si exige «sin pérdida», usar FLAC (§4.4) |
| R9 | No regresión del contrato de prueba | `maqueta-ims-3/scripts/test_maqueta.sh` debe seguir dando 15/15 tras cualquier cambio [CONFIG] |

---

## 6. Referencias (por nombre de documento)

- IETF RFC 6716 — *Definition of the Opus Audio Codec* (§2.1.1, puntos de operación por bitrate). [DOC]
- IETF RFC 7845 — *Ogg Encapsulation for the Opus Audio Codec*. [DOC]
- IETF RFC 7587 — *RTP Payload Format for the Opus Speech and Audio Codec*. [DOC]
- IETF RFC 4867 — *RTP Payload Format and File Storage Format for AMR and AMR-WB*. [DOC]
- ITU-T G.711 — *Pulse code modulation (PCM) of voice frequencies*. [DOC]
- ITU-T G.722 — *7 kHz audio-coding within 64 kbit/s*. [DOC]
- ITU-T G.729 — *Coding of speech at 8 kbit/s using CS-ACELP*. [DOC]
- ITU-T G.113 — *Transmission impairments due to speech processing* (Apéndice I, valores Ie). [DOC]
- ITU-T G.107 / G.107.1 — *E-model* (NB / WB). [DOC]
- ITU-T P.800 (MOS), P.862 (PESQ), P.863 (POLQA). [DOC]
- ETSI/3GPP GSM 06.10 — *Full rate speech transcoding*. [DOC]
- 3GPP TS 26.071 — *AMR speech codec; General description*. [DOC]
- 3GPP TS 26.171 — *AMR-WB speech codec; General description* (también ITU-T G.722.2). [DOC]
- 3GPP TR 26.976 — *AMR-WB performance characterization*. [DOC]
- Documentación de FreeSWITCH: `mod_sndfile`, `mod_opus`, `mod_opusfile`, `mod_shout`, `mod_native_file`, `mod_g729` / `mod_com_g729`, `mod_amr` / `mod_amrwb`, `mod_voicemail` (parámetro `file-extension`), variable de canal `record_sample_rate`. [DOC]
- Documentación de Xiph.Org: Speex (estado obsoleto en favor de Opus), FLAC, libopusfile / libopusenc. [DOC]
- Google Cloud Speech-to-Text — `RecognitionConfig.AudioEncoding` (LINEAR16, FLAC, MULAW, AMR, AMR_WB, OGG_OPUS, SPEEX_WITH_HEADER_BYTE). [DOC]
