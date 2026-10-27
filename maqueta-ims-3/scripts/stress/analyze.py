#!/usr/bin/env python3
"""analyze.py — resume una ejecución de run_stress.sh en tablas Markdown y gráficas SVG.

Uso: analyze.py <dir_run> <dir_salida_graficas>
Escribe <dir_salida>/resumen.md (tablas) y graf_*.svg (CPU, RAM, red por nodo,
llamadas concurrentes y tiempos de establecimiento), sin dependencias externas.
"""
import csv, json, os, statistics, sys
from collections import defaultdict

RUN, OUT = sys.argv[1], sys.argv[2]
os.makedirs(OUT, exist_ok=True)
NODES = {"core": "Core IMS (.231)", "db": "Base de datos (.232)", "ivr": "IVR+VMS (.233)"}
COLORS = {"core": "#1f6feb", "db": "#8250df", "ivr": "#d1242f"}

stages = []  # (nombre, t_ini, t_fin)
opened = {}
for r in csv.DictReader(open(f"{RUN}/stages.csv")):
    if r["event"] == "start":
        opened[r["stage"]] = float(r["t"])
    elif r["stage"] in opened:
        stages.append((r["stage"], opened.pop(r["stage"]), float(r["t"])))
T0 = min(s[1] for s in stages) - 60
T1 = max(s[2] for s in stages) + 20

ev = [json.loads(l) for l in open(f"{RUN}/results.jsonl") if l.strip()]
host = {n: [{k: float(v) for k, v in r.items()} for r in csv.DictReader(open(f"{RUN}/host_{n}.csv"))]
        for n in NODES if os.path.exists(f"{RUN}/host_{n}.csv")}
ctn = defaultdict(list)
for n in NODES:
    p = f"{RUN}/ctn_{n}.csv"
    if os.path.exists(p):
        for r in csv.DictReader(open(p)):
            ctn[(n, r["container"])].append((float(r["t"]), float(r["cpu_pct"] or 0), float(r["mem_mb"] or 0)))


def pct(v, p):
    if not v:
        return "—"
    v = sorted(v); k = (len(v) - 1) * p / 100; f = int(k)
    return round(v[f] + (v[min(f + 1, len(v) - 1)] - v[f]) * (k - f), 1)


def in_stage(t, s):
    return s[1] <= t <= s[2] + 30  # las llamadas terminan hasta HOLD s después del fin de etapa


md = ["# Resumen de la ejecución\n"]
# --- tabla funcional por etapa
md.append("| Etapa | Registros OK / intentos | Registro p50 / p95 (ms) | Llamadas OK / intentos | Éxito | "
          "Establecimiento p50 / p95 / máx (ms) | RTP recibido / enviado (media, mín) | BYE 200 | Errores |")
md.append("|---|---|---|---|---|---|---|---|---|")
summary = {}
for s in stages:
    E = [e for e in ev if e.get("label") == s[0]]
    reg = [e for e in E if e["ev"] == "register"]; calls = [e for e in E if e["ev"] == "call"]
    ok = [c for c in calls if c.get("code") == 200]; err = [e for e in E if e["ev"] == "error"]
    ratio = [c["rx_ratio"] for c in ok if "rx_ratio" in c]
    summary[s[0]] = dict(calls=len(calls), ok=len(ok), setup=[c["setup_ms"] for c in ok])
    codes = defaultdict(int)
    for c in calls:
        if c.get("code") != 200:
            codes[c.get("code")] += 1
    md.append(f"| {s[0]} | {sum(1 for r in reg if r['code'] == 200)} / {len(reg)} | "
              f"{pct([r['ms'] for r in reg], 50)} / {pct([r['ms'] for r in reg], 95)} | "
              f"{len(ok)} / {len(calls)} | {round(100 * len(ok) / len(calls), 1) if calls else '—'} % | "
              f"{pct(summary[s[0]]['setup'], 50)} / {pct(summary[s[0]]['setup'], 95)} / "
              f"{max(summary[s[0]]['setup']) if ok else '—'} | "
              f"{round(statistics.mean(ratio), 3) if ratio else '—'} , {min(ratio) if ratio else '—'} | "
              f"{sum(1 for c in ok if c.get('bye') == 200)} / {len(ok)} | "
              f"{len(err)}{' ' + str(dict(codes)) if codes else ''} |")

# --- recursos de host por etapa
md.append("\n## Recursos de host por nodo y etapa\n")
md.append("| Etapa | Nodo | CPU media / máx (%) | Load1 máx | RAM usada máx (MB) | Red RX media / máx (kbit/s) | Red TX media / máx (kbit/s) | Conexiones TCP máx |")
md.append("|---|---|---|---|---|---|---|---|")
for s in [("reposo", T0, stages[0][1])] + stages:
    for n, rows in host.items():
        R = [r for r in rows if s[1] <= r["t"] <= s[2]]
        if not R:
            continue
        g = lambda k: [r[k] for r in R]  # noqa: E731
        md.append(f"| {s[0]} | {NODES[n]} | {round(statistics.mean(g('cpu_pct')), 1)} / {max(g('cpu_pct'))} | "
                  f"{round(max(g('load1')), 2)} | {int(max(g('mem_used_mb')))} / {int(R[0]['mem_total_mb'])} | "
                  f"{round(statistics.mean(g('rx_kbps')))} / {int(max(g('rx_kbps')))} | "
                  f"{round(statistics.mean(g('tx_kbps')))} / {int(max(g('tx_kbps')))} | {int(max(g('tcp_estab')))} |")

