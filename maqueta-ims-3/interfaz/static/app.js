"use strict";

const $ = (id) => document.getElementById(id);

/* ---------- pestañas ---------- */
document.querySelectorAll(".tab").forEach((b) => {
  b.addEventListener("click", () => {
    document.querySelectorAll(".tab").forEach((x) => x.classList.toggle("active", x === b));
    document.querySelectorAll(".panel").forEach((p) => p.classList.toggle("active", p.id === "tab-" + b.dataset.tab));
  });
});

/* ---------- helpers fetch ---------- */
async function jpost(url, body) {
  const r = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body || {}),
  });
  return r.json();
}

function setBusy(btn, busy) {
  if (busy) {
    btn.dataset.old = btn.innerHTML;
    btn.innerHTML = '<span class="spinner"></span>Procesando…';
    btn.disabled = true;
  } else {
    btn.innerHTML = btn.dataset.old || "";
    btn.disabled = false;
  }
}

/* ---------- estado ---------- */
async function loadStatus() {
  try {
    const s = await (await fetch("/api/status")).json();
    $("domain").textContent = s.domain;
    $("dnsbar").textContent =
      "resolución DNS: " + (s.dns.ip === s.dns.expected ? "OK (" + s.dns.ip + ")" : "FALLO (" + (s.dns.ip || "sin IP") + ")");

    const cg = $("containers");
    cg.innerHTML = "";
    s.containers.forEach((c) => {
      const d = document.createElement("div");
      d.className = "node";
      const up = c.running;
      d.innerHTML = `<span class="dot ${up ? "up" : "down"}"></span><b>${c.name}</b>` +
        `<small>${up ? c.status : "detenido"}${c.image ? " · " + c.image : ""}</small>`;
      cg.appendChild(d);
    });

    const lg = $("listeners");
    lg.innerHTML = "";
    s.listeners.forEach((l) => {
      const d = document.createElement("div");
      d.className = "node";
      d.innerHTML = `<span class="dot ${l.up ? "up" : "down"}"></span><b>${l.container}</b>` +
        `<small>puerto ${l.port} — ${l.up ? "escuchando" : "sin listener"}</small>`;
      lg.appendChild(d);
    });

    $("dns").innerHTML = `<div><b>Dominio</b> ${s.dns.domain}</div>` +
      `<div><b>IP resuelta</b> ${s.dns.ip || "—"}</div>` +
      `<div><b>IP esperada (P-CSCF)</b> ${s.dns.expected}</div>`;
  } catch (e) {
    $("dnsbar").textContent = "error consultando estado: " + e;
  }
}
setInterval(loadStatus, 4000);
loadStatus();

/* ---------- prueba E2E ---------- */
$("run-test").addEventListener("click", async () => {
  const btn = $("run-test");
  setBusy(btn, true);
  $("test-summary").classList.add("hidden");
  $("test-results").innerHTML = "";
  try {
    const t = await jpost("/api/test");
    const sum = $("test-summary");
    sum.classList.remove("hidden");
    sum.className = "summary " + (t.ok ? "ok" : "ko");
    sum.textContent = t.results.filter((r) => r.status === "FAIL").length === 0
      ? "✅ Prueba superada: TODO correcto"
      : `❌ Algunas comprobaciones fallaron: ${t.results.filter((r) => r.status === "FAIL").length} de ${t.results.length}`;
    const ul = $("test-results");
    ul.innerHTML = "";
    t.results.forEach((r) => {
      const li = document.createElement("li");
      li.innerHTML = `<span class="badge ${r.status}">${r.status}</span> <b>${r.name}</b>` +
        (r.detail ? `<div class="dim" style="font-size:12px">${r.detail}</div>` : "");
      ul.appendChild(li);
    });
  } catch (e) {
    $("test-summary").classList.remove("hidden");
    $("test-summary").className = "summary ko";
    $("test-summary").textContent = "Error: " + e;
  }
  setBusy(btn, false);
});

/* ---------- VMS ---------- */
function fmtSize(b) {
  return b >= 1024 ? (b / 1024).toFixed(1) + " KB" : b + " B";
}

function vmsMessagesHTML(mb) {
  if (!mb.list || !mb.list.length) {
    return `<div class="dim">Buzón ${mb.mailbox}: sin mensajes.</div>`;
  }
  const rows = mb.list.map((m) => {
    const dur = m.duration_s != null ? (m.duration_s + " s de grabación") : "";
    return `<div class="vms-msg">
        <span class="dot up"></span>
        <b>${m.name}</b>
        <small>${m.modified} · ${fmtSize(m.size)}${dur ? " · " + dur : ""}</small>
        <audio controls preload="none"
          src="/api/vms/media?mailbox=${mb.mailbox}&msg=${m.name}"></audio>
      </div>`;
  }).join("");
  return `<h3 class="vms-box-title">Buzón ${mb.mailbox}</h3>${rows}`;
}

