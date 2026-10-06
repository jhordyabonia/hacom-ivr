// Genera las presentaciones de entregables FEAT-02 (maqueta IMS uVAS).
const pptxgen = require("pptxgenjs");
const path = require("path");
const { applyTheme } = require("/home/jhordy/.config/Claude/local-agent-mode-sessions/skills-plugin/0b46eb01-f949-49b1-85df-6ddc422bf119/72e655d5-83de-48a1-8a07-ea9221178728/skills/pptx/scripts/apply_theme.js");

const OUT = "/media/jhordy/documents/hacom/ivr/entregables-feat-02/04_presentaciones";

const THEME = {
  name: "IMS Señalización",
  headFontFace: "Cambria",
  bodyFontFace: "Calibri",
  colors: {
    dk1: "17262F", lt1: "FFFFFF", dk2: "0E4A55", lt2: "EEF4F5",
    accent1: "0F7C8A", accent2: "F0A030", accent3: "3E9A5E", accent4: "C2473A",
    accent5: "5B6B78", accent6: "9CC9CF", hlink: "0F7C8A", folHlink: "5B6B78",
  },
};
const HEX = THEME.colors;

// ---------------------------------------------------------------- helpers
function newDeck(title) {
  const pres = new pptxgen();
  pres.layout = "LAYOUT_WIDE"; // 13.33 x 7.5
  pres.title = title;
  pres.author = "Jhordy Abonia";
  pres.company = "HACOM / Amaris";
  pres.theme = { headFontFace: THEME.headFontFace, bodyFontFace: THEME.bodyFontFace };
  const C = pres.SchemeColor;
  pres.defineSlideMaster({
    title: "PORTADA",
    background: { color: C.text2 },
    objects: [
      { placeholder: { options: { name: "title", type: "title", x: 0.8, y: 2.2, w: 11.7, h: 1.6, fontSize: 44, bold: true, color: C.background1, valign: "bottom" }, text: "" } },
      { placeholder: { options: { name: "body", type: "body", x: 0.8, y: 4.0, w: 11.7, h: 1.4, fontSize: 20, color: C.accent6, valign: "top" }, text: "" } },
    ],
  });
  pres.defineSlideMaster({
    title: "CONTENIDO",
    background: { color: C.background1 },
    margin: [0.5, 0.6, 0.7, 0.6],
    objects: [
      { placeholder: { options: { name: "title", type: "title", x: 0.6, y: 0.35, w: 12.1, h: 0.9, fontSize: 30, bold: true, color: C.text2, valign: "middle", align: "left" }, text: "" } },
      { text: { text: "Maqueta IMS uVAS · FEAT-02", options: { x: 0.6, y: 7.0, w: 6, h: 0.3, fontSize: 10, color: C.accent5 } } },
    ],
    slideNumber: { x: 12.2, y: 7.0, w: 0.6, h: 0.3, fontSize: 10, color: C.accent5 },
  });
  return { pres, C };
}

function card(slide, C, o) {
  // o: x,y,w,h, head, body, num (opcional), color
  slide.addShape("roundRect", { x: o.x, y: o.y, w: o.w, h: o.h, rectRadius: 0.12, fill: { color: C.background2 }, line: { color: C.background2 }, objectName: "card-" + o.head });
  let tx = o.x + 0.25;
  if (o.num !== undefined) {
    slide.addShape("ellipse", { x: o.x + 0.25, y: o.y + 0.25, w: 0.6, h: 0.6, fill: { color: o.color || C.accent1 }, line: { color: o.color || C.accent1 } });
    slide.addText(String(o.num), { x: o.x + 0.25, y: o.y + 0.25, w: 0.6, h: 0.6, fontSize: 18, bold: true, color: C.background1, align: "center", valign: "middle", margin: 0, isTextBox: true });
    tx = o.x + 1.0;
  }
  slide.addText(o.head, { x: tx, y: o.y + 0.2, w: o.x + o.w - tx - 0.2, h: 0.7, fontSize: 18, bold: true, color: C.text2, valign: "middle", margin: 0, isTextBox: true });
  slide.addText(o.body, { x: o.x + 0.25, y: o.y + 0.95, w: o.w - 0.5, h: o.h - 1.1, fontSize: 14, color: C.text1, valign: "top", margin: 0, isTextBox: true });
}

function addBusinessDays(d, n) {
  const r = new Date(d);
  while (n > 0) { r.setDate(r.getDate() + 1); if (r.getDay() !== 0 && r.getDay() !== 6) n--; }
  return r;
}
const fmt = (d) => d.toLocaleDateString("es-CO", { day: "2-digit", month: "short" });

