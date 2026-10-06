# Entregables FEAT-02 — maqueta IMS uVAS

Rama: `feature/feat-02` · Fecha: 2026-10-06

| # | Entregable | Archivo |
|---|---|---|
| 1 | Verificación de cumplimiento 3GPP (señalización, autenticación y seguridad) | `01_verificacion_3gpp/INFORME_CUMPLIMIENTO_3GPP.md` · informes del verificador `check_3gpp_linea_base.md` (5/27) y `check_3gpp_final.md` (27/27) |
| 2 | FEAT-02 VMS completo: implementación y definición de hecho | `02_feat02/FEAT-02_VMS_IMPLEMENTACION.md` |
| 3 | Iteraciones captura → análisis → corrección (29 corridas) | `03_iteraciones/BITACORA_ITERACIONES.md` y `03_iteraciones/iter-*/` |
| 4 | Avance, cronograma PMV y paso a paso a DEV (diapositivas) | `04_presentaciones/FEAT-02_avance_PMV_ruta_DEV.pptx` (+ PDF) |
| 4 | Tutorial: conectar un softphone externo | `04_presentaciones/Tutorial_softphone_externo.pptx` (+ PDF) y `TUTORIAL_SOFTPHONE_EXTERNO.md` |

## Resultado

- E2E `scripts/test_maqueta.sh`: **22/22** (antes 16/20).
- Verificación de la captura `maqueta_ims_sip_only.pcap`: **27/27 reglas 3GPP** (antes 5/27),
  en dos corridas consecutivas (`iter-28-final`, `iter-29-confirmacion`).
- Autenticación IMS-AKA real e IPsec ESP en Gm, verificados criptográficamente sobre la captura.

## Reproducir

```bash
cd maqueta-ims-3
docker compose up -d --build
bash scripts/capture_iteration.sh ../entregables-feat-02/03_iteraciones/iter-NN
```

Cada carpeta `iter-*` contiene `test_maqueta.log`, `maqueta_ims_sip_only.pcap` y
`check_3gpp.md`. Las capturas completas (`maqueta_ims.pcap`) solo se conservan en la
línea base y las dos corridas finales; las capturas no se versionan en git (`*.pcap`
está en `.gitignore`).