async function loadVMS() {
  try {
    const v = await (await fetch("/api/vms")).json();
    let html = "";
    (v.mailboxes || []).forEach((m) => {
      html += `<div><b>Buzón ${m.mailbox}</b> ${m.messages} mensaje(s) — ` +
        `último: ${m.last || "ninguno"}</div>`;
    });
    html += `<div><b>Prompts de voz (vm-*)</b> ${v.prompts ? "presentes ✓" : "FALTAN ✗"}</div>`;
    $("vms-status").innerHTML = html || "<div class='dim'>sin datos</div>";
    $("vms-messages").innerHTML = (v.mailboxes || [])
      .map((mb) => vmsMessagesHTML(mb)).join("<hr>");
  } catch (e) {
    $("vms-status").textContent = "error: " + e;
  }
}
loadVMS();

$("vms-run").addEventListener("click", async () => {
  const btn = $("vms-run");
  setBusy(btn, true);
  $("vms-result").textContent = "Registrando UE1 y llamando al buzón 0100003…";
  try {
    const r = await jpost("/api/actions/vms", { ue: "1", dest: "0100003" });
    let txt =
      "Llamada UE1 → " + r.dest +
      " → " + (r.confirmed ? "CONFIRMED ✓" : "no confirmada ✗") + "\n" +
      "Mensaje grabado: " + r.messages_before + " → " + r.messages_after +
      "  (" + (r.ok ? "OK ✓" : "FALLO ✗") + ")\n";
    if (r.lines && r.lines.length) txt += "\n" + r.lines.join("\n") + "\n";
    $("vms-result").textContent = txt;
  } catch (e) {
    $("vms-result").textContent = "Error: " + e;
  }
  setBusy(btn, false);
loadVMS();

/* ---------- nuevo mensaje de voz desde la web ---------- */
const vmsAudio = {
  blob: null,
  stream: null,
  rec: null,
  chunks: [],
};

// convertidor -> WAV PCM16 mono 8 kHz (lo que Asterisk reproduce/graba)
async function toPcm16Wav8k(blob) {
  const AC = window.AudioContext || window.webkitAudioContext;
  if (!AC) throw new Error("AudioContext no soportado");
  const ctx = new AC();
  const ab = await blob.arrayBuffer();
  const buf = await ctx.decodeAudioData(ab);
  const src = buf.getChannelData(0);
  const SR = 8000;
  const n8 = Math.round(src.length * SR / buf.sampleRate);
  const w = new DataView(new ArrayBuffer(44 + n8 * 2));
  const W = (o, s) => { for (let i = 0; i < s.length; i++) w.setUint8(o + i, s.charCodeAt(i)); };
  W(0, "RIFF"); w.setUint32(4, 36 + n8 * 2, true);
  W(8, "WAVE"); W(12, "fmt "); w.setUint32(16, 16, true);
  w.setUint16(20, 1, true); w.setUint16(22, 1, true);
  w.setUint32(24, SR, true); w.setUint32(28, SR * 2, true);
  w.setUint16(32, 2, true); w.setUint16(34, 16, true);
  W(36, "data"); w.setUint32(40, n8 * 2, true);
  for (let i = 0; i < n8; i++) {
    const t = i * buf.sampleRate / SR;
    const i0 = Math.floor(t);
    const fr = t - i0;
    const v = src[Math.min(i0 + 1, src.length - 1)] * fr + src[i0] * (1 - fr);
    w.setInt16(44 + i * 2, Math.max(-32768, Math.min(32767, v * 32768)), true);
  }
  await ctx.close();
  return new Blob([w], { type: "audio/wav" });
}

$("vms-rec").addEventListener("click", async () => {
  try {
    vmsAudio.stream = await navigator.mediaDevices.getUserMedia({ audio: true });
    vmsAudio.chunks = [];
    vmsAudio.rec = new MediaRecorder(vmsAudio.stream);
    vmsAudio.rec.ondataavailable = (e) => vmsAudio.chunks.push(e.data);
    vmsAudio.rec.onstop = () => {
      vmsAudio.blob = new Blob(vmsAudio.chunks, { type: vmsAudio.rec.mimeType });
      previewVmsAudio(vmsAudio.blob);
    };
    vmsAudio.rec.start();
    $("vms-rec").classList.add("hidden");
    $("vms-stop-rec").classList.remove("hidden");
    $("vms-send-status").textContent = "grabando…";
  } catch (e) {
    $("vms-send-status").textContent = "micrófono no disponible: " + e;
  }
});

$("vms-stop-rec").addEventListener("click", () => {
  vmsAudio.rec && vmsAudio.rec.stop();
  vmsAudio.stream && vmsAudio.stream.getTracks().forEach((t) => t.stop());
  $("vms-rec").classList.remove("hidden");
  $("vms-stop-rec").classList.add("hidden");
});

$("vms-file").addEventListener("change", (e) => {
  const f = e.target.files[0];
  if (!f) return;
  vmsAudio.blob = f;
  previewVmsAudio(f);
});

function previewVmsAudio(blob) {
  const p = $("vms-preview");
  p.src = URL.createObjectURL(blob);
  p.classList.remove("hidden");
  $("vms-send-status").textContent = "audio listo · " + fmtSize(blob.size);
  $("vms-send").disabled = false;
}

$("vms-send").addEventListener("click", async () => {
  const btn = $("vms-send");
  setBusy(btn, true);
  $("vms-send-result").textContent = "convirtiendo a PCM16 8 kHz…";
  try {
    const wav = await toPcm16Wav8k(vmsAudio.blob);
    $("vms-send-result").textContent = "enviando al AS y llamando a 0100003…";
    const fd = new FormData();
    fd.append("audio", wav, "web_message.wav");
    fd.append("ue", "1");
    fd.append("dest", "0100003");
    const r = await (await fetch("/api/vms/audio", { method: "POST", body: fd })).json();
    let txt = (r.ok ? "✔ " : "✘ ") +
      "Llamada UE1 → " + r.dest + (r.confirmed ? " CONFIRMED" : " (no confirmada)") +
      " · duración " + (r.duration_s ?? "?") + " s\n" +
      "Mensaje grabado en buzón: " + r.messages_before + " → " + r.messages_after + "\n";
    if (r.error) txt = "Error: " + r.error;
    if (r.lines && r.lines.length) txt += "\n" + r.lines.join("\n");
    $("vms-send-result").textContent = txt;
  } catch (e) {
    $("vms-send-result").textContent = "Error: " + e;
  }
  setBusy(btn, false);
  $("vms-send").disabled = !vmsAudio.blob;
  loadVMS();
});
});