// ================================================================ DECK A
async function deckAvance() {
  const { pres, C } = newDeck("Maqueta IMS uVAS — avance FEAT-02 y ruta a DEV");

  // 1 Portada
  pres.addSection({ title: "Resumen" });
  let s = pres.addSlide({ masterName: "PORTADA", sectionTitle: "Resumen" });
  s.addText("Maqueta IMS uVAS: VMS completo y señalización 3GPP al 100 %", { placeholder: "title" });
  s.addText("Avance FEAT-02, PMV de voz y paso a paso para llevar la maqueta a un ambiente DEV · octubre 2026", { placeholder: "body" });
  s.addNotes("Presentación del avance: FEAT-02 terminado, cumplimiento 3GPP verificado sobre capturas, y plan para el ambiente DEV compartido.");

  // 2 Resumen en cifras
  s = pres.addSlide({ masterName: "CONTENIDO", sectionTitle: "Resumen" });
  s.addText("La maqueta pasa de 5 a 27 reglas 3GPP verificadas", { placeholder: "title" });
  const stats = [
    ["27/27", "reglas 3GPP en la captura final", "línea base: 5/27 (18,5 %)", C.accent1],
    ["22/22", "checks E2E del test de la maqueta", "antes: 16/20", C.accent3],
    ["103", "paquetes ESP con integridad verificada", "IMS-AKA + IPsec en Gm", C.accent2],
  ];
  stats.forEach((st, i) => {
    const x = 0.6 + i * 4.1;
    s.addShape("roundRect", { x, y: 1.6, w: 3.8, h: 3.2, rectRadius: 0.15, fill: { color: C.background2 }, line: { color: C.background2 } });
    s.addText(st[0], { x, y: 1.85, w: 3.8, h: 1.3, fontSize: 60, bold: true, color: st[3], align: "center", margin: 0, isTextBox: true, fontFace: THEME.headFontFace });
    s.addText(st[1], { x: x + 0.3, y: 3.2, w: 3.2, h: 0.8, fontSize: 16, color: C.text1, align: "center", margin: 0, isTextBox: true });
    s.addText(st[2], { x: x + 0.3, y: 4.0, w: 3.2, h: 0.5, fontSize: 12, italic: true, color: C.accent5, align: "center", margin: 0, isTextBox: true });
  });
  s.addText("Verificado en 29 iteraciones de captura (tcpdump → tshark -Y sip → check_3gpp.py); dos corridas finales consecutivas al 100 %.", { x: 0.6, y: 5.3, w: 12.1, h: 0.8, fontSize: 16, color: C.text1, isTextBox: true });
  s.addNotes("Las 27 reglas citan TS 24.229, TS 33.203, TS 24.606, TS 26.114 y RFC 3261/3329. 100 % es sobre ese conjunto explícito.");

  // 3 Arquitectura
  pres.addSection({ title: "Lo construido" });
  s = pres.addSlide({ masterName: "CONTENIDO", sectionTitle: "Lo construido" });
  s.addText("Cada servicio es un AS tras una iFC; el Core no cambia", { placeholder: "title" });
  const nodes = [
    ["UE IMS", "pjsua + IMS-AKA\nIPsec ESP", C.accent2],
    ["P-CSCF", "sec-agree\nSA ESP · PAI", C.accent1],
    ["I-CSCF", "UAR / LIR", C.accent1],
    ["S-CSCF", "MAR/SAR · iFC\nP10 · P30 · P40", C.accent1],
    ["AS-Front", "ISC → SIP", C.accent3],
    ["FreeSWITCH", "IVR · VMS · MWI", C.accent3],
  ];
  nodes.forEach((n, i) => {
    const x = 0.5 + i * 2.1;
    s.addShape("roundRect", { x, y: 2.0, w: 1.8, h: 1.9, rectRadius: 0.15, fill: { color: n[2] }, line: { color: n[2] }, objectName: "nodo-" + n[0] });
    s.addText(n[0], { x, y: 2.1, w: 1.8, h: 0.6, fontSize: 18, bold: true, color: C.background1, align: "center", margin: 0, isTextBox: true });
    s.addText(n[1], { x: x + 0.1, y: 2.7, w: 1.6, h: 1.1, fontSize: 13, color: C.background1, align: "center", margin: 0, isTextBox: true });
    if (i < nodes.length - 1) s.addShape("rightArrow", { x: x + 1.82, y: 2.8, w: 0.26, h: 0.3, fill: { color: C.accent5 }, line: { color: C.accent5 } });
  });
  s.addShape("roundRect", { x: 6.8, y: 4.4, w: 1.8, h: 1.0, rectRadius: 0.12, fill: { color: C.background2 }, line: { color: C.accent5 } });
  s.addText("PyHSS (Cx)\nperfiles + vectores AKA", { x: 6.8, y: 4.4, w: 1.8, h: 1.0, fontSize: 12, color: C.text2, align: "center", valign: "middle", margin: 0, isTextBox: true });
  s.addText([
    { text: "Gm (UE – P-CSCF): ", options: { bold: true } }, { text: "toda la señalización dentro de ESP tras el registro.", options: { breakLine: true } },
    { text: "ISC: ", options: { bold: true } }, { text: "IVR 0100002, buzón 0100003/0100004, MWI y depósito por no registrado.", options: {} },
  ], { x: 0.6, y: 5.7, w: 12.1, h: 0.9, fontSize: 15, color: C.text1, isTextBox: true });

  // 4 Seguridad antes/después
  s = pres.addSlide({ masterName: "CONTENIDO", sectionTitle: "Lo construido" });
  s.addText("Autenticación y seguridad: de simulada a real", { placeholder: "title" });
  const rows = [
    ["Aspecto", "Antes", "Ahora"],
    ["Autenticación", "Digest MD5 (fallback)", "IMS-AKA obligatorio (AKAv1-MD5)"],
    ["UE", "pjsua sin AKA real", "K/OPc/AMF, IMPI desde el 1er REGISTER"],
    ["sec-agree", "Security-Server de eco", "ims_ipsec_pcscf con SPI/puertos propios"],
    ["Gm", "SIP en claro", "IPsec ESP (hmac-sha-1-96), SA renovadas"],
    ["Hacia el core", "Security-* y sec-agree filtrados", "Retirados; integrity-protected yes/no"],
  ];
  s.addTable(rows.map((r, i) => r.map((c) => ({ text: c, options: { bold: i === 0, color: i === 0 ? HEX.lt1 : HEX.dk1, fill: { color: i === 0 ? HEX.dk2 : (i % 2 ? HEX.lt2 : HEX.lt1) } } }))), {
    x: 0.6, y: 1.5, w: 12.1, colW: [2.6, 4.4, 5.1], fontSize: 15, fontFace: THEME.bodyFontFace, border: { type: "solid", pt: 0.5, color: HEX.accent6 }, rowH: 0.62, valign: "middle",
  });
  s.addText("Evidencia: la respuesta AKA (RES), el AUTN (MAC-A) y el ICV de cada paquete ESP se recalculan con Milenage a partir de la captura.", { x: 0.6, y: 5.6, w: 12.1, h: 0.8, fontSize: 15, italic: true, color: C.accent5, isTextBox: true });

  // 5 FEAT-02 flujos
  s = pres.addSlide({ masterName: "CONTENIDO", sectionTitle: "Lo construido" });
  s.addText("FEAT-02: depositar, avisar y recuperar el mensaje", { placeholder: "title" });
  card(s, C, { x: 0.6, y: 1.5, w: 3.9, h: 3.2, num: 1, head: "Depósito", body: "UE1 llama a UE2 no registrado. El S-CSCF pide el perfil (SAR unregistered) y la iFC P40 lo desvía al AS: mod_voicemail graba en el buzón del MSISDN." });
  card(s, C, { x: 4.7, y: 1.5, w: 3.9, h: 3.2, num: 2, head: "MWI", color: C.accent2, body: "UE2 se suscribe a message-summary (iFC P10). El AS notifica en el diálogo: Messages-Waiting yes tras depositar y no tras borrar (TS 24.606)." });
  card(s, C, { x: 8.8, y: 1.5, w: 3.9, h: 3.2, num: 3, head: "Recuperación", color: C.accent3, body: "UE2 llama al 0100004, marca el PIN (DTMF), escucha con 1 y borra con 7. El buzón queda vacío y el MWI se actualiza." });
  s.addText("Cinco checks E2E nuevos cubren el ciclo completo; los tres flujos viajan sobre IMS-AKA + IPsec.", { x: 0.6, y: 5.0, w: 12.1, h: 0.6, fontSize: 15, color: C.text1, isTextBox: true });

  // 6 Evolución (gráfico)
  s = pres.addSlide({ masterName: "CONTENIDO", sectionTitle: "Lo construido" });
  s.addText("Cada iteración corrigió una causa raíz concreta", { placeholder: "title" });
  const pct = [18.5, 55.6, 70.4, 88.9, 88.9, 88.9, 92.6, 92.6, 92.6, 92.6, 70.4, 88.9, 92.6, 96.3, 92.6, 96.3, 92.6, 92.6, 92.6, 92.6, 96.3, 96.3, 96.3, 77.8, 100, 100, 100, 92.6, 100, 100];
  const e2e = [80, 36.4, 40.9, 72.7, 45.5, 77.3, 77.3, 77.3, 77.3, 77.3, 36.4, 77.3, 68.2, 77.3, 86.4, 90.9, 86.4, 81.8, 90.9, 90.9, 95.5, 95.5, 95.5, 40.9, 95.5, 95.5, 100, 100, 100, 100];
  const labels = pct.map((_, i) => String(i));
  s.addChart(pres.charts.LINE, [
    { name: "Reglas 3GPP (%)", labels, values: pct },
    { name: "Checks E2E (%)", labels, values: e2e },
  ], {
    x: 0.6, y: 1.4, w: 8.4, h: 5.0, chartColors: [HEX.accent1, HEX.accent2], lineSize: 2.5, lineDataSymbolSize: 5,
    valAxisMinVal: 0, valAxisMaxVal: 100, valAxisLabelColor: HEX.accent5, catAxisLabelColor: HEX.accent5,
    valAxisLabelFontFace: "+mn-lt", catAxisLabelFontFace: "+mn-lt", legendFontFace: "+mn-lt", titleFontFace: "+mn-lt",
    valGridLine: { color: "D9E3E5", size: 0.5 }, catGridLine: { style: "none" },
    showLegend: true, legendPos: "b", showTitle: true, title: "Cumplimiento por iteración", titleColor: HEX.dk2, titleFontSize: 14,
  });
  s.addText([
    { text: "Hitos", options: { bold: true, fontSize: 18, color: HEX.dk2, breakLine: true } },
    { text: "It. 1: primer registro AKA + IPsec", options: { bullet: true, breakLine: true } },
    { text: "It. 4–5: NAT sin estado y SA de dos generaciones", options: { bullet: true, breakLine: true } },
    { text: "It. 13: parche ims_isc (desvío a buzón)", options: { bullet: true, breakLine: true } },
    { text: "It. 24: todo Gm en ESP", options: { bullet: true, breakLine: true } },
    { text: "It. 28–29: 100 % / 100 % consecutivos", options: { bullet: true } },
  ], { x: 9.3, y: 1.5, w: 3.5, h: 4.9, fontSize: 14, color: C.text1, paraSpaceAfter: 6, valign: "top", isTextBox: true });
  s.addNotes("Las caídas (iteraciones 10 y 23) son regresiones de prueba: reconstrucción de Kamailio con SA residuales y un intento de enviar el REGISTER inicial desde port_uc, que se revirtió.");

  // 7 PMV estado
  pres.addSection({ title: "PMV y cronograma" });
  s = pres.addSlide({ masterName: "CONTENIDO", sectionTitle: "PMV y cronograma" });
  s.addText("PMV de voz: dos de cinco features listos", { placeholder: "title" });
  const pmv = [
    ["Feature", "Alcance", "Estado"],
    ["FEAT-01", "IVR con menú DTMF y flujos por país", "Listo"],
    ["FEAT-02", "VMS: depósito, MWI, recuperación con PIN", "Listo"],
    ["FEAT-03", "MCA: aviso de llamada perdida", "Pendiente"],
    ["FEAT-04", "CDR en MySQL + API de charging", "Pendiente"],
    ["FEAT-05", "Reportes y monitoreo en la UI", "Pendiente"],
  ];
  s.addTable(pmv.map((r, i) => r.map((c, j) => ({ text: c, options: { bold: i === 0 || j === 2, color: i === 0 ? HEX.lt1 : (j === 2 ? (c === "Listo" ? HEX.accent3 : HEX.accent4) : HEX.dk1), fill: { color: i === 0 ? HEX.dk2 : (i % 2 ? HEX.lt2 : HEX.lt1) } } }))), {
    x: 0.6, y: 1.5, w: 12.1, colW: [2.0, 7.6, 2.5], fontSize: 16, fontFace: THEME.bodyFontFace, border: { type: "solid", pt: 0.5, color: HEX.accent6 }, rowH: 0.65, valign: "middle",
  });
  s.addText("FEAT-03 depende de FEAT-02 (aviso por MWI en el primer corte); FEAT-05 depende de FEAT-04 (CDR).", { x: 0.6, y: 5.8, w: 12.1, h: 0.6, fontSize: 15, italic: true, color: C.accent5, isTextBox: true });

  // 8 Cronograma (Gantt)
  s = pres.addSlide({ masterName: "CONTENIDO", sectionTitle: "PMV y cronograma" });
  s.addText("Ruta a DEV y cierre del PMV de voz", { placeholder: "title" });
  const start = new Date(2026, 9, 12); // lunes 12-oct-2026
  const tasks = [
    { t: "Solicitud y provisión de VM DEV", d: 5, dep: null, who: "Infra (Henry)" },
    { t: "Despliegue maqueta + E2E 22/22 en DEV", d: 3, dep: 0, who: "Jhordy" },
    { t: "Acceso externo y softphones", d: 3, dep: 1, who: "Jhordy" },
    { t: "Endurecimiento (prompts, CFNR, SA)", d: 8, dep: 1, who: "Jhordy" },
    { t: "FEAT-03 MCA", d: 5, dep: 3, who: "Desarrollo" },
    { t: "FEAT-04 CDR + API", d: 5, dep: 3, who: "Desarrollo" },
    { t: "FEAT-05 Reportes UI", d: 5, dep: 5, who: "Desarrollo" },
    { t: "Validación, demo y HLD", d: 4, dep: 6, who: "Equipo + Gleidi" },
  ];
  tasks.forEach((k) => {
    k.s = k.dep === null ? new Date(start) : addBusinessDays(tasks[k.dep].e, 0);
    if (k.dep !== null) k.s = addBusinessDays(tasks[k.dep].e, 1);
    k.e = addBusinessDays(k.s, k.d - 1);
  });
  // offset en días hábiles desde el inicio
  const bd = (a, b) => { let n = 0; const r = new Date(a); while (r < b) { r.setDate(r.getDate() + 1); if (r.getDay() !== 0 && r.getDay() !== 6) n++; } return n; };
  const total = bd(start, tasks[tasks.length - 1].e) + 1;
  const gx = 4.2, gw = 6.6, gy = 1.45, rh = 0.54, unit = gw / total;
  for (let w = 0; w <= total; w += 5) {
    s.addText("S" + (w / 5 + 1), { x: gx + w * unit, y: gy - 0.05, w: 0.6, h: 0.3, fontSize: 10, color: C.accent5, margin: 0, isTextBox: true });
  }
  tasks.forEach((k, i) => {
    const y = gy + 0.35 + i * rh;
    s.addText(k.t, { x: 0.6, y, w: 3.7, h: rh - 0.08, fontSize: 13, color: C.text1, valign: "middle", margin: 0, isTextBox: true });
    const off = bd(start, k.s);
    const col = i < 2 ? C.accent2 : (i < 4 ? C.accent1 : (i < 7 ? C.accent3 : C.accent5));
    s.addShape("roundRect", { x: gx + off * unit, y: y + 0.06, w: k.d * unit, h: rh - 0.2, rectRadius: 0.06, fill: { color: col }, line: { color: col }, objectName: "barra-" + i });
    s.addText(fmt(k.s) + " – " + fmt(k.e), { x: gx + (off + k.d) * unit + 0.08, y, w: 2.2, h: rh - 0.08, fontSize: 10, color: C.accent5, valign: "middle", margin: 0, isTextBox: true });
  });
  const endAll = tasks[tasks.length - 1].e;
  s.addText(`Duración total: ${total} días hábiles (${fmt(start)} → ${fmt(endAll)}). Supuestos: VM entregada en 5 días; acceso externo y endurecimiento en paralelo; FEAT-03 y FEAT-04 en paralelo.`, { x: 0.6, y: 6.35, w: 12.1, h: 0.55, fontSize: 13, italic: true, color: C.accent5, isTextBox: true });
  console.log("Cronograma:", tasks.map((k) => `${k.t}: ${fmt(k.s)}-${fmt(k.e)}`).join(" | "), "total", total);
  s.addNotes("Estimación por descomposición de tareas en días hábiles; las fechas se recalculan si cambia la fecha de entrega de la VM, que es la dependencia externa principal.");

  // 9 Requisitos DEV
  pres.addSection({ title: "Paso a paso DEV" });
  s = pres.addSlide({ masterName: "CONTENIDO", sectionTitle: "Paso a paso DEV" });
  s.addText("Qué pedir a infraestructura", { placeholder: "title" });
  const req = [
    ["8 vCPU", "CPU recomendada (mínimo 4)"],
    ["16 GB", "RAM recomendada (mínimo 8)"],
    ["80 GB", "SSD (imágenes ~6 GB + capturas)"],
    ["Linux", "kernel con xfrm/esp4 y nftables"],
  ];
  req.forEach((r, i) => {
    const x = 0.6 + i * 3.05;
    s.addShape("roundRect", { x, y: 1.6, w: 2.8, h: 2.2, rectRadius: 0.15, fill: { color: C.background2 }, line: { color: C.background2 } });
    s.addText(r[0], { x, y: 1.8, w: 2.8, h: 0.9, fontSize: 36, bold: true, color: C.accent1, align: "center", margin: 0, isTextBox: true, fontFace: THEME.headFontFace });
    s.addText(r[1], { x: x + 0.2, y: 2.75, w: 2.4, h: 0.9, fontSize: 14, color: C.text1, align: "center", margin: 0, isTextBox: true });
  });
  s.addText([
    { text: "Docker Engine + Compose v2; acceso SSH al repositorio hacom-ivr.", options: { bullet: true, breakLine: true } },
    { text: "Red: ruta de la LAN/VPN de desarrollo hacia 172.32.0.0/24 (sin NAT: IPsec ESP no atraviesa NAT sin UDP-encap).", options: { bullet: true, breakLine: true } },
    { text: "Puerto 8090/TCP para la UI de operación; UDP 5060 y 6100-6109/5100-5109 del P-CSCF.", options: { bullet: true } },
  ], { x: 0.6, y: 4.2, w: 12.1, h: 2.2, fontSize: 15, color: C.text1, paraSpaceAfter: 8, isTextBox: true });

  // 10 Paso a paso
  s = pres.addSlide({ masterName: "CONTENIDO", sectionTitle: "Paso a paso DEV" });
  s.addText("Ocho pasos de la VM vacía a la maqueta verificada", { placeholder: "title" });
  const steps = [
    ["Preparar la VM", "Docker + Compose, módulos esp4/xfrm_user y nf_tables."],
    ["Clonar la rama", "git clone … && git checkout feature/feat-02"],
    ["Ajustar .env", "IPs de la red y dominio (MCC/MNC) si cambian."],
    ["Construir y levantar", "docker compose up -d --build (14 contenedores)."],
    ["Provisionar HSS", "scripts/provision_hss.sh (suscriptores e iFC)."],
    ["Probar E2E", "bash scripts/test_maqueta.sh → 22/22"],
    ["Verificar 3GPP", "bash scripts/capture_iteration.sh <dir> → 27/27"],
    ["Abrir acceso", "Ruta LAN→172.32.0.0/24 y softphones (tutorial)."],
  ];
  steps.forEach((st, i) => {
    const col = i % 2, row = Math.floor(i / 2);
    const x = 0.6 + col * 6.15, y = 1.45 + row * 1.3;
    s.addShape("ellipse", { x, y: y + 0.1, w: 0.6, h: 0.6, fill: { color: C.accent1 }, line: { color: C.accent1 } });
    s.addText(String(i + 1), { x, y: y + 0.1, w: 0.6, h: 0.6, fontSize: 18, bold: true, color: C.background1, align: "center", valign: "middle", margin: 0, isTextBox: true });
    s.addText(st[0], { x: x + 0.8, y, w: 5.1, h: 0.45, fontSize: 17, bold: true, color: C.text2, margin: 0, isTextBox: true });
    s.addText(st[1], { x: x + 0.8, y: y + 0.45, w: 5.1, h: 0.6, fontSize: 14, color: C.text1, margin: 0, isTextBox: true });
  });
  s.addNotes("Detalle de comandos en README.md del repositorio y en entregables-feat-02/README.md.");

  // 11 Riesgos
  pres.addSection({ title: "Cierre" });
  s = pres.addSlide({ masterName: "CONTENIDO", sectionTitle: "Cierre" });
  s.addText("Riesgos y pendientes que conviene decidir ya", { placeholder: "title" });
  card(s, C, { x: 0.6, y: 1.5, w: 5.9, h: 2.3, head: "Integración con el HSS del operador", body: "Cómo enrutará las consultas de buzón hacia el FreeSWITCH correcto sin almacenamiento central (riesgo abierto en la minuta del 25/09)." });
  card(s, C, { x: 6.8, y: 1.5, w: 5.9, h: 2.3, head: "Softphones comerciales", body: "No hacen IMS-AKA ni IPsec. En DEV se habilita un perfil SIP Digest (TS 33.203 Anexo N) aislado; producción solo AKA." });
  card(s, C, { x: 0.6, y: 4.05, w: 5.9, h: 2.3, head: "Prompts de voz del buzón", body: "La imagen no trae los audios de mod_voicemail; el menú es propio en Lua. Falta grabar o instalar prompts en español." });
  card(s, C, { x: 6.8, y: 4.05, w: 5.9, h: 2.3, head: "Dependencia de infraestructura", body: "Sin VM DEV no avanza la validación compartida: es la primera tarea de la ruta crítica." });

  // 12 Próximos pasos (oscura)
  s = pres.addSlide({ masterName: "PORTADA", sectionTitle: "Cierre" });
  s.addText("Próximos pasos", { placeholder: "title" });
  s.addText("1. Solicitar la VM DEV (8 vCPU / 16 GB / 80 GB) · 2. Desplegar y repetir 22/22 y 27/27 en DEV · 3. Abrir acceso de softphones · 4. Iniciar FEAT-03 y FEAT-04", { placeholder: "body" });

  const file = path.join(OUT, "FEAT-02_avance_PMV_ruta_DEV.pptx");
  await pres.writeFile({ fileName: file });
  await applyTheme(file, THEME);
  return file;
}

