// ui_screens.mjs — capturas de la UI de la maqueta por pestaña (Chrome DevTools Protocol,
// sin dependencias: WebSocket nativo de Node >= 22).
// Uso: node ui_screens.mjs http://192.168.5.233:8090/ <dir_salida> [espera_ms_por_pestaña]
import { spawn } from "node:child_process";
import { writeFileSync, mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const [url, outDir, waitArg] = process.argv.slice(2);
const WAIT = Number(waitArg || 4000);
const port = 9333;
const chrome = spawn("google-chrome", ["--headless=new", "--no-sandbox", "--disable-gpu", "--hide-scrollbars",
  `--remote-debugging-port=${port}`, `--user-data-dir=${mkdtempSync(join(tmpdir(), "cdp-"))}`, "about:blank"],
  { stdio: "ignore" });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

let target;
for (let i = 0; i < 40 && !target; i++) {
  await sleep(250);
  try { target = (await (await fetch(`http://127.0.0.1:${port}/json`)).json()).find((t) => t.type === "page"); } catch {}
}
const ws = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((r) => ws.addEventListener("open", r));
let id = 0; const pending = new Map();
ws.addEventListener("message", (e) => { const m = JSON.parse(e.data); if (pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); } });
const cmd = (method, params = {}) => new Promise((r) => { const i = ++id; pending.set(i, r); ws.send(JSON.stringify({ id: i, method, params })); });
const evalJs = async (expr) => (await cmd("Runtime.evaluate", { expression: expr, awaitPromise: true, returnByValue: true })).result?.result?.value;

await cmd("Emulation.setDeviceMetricsOverride", { width: 1440, height: 1000, deviceScaleFactor: 1, mobile: false });
await cmd("Page.enable");
await cmd("Page.navigate", { url });
await sleep(WAIT);
const tabs = await evalJs(`[...document.querySelectorAll("button.tab")].map(b => [b.dataset.tab, b.textContent.trim()])`);
let n = 1;
for (const [tab, label] of tabs) {
  await evalJs(`document.querySelector('button.tab[data-tab="${tab}"]').click()`);
  await sleep(WAIT);
  const h = await evalJs(`Math.min(4000, document.documentElement.scrollHeight)`);
  await cmd("Emulation.setDeviceMetricsOverride", { width: 1440, height: h, deviceScaleFactor: 1, mobile: false });
  await sleep(500);
  const shot = await cmd("Page.captureScreenshot", { format: "png" });
  const file = join(outDir, `${String(n++).padStart(2, "0")}_ui_${tab}.png`);
  writeFileSync(file, Buffer.from(shot.result.data, "base64"));
  console.log(file, label, `${h}px`);
}
ws.close(); chrome.kill();