/* ---------- operación ---------- */
async function action(acc, body) {
  const out = acc === "vms" ? $("vms-result") : $("op-result");
  out.textContent = "Ejecutando " + acc + "…";
  const labels = { register: "Registro UE", call: "Llamada", stop: "Detener UEs", vms: "Prueba VMS" };
  const r = await jpost("/api/actions/" + acc, body);
  let txt = (labels[acc] || acc) + (acc === "register" ? body.ue : "") +
    " → " + (r.ok ? "OK ✓" : "FALLO ✗") + "\n";
  if (r.lines && r.lines.length) txt += r.lines.join("\n") + "\n";
  if (r.detail) txt += r.detail + "\n";
  out.textContent = txt;
}

/* ---------- configuración ---------- */
let CONFIG = null;
async function loadConfig() {
  CONFIG = await (await fetch("/api/config")).json();
  const c = $("config-ues");
  c.innerHTML = "";
  ["1", "2"].forEach((k) => {
    const u = CONFIG.ues[k];
    const card = document.createElement("div");
    card.className = "node";
    card.style.marginBottom = "8px";
    card.innerHTML =
      `<b>UE${k}</b>` +
      `<label>IMSI <input data-ue="${k}" data-f="imsi" value="${u.imsi}"></label>` +
      `<label>MSISDN <input data-ue="${k}" data-f="msisdn" value="${u.msisdn}"></label>` +
      `<label>Password (ki) <input data-ue="${k}" data-f="ki" value="${u.ki}"></label>` +
      (u.port ? `<label>Puerto SIP <input data-ue="${k}" data-f="port" value="${u.port}"></label>` : "");
    c.appendChild(card);
  });
  $("ifc-info").innerHTML =
    `<div><b>iFC (HSS)</b> ${CONFIG.ifc.file}</div>` +
    `<div><b>Regla</b> ${CONFIG.ifc.rule}</div>` +
    `<div><b>Origen de datos</b> ${CONFIG.source}</div>`;
}
loadConfig();

async function saveConfig() {
  const body = {};
  document.querySelectorAll("#config-ues input").forEach((i) => {
    const k = i.dataset.ue, f = i.dataset.f;
    body[k] = body[k] || {};
    body[k][f] = i.value;
  });
  const r = await jpost("/api/config", body);
  $("provision-result").textContent = r.ok ? "Configuración guardada ✓" : "Error: " + (r.error || "?");
  loadConfig();
}

async function provision() {
  const btn = [...document.querySelectorAll("button")].find((b) => b.textContent.includes("Provisionar"));
  setBusy(btn, true);
  $("provision-result").textContent = "Provisionando en PyHSS…";
  const r = await jpost("/api/config/provision");
  let txt = "";
  (r.results || []).forEach((s) => { txt += `${s.tag} ${s.label} → ${s.ok ? "OK" : "FALLO"}  (${s.detail})\n`; });
  $("provision-result").textContent = txt || (r.ok ? "Provisionado ✓" : "Error");
  setBusy(btn, false);
}

/* ---------- logs ---------- */
const LOG_NODES = ["mims3_pcscf", "mims3_scscf", "mims3_icscf", "mims3_asfront", "mims3_freeswitch", "mims3_pyhss_hss", "mims3_pyhss_api", "mims3_rtpengine", "mims3_dns", "mims3_softphone"];
const ls = $("log-select");
ls.innerHTML = LOG_NODES.map((n) => `<option value="${n}">${n}</option>`).join("");
async function loadLogs() {
  $("log-output").textContent = "cargando…";
  const r = await (await fetch("/api/logs?name=" + ls.value)).json();
  $("log-output").textContent = r.error ? ("ERROR: " + r.error) : r.logs.slice(-120).join("\n");
}
ls.addEventListener("change", loadLogs);
document.querySelector("#tab-logs .mini, #tab-logs button").addEventListener("click", loadLogs);