# --- contenedores: pico de CPU y RAM en toda la prueba
md.append("\n## Contenedores: picos durante la prueba\n")
md.append("| Nodo | Contenedor | CPU media en carga (%) | CPU máx (%) | RAM reposo (MB) | RAM máx (MB) |")
md.append("|---|---|---|---|---|---|")
load_from = min(s[1] for s in stages if s[0].startswith("C_"))
for (n, c), rows in sorted(ctn.items(), key=lambda kv: -max(r[1] for r in kv[1])):
    idle = [r[2] for r in rows if r[0] < stages[0][2]] or [rows[0][2]]
    busy = [r[1] for r in rows if r[0] >= load_from]
    md.append(f"| {NODES[n]} | {c} | {round(statistics.mean(busy), 1) if busy else '—'} | {max(r[1] for r in rows)} | "
              f"{round(statistics.mean(idle), 1)} | {max(r[2] for r in rows)} |")
open(f"{OUT}/resumen.md", "w").write("\n".join(md) + "\n")


# --- gráficas SVG
W, H, PL, PR, PT, PB = 1100, 360, 70, 160, 40, 45


def chart(fname, title, ylabel, series, ymax=None):
    xs = lambda t: PL + (t - T0) / (T1 - T0) * (W - PL - PR)  # noqa: E731
    vals = [v for _, pts, _ in series for _, v in pts]
    top = ymax or max(vals + [1]) * 1.1
    ys = lambda v: H - PB - v / top * (H - PT - PB)  # noqa: E731
    o = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" font-family="Arial, sans-serif" font-size="12">',
         f'<rect width="{W}" height="{H}" fill="#fff"/>',
         f'<text x="{PL}" y="22" font-size="15" font-weight="bold">{title}</text>']
    for i, s in enumerate(stages):  # bandas de etapa
        o.append(f'<rect x="{xs(s[1]):.1f}" y="{PT}" width="{max(1, xs(s[2]) - xs(s[1])):.1f}" height="{H - PT - PB}" '
                 f'fill="{"#f2f6fc" if i % 2 else "#fbf7ee"}"/>')
        o.append(f'<text x="{xs(s[1]) + 2:.1f}" y="{PT + 12}" font-size="10" fill="#555">{s[0]}</text>')
    for k in range(6):
        v = top * k / 5; y = ys(v)
        o.append(f'<line x1="{PL}" x2="{W - PR}" y1="{y:.1f}" y2="{y:.1f}" stroke="#ddd"/>'
                 f'<text x="{PL - 6}" y="{y + 4:.1f}" text-anchor="end">{v:.0f}</text>')
    for m in range(0, int(T1 - T0) + 1, 120):
        x = xs(T0 + m)
        o.append(f'<text x="{x:.1f}" y="{H - PB + 16}" text-anchor="middle">{m // 60} min</text>')
    o.append(f'<text x="16" y="{(H) / 2}" transform="rotate(-90 16 {H / 2})" text-anchor="middle">{ylabel}</text>')
    for j, (name, pts, color) in enumerate(series):
        if not pts:
            continue
        d = " ".join(f"{xs(t):.1f},{ys(v):.1f}" for t, v in pts if T0 <= t <= T1)
        o.append(f'<polyline fill="none" stroke="{color}" stroke-width="1.6" points="{d}"/>')
        o.append(f'<rect x="{W - PR + 12}" y="{PT + 18 * j}" width="12" height="12" fill="{color}"/>'
                 f'<text x="{W - PR + 30}" y="{PT + 10 + 18 * j}">{name}</text>')
    o.append("</svg>")
    open(f"{OUT}/{fname}", "w").write("\n".join(o))


chart("graf_cpu_host.svg", "CPU de host por nodo", "% CPU",
      [(NODES[n], [(r["t"], r["cpu_pct"]) for r in rows], COLORS[n]) for n, rows in host.items()], 100)
chart("graf_ram_host.svg", "RAM usada por nodo", "MB",
      [(NODES[n], [(r["t"], r["mem_used_mb"]) for r in rows], COLORS[n]) for n, rows in host.items()])
chart("graf_red_host.svg", "Tráfico de red (RX+TX) de la NIC por nodo", "kbit/s",
      [(NODES[n], [(r["t"], r["rx_kbps"] + r["tx_kbps"]) for r in rows], COLORS[n]) for n, rows in host.items()])
palette = ["#1f6feb", "#d1242f", "#2da44e", "#bf8700", "#8250df", "#57606a", "#cf222e", "#0969da"]
top = sorted(ctn.items(), key=lambda kv: -max(r[1] for r in kv[1]))[:8]
chart("graf_cpu_contenedores.svg", "CPU por contenedor (8 de mayor consumo)", "% CPU (100 = 1 núcleo)",
      [(c.replace("mims3_", ""), [(r[0], r[1]) for r in rows], palette[i]) for i, ((n, c), rows) in enumerate(top)])
# llamadas concurrentes reconstruidas de los eventos (fin = t; inicio = t - hold - setup)
conc = []
calls = [e for e in ev if e["ev"] == "call" and e.get("code") == 200]
for t in range(int(T0), int(T1), 2):
    conc.append((t, sum(1 for c in calls if c["t"] - (c["rtp_tx"] * 0.02) <= t <= c["t"])))
chart("graf_llamadas_concurrentes.svg", "Llamadas activas con medios (reconstruido de los eventos)", "llamadas",
      [("llamadas activas", conc, "#2da44e")])
chart("graf_establecimiento.svg", "Tiempo de establecimiento por llamada (INVITE → 200 OK)", "ms",
      [("setup_ms", sorted((c["t"] - c["rtp_tx"] * 0.02, c["setup_ms"]) for c in calls), "#bf8700")])
print(open(f"{OUT}/resumen.md").read())
