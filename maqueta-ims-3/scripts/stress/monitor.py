#!/usr/bin/env python3
"""monitor.py — muestreo de recursos de un nodo DEV durante las pruebas de estrés.

Cada INTERVAL s escribe en dos CSV:
  host_<nodo>.csv : cpu_pct, load1, mem_used_mb, mem_total_mb, rx_kbps, tx_kbps (NIC),
                    rx_pps, tx_pps, tcp_estab
  ctn_<nodo>.csv  : por contenedor mims3_*: cpu_pct, mem_mb, net_rx_kb, net_tx_kb (docker stats)

Uso (en el nodo): python3 monitor.py --node core --secs 900 --interval 2 --dir /tmp/stress
"""
import argparse, csv, json, os, subprocess, threading, time


def cpu_times():
    v = list(map(int, open("/proc/stat").readline().split()[1:]))
    idle = v[3] + v[4]
    return sum(v), idle


def mem():
    m = {l.split(":")[0]: int(l.split()[1]) for l in open("/proc/meminfo")}
    return (m["MemTotal"] - m["MemAvailable"]) // 1024, m["MemTotal"] // 1024


def net(dev):
    for l in open("/proc/net/dev"):
        if l.strip().startswith(dev + ":"):
            f = l.split(":")[1].split()
            return int(f[0]), int(f[1]), int(f[8]), int(f[9])  # rx_bytes, rx_pkts, tx_bytes, tx_pkts
    return 0, 0, 0, 0


def tcp_estab():
    n = 0
    for p in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            n += sum(1 for l in open(p).readlines()[1:] if l.split()[3] == "01")
        except OSError:
            pass
    return n


def docker_loop(path, secs, interval):
    end = time.time() + secs
    with open(path, "w", newline="") as f:
        w = csv.writer(f); w.writerow(["t", "container", "cpu_pct", "mem_mb", "net_rx_kb", "net_tx_kb"])
        while time.time() < end:
            t = round(time.time(), 1)
            out = subprocess.run(["docker", "stats", "--no-stream", "--format", "{{json .}}"],
                                 capture_output=True, text=True).stdout
            for l in out.splitlines():
                d = json.loads(l)
                if not d["Name"].startswith("mims3_"):
                    continue
                def size(x):
                    x = x.strip(); u = {"B": 1 / 1024, "kB": 1, "KiB": 1, "MB": 1024, "MiB": 1024, "GB": 1048576, "GiB": 1048576}
                    for k in sorted(u, key=len, reverse=True):
                        if x.endswith(k):
                            return float(x[:-len(k)]) * u[k]
                    return 0.0
                rx, tx = d["NetIO"].split("/")
                w.writerow([t, d["Name"].split(".")[0], d["CPUPerc"].rstrip("%"),
                            round(size(d["MemUsage"].split("/")[0]) / 1024, 1), round(size(rx), 1), round(size(tx), 1)])
            f.flush()
            time.sleep(max(0, interval - 1))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--node", required=True); ap.add_argument("--secs", type=int, default=900)
    ap.add_argument("--interval", type=float, default=2); ap.add_argument("--dir", default="/tmp/stress")
    ap.add_argument("--nic", default="ens18")
    a = ap.parse_args(); os.makedirs(a.dir, exist_ok=True)
    threading.Thread(target=docker_loop, args=(f"{a.dir}/ctn_{a.node}.csv", a.secs, a.interval * 2), daemon=True).start()
    end = time.time() + a.secs
    c0, n0 = cpu_times(), net(a.nic); t0 = time.time()
    with open(f"{a.dir}/host_{a.node}.csv", "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["t", "cpu_pct", "load1", "mem_used_mb", "mem_total_mb", "rx_kbps", "tx_kbps", "rx_pps", "tx_pps", "tcp_estab"])
        while time.time() < end:
            time.sleep(a.interval)
            c1, n1, t1 = cpu_times(), net(a.nic), time.time(); dt = t1 - t0
            tot, idle = c1[0] - c0[0], c1[1] - c0[1]
            used, total = mem()
            w.writerow([round(t1, 1), round(100 * (tot - idle) / tot, 1) if tot else 0,
                        os.getloadavg()[0], used, total,
                        round((n1[0] - n0[0]) * 8 / 1000 / dt, 1), round((n1[2] - n0[2]) * 8 / 1000 / dt, 1),
                        round((n1[1] - n0[1]) / dt), round((n1[3] - n0[3]) / dt), tcp_estab()])
            f.flush(); c0, n0, t0 = c1, n1, t1


if __name__ == "__main__":
    main()