// ================================================================ DECK B
async function deckTutorial() {
  const { pres, C } = newDeck("Tutorial: conectar un softphone externo a la maqueta IMS");
  pres.addSection({ title: "Tutorial" });
  let s = pres.addSlide({ masterName: "PORTADA", sectionTitle: "Tutorial" });
  s.addText("Conectar un softphone externo a la maqueta IMS", { placeholder: "title" });
  s.addText("Dos caminos: el UE IMS de la maqueta (conforme 3GPP) o un softphone comercial con el perfil SIP Digest de DEV", { placeholder: "body" });

  s = pres.addSlide({ masterName: "CONTENIDO", sectionTitle: "Tutorial" });
  s.addText("Elegir el camino según el cliente", { placeholder: "title" });
  card(s, C, { x: 0.6, y: 1.5, w: 5.9, h: 4.4, num: "A", head: "UE IMS de la maqueta", body: "pjsua parcheado (IMS-AKA + IPsec) en otro equipo Linux con Docker. Es el camino 3GPP: el P-CSCF negocia las SA y todo el tráfico va cifrado en integridad.\n\nRecomendado para demos y pruebas de conformidad." });
  card(s, C, { x: 6.8, y: 1.5, w: 5.9, h: 4.4, num: "B", color: C.accent2, head: "Zoiper / Linphone / MicroSIP", body: "No implementan IMS-AKA ni sec-agree. Requieren activar el perfil SIP Digest no-3GPP (TS 33.203 Anexo N) en el S-CSCF.\n\nSolo para DEV: con él activo la regla A4 deja de cumplirse para esos clientes." });

  s = pres.addSlide({ masterName: "CONTENIDO", sectionTitle: "Tutorial" });
  s.addText("Paso común: llegar a la red de la maqueta sin NAT", { placeholder: "title" });
  s.addText([
    { text: "En el host de la maqueta (una vez):", options: { bold: true, breakLine: true } },
    { text: "sudo sysctl -w net.ipv4.ip_forward=1", options: { fontFace: "Courier New", breakLine: true } },
    { text: "sudo iptables -I DOCKER-USER -s <LAN>/24 -d 172.32.0.0/24 -j ACCEPT", options: { fontFace: "Courier New", breakLine: true } },
    { text: " ", options: { breakLine: true } },
    { text: "En el equipo del softphone:", options: { bold: true, breakLine: true } },
    { text: "sudo ip route add 172.32.0.0/24 via <IP del host de la maqueta>", options: { fontFace: "Courier New", breakLine: true } },
    { text: " ", options: { breakLine: true } },
    { text: "Comprobar: ping 172.32.0.8 (P-CSCF) y que el DNS 172.32.0.2 resuelva ims.mnc001.mcc001.3gppnetwork.org.", options: {} },
  ], { x: 0.6, y: 1.5, w: 8.0, h: 4.8, fontSize: 15, color: C.text1, valign: "top", isTextBox: true });
  s.addShape("roundRect", { x: 8.9, y: 1.6, w: 3.8, h: 4.2, rectRadius: 0.15, fill: { color: C.background2 }, line: { color: C.background2 } });
  s.addText("Por qué sin NAT", { x: 9.1, y: 1.8, w: 3.4, h: 0.5, fontSize: 18, bold: true, color: C.text2, margin: 0, isTextBox: true });
  s.addText("ESP no atraviesa NAT sin encapsulado UDP, y el P-CSCF y RTPEngine anuncian direcciones 172.32.0.x. Con una ruta, el softphone ve esas direcciones directamente.", { x: 9.1, y: 2.4, w: 3.4, h: 3.2, fontSize: 14, color: C.text1, margin: 0, valign: "top", isTextBox: true });

  s = pres.addSlide({ masterName: "CONTENIDO", sectionTitle: "Tutorial" });
  s.addText("Camino A: el UE IMS en otro equipo", { placeholder: "title" });
  s.addText([
    { text: "1.  Copiar la carpeta maqueta-ims-3/softphone y construir: docker build -t mims3_softphone softphone/", options: { breakLine: true } },
    { text: "2.  Arrancar con capacidades de red: docker run -it --rm --net=host --cap-add NET_ADMIN --cap-add NET_RAW -v $PWD/softphone:/mnt/softphone mims3_softphone bash", options: { breakLine: true } },
    { text: "3.  Registrar el UE1: /mnt/softphone/scripts/ue.sh 1 (UE2: ue.sh 2)", options: { breakLine: true } },
    { text: "4.  En la consola de pjsua: m → sip:0100002@ims.mnc001.mcc001.3gppnetwork.org (IVR) o 0100004 (buzón)", options: { breakLine: true } },
    { text: "5.  Con red host, pjsua toma la IP del equipo: el Contact y las SA usan esa dirección.", options: {} },
  ], { x: 0.6, y: 1.5, w: 12.1, h: 4.6, fontSize: 15, color: C.text1, paraSpaceAfter: 10, valign: "top", isTextBox: true });
  s.addText("Esperado en el log: \"sec-agree: SA IPsec ESP establecidas\" y \"registration success, status=200\".", { x: 0.6, y: 6.1, w: 12.1, h: 0.5, fontSize: 14, italic: true, color: C.accent5, isTextBox: true });

  s = pres.addSlide({ masterName: "CONTENIDO", sectionTitle: "Tutorial" });
  s.addText("Camino B: softphone comercial con perfil Digest (DEV)", { placeholder: "title" });
  s.addText([
    { text: "Activar el perfil en el S-CSCF", options: { bold: true, breakLine: true } },
    { text: "scscf/scscf.cfg: #!define WITH_NON3GPP_DIGEST, luego docker restart mims3_scscf", options: { breakLine: true } },
    { text: " ", options: { breakLine: true } },
    { text: "Cuenta en Zoiper / Linphone / MicroSIP", options: { bold: true, breakLine: true } },
    { text: "Usuario y autenticación: 0010100001 (MSISDN)", options: { bullet: true, breakLine: true } },
    { text: "Dominio: ims.mnc001.mcc001.3gppnetwork.org · Proxy/outbound: 172.32.0.8:5060 UDP", options: { bullet: true, breakLine: true } },
    { text: "Contraseña: la clave de prueba UE1_KI de maqueta-ims-3/.env", options: { bullet: true, breakLine: true } },
    { text: "Códecs: PCMU/PCMA (FreeSWITCH responde en G.711)", options: { bullet: true } },
  ], { x: 0.6, y: 1.5, w: 8.0, h: 4.9, fontSize: 15, color: C.text1, paraSpaceAfter: 6, valign: "top", isTextBox: true });
  s.addShape("roundRect", { x: 8.9, y: 1.6, w: 3.8, h: 4.2, rectRadius: 0.15, fill: { color: C.background2 }, line: { color: C.accent4 } });
  s.addText("Antes de una demo", { x: 9.1, y: 1.8, w: 3.4, h: 0.5, fontSize: 18, bold: true, color: C.accent4, margin: 0, isTextBox: true });
  s.addText("Volver a comentar la línea (##!define) y reiniciar el S-CSCF. Con el perfil desactivado, un cliente Digest recibe 403 y la maqueta solo admite IMS-AKA.", { x: 9.1, y: 2.4, w: 3.4, h: 3.2, fontSize: 14, color: C.text1, margin: 0, valign: "top", isTextBox: true });

  s = pres.addSlide({ masterName: "CONTENIDO", sectionTitle: "Tutorial" });
  s.addText("Probar y diagnosticar", { placeholder: "title" });
  const diag = [
    ["Síntoma", "Causa probable", "Acción"],
    ["403 Authentication Failed", "Perfil Digest desactivado", "Camino A, o activar el perfil (DEV)"],
    ["Sin respuesta al REGISTER", "Falta la ruta a 172.32.0.0/24", "ip route y regla DOCKER-USER"],
    ["Llamada sin audio", "RTP con NAT o firewall", "Ruta directa; abrir UDP de RTPEngine"],
    ["sec-agree: fallo instalando SA", "SA residuales en el UE", "ip xfrm state flush; ip xfrm policy flush"],
  ];
  s.addTable(diag.map((r, i) => r.map((c) => ({ text: c, options: { bold: i === 0, color: i === 0 ? HEX.lt1 : HEX.dk1, fill: { color: i === 0 ? HEX.dk2 : (i % 2 ? HEX.lt2 : HEX.lt1) } } }))), {
    x: 0.6, y: 1.5, w: 12.1, colW: [3.6, 3.9, 4.6], fontSize: 14, fontFace: THEME.bodyFontFace, border: { type: "solid", pt: 0.5, color: HEX.accent6 }, rowH: 0.7, valign: "middle",
  });
  s.addText("Prueba rápida: llamar a 0100002 (IVR, pulsar 1) y a 0100003 (dejar un mensaje).", { x: 0.6, y: 5.6, w: 12.1, h: 0.6, fontSize: 15, color: C.text1, isTextBox: true });

  const file = path.join(OUT, "Tutorial_softphone_externo.pptx");
  await pres.writeFile({ fileName: file });
  await applyTheme(file, THEME);
  return file;
}

(async () => {
  console.log(await deckAvance());
  console.log(await deckTutorial());
})();
