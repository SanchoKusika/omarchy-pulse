// Run with: deno run --allow-read tests/model.test.js
// Model.js is a QML JavaScript resource with no ES exports, so it is
// evaluated here rather than imported.

const source = Deno.readTextFileSync(new URL("../Model.js", import.meta.url))
const M = new Function("var module = { exports: {} };" + source + "; return module.exports")()

let failures = 0
function check(name, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected)
  if (!ok) {
    failures++
    console.log("FAIL " + name + "\n  expected " + JSON.stringify(expected) + "\n  got      " + JSON.stringify(actual))
  }
}

// ---- settings
check("defaults", M.normalize(undefined), { style: "pulse", metric: "cpu", metrics: ["cpu"], metricOrder: ["cpu", "mem", "gpu", "temp", "gpuTemp"], interval: 2, alert: 90 })
check("unknown style falls back", M.normalize({ style: "<b>x</b>" }).style, "pulse")
check("interval clamps low", M.normalize({ interval: 0 }).interval, 1)
check("interval clamps high", M.normalize({ interval: 999 }).interval, 10)
check("interval junk", M.normalize({ interval: "abc" }).interval, 2)
check("alert clamps", M.normalize({ alert: 5 }).alert, 50)
check("style cycles forward", M.nextStyle("text"), "pulse")
check("style cycles back", M.nextStyle("pulse", -1), "text")

// ---- metrics
check("defaults include metric", M.normalize({}).metric, "cpu")
check("unknown metric falls back", M.normalize({ metric: "fan" }).metric, "cpu")
check("gpu metric kept", M.normalize({ metric: "gpu" }).metric, "gpu")
check("metrics array kept", M.normalize({ metrics: ["cpu", "gpu"] }).metrics, ["cpu", "gpu"])
check("metrics array order preserved", M.normalize({ metrics: ["gpu", "cpu", "temp", "mem"] }).metrics, ["gpu", "cpu", "temp", "mem"])
check("metrics all expands", M.normalize({ metric: "all" }).metrics, ["cpu", "mem", "gpu", "temp", "gpuTemp"])
check("metric cycles", M.nextMetric("gpuTemp"), "cpu")
check("metric cycles back", M.nextMetric("cpu", -1), "gpuTemp")
check("icons are single glyphs", Object.values(M.ICONS).map(s => [...s].length), [1, 1, 1, 1, 1])
check("icons are the md glyphs", Object.values(M.ICONS).map(s => s.codePointAt(0).toString(16)), ["f4bc", "efc5", "f0fb2", "f050f", "f050f"])

// ---- gpu parsing
check("parse nvidia gpu", M.parseGpu("80, 25, 2662, 4096, 50\n", "nvidia"), {
  ok: true,
  gpu: 80,
  vramUsed: 2662 * 1024 * 1024,
  vramTotal: 4096 * 1024 * 1024,
  temp: 50
})
check("parse amd gpu", M.parseGpu("45, 1000, 2000\n", "amdgpu"), {
  ok: true,
  gpu: 45,
  vramUsed: 1000,
  vramTotal: 2000,
  temp: NaN
})
check("parse gpu empty", M.parseGpu("", "nvidia").ok, false)

check("same entry ignores key order", M.sameEntry({ id: "a", style: "bars" }, { style: "bars", id: "a" }), true)
check("same entry sees a change", M.sameEntry({ id: "a", style: "bars" }, { id: "a", style: "text" }), false)
check("same entry sees a missing key", M.sameEntry({ id: "a" }, { id: "a", metric: "cpu" }), false)

// ---- temperature scale
check("temp floor", M.tempFraction(25), 0)
check("temp mid", M.tempFraction(65), 0.5)
check("temp ceil", M.tempFraction(120), 1)
check("temp unknown", M.tempFraction(NaN), 0)

// ---- alert hysteresis
check("alert turns on at threshold", M.alertState(false, 90, 90, 5), true)
check("alert stays off below", M.alertState(false, 89, 90, 5), false)
check("alert holds inside the margin", M.alertState(true, 86, 90, 5), true)
check("alert clears below the margin", M.alertState(true, 84, 90, 5), false)
check("unknown clears alert", M.alertState(true, -1, 90, 5), false)
check("NaN clears alert", M.alertState(true, NaN, 90, 5), false)

// ---- cpu
const stat1 = "cpu  100 0 100 700 100 0 0 0 0 0\ncpu0 50 0 50 350 50 0 0 0 0 0\ncpu1 50 0 50 350 50 0 0 0 0 0\nintr 1 2 3\n"
const stat2 = "cpu  200 0 200 1300 100 0 0 0 0 0\ncpu0 1 1 1 1\ncpu1 1 1 1 1\n"
const c1 = M.parseCpu(stat1), c2 = M.parseCpu(stat2)
check("threads counted", c1.threads, 2)
check("idle includes iowait", c1.idle, 800)
check("cpu percent", Math.round(M.cpuPercent(c1, c2)), 25)
check("first sample is unknown", M.cpuPercent(null, c2), -1)
check("garbage stat", M.parseCpu("nonsense").ok, false)
check("backwards counters are unknown", M.cpuPercent(c2, c1), -1)

check("cores parsed", c1.cores.length, 2)
check("core percents", M.corePercents(c1, M.parseCpu("cpu 1 1 1 1\ncpu0 100 0 100 400 50 0 0 0\ncpu1 50 0 50 350 50 0 0 0\n")).map(Math.round), [67, -1])
check("core percents without history", M.corePercents(null, c1), [-1, -1])

// ---- memory
const mem = M.parseMeminfo("MemTotal:  1000 kB\nMemFree: 100 kB\nMemAvailable:  400 kB\nSwapTotal: 200 kB\nSwapFree: 150 kB\n")
check("mem used", mem.used, 600 * 1024)
check("swap used", mem.swapUsed, 50 * 1024)
check("mem fraction", M.fraction(mem.used, mem.total), 0.6)
check("fraction with zero total", M.fraction(5, 0), 0)

// ---- network
const dev = [
  "Inter-|   Receive", " face |bytes",
  "    lo: 9999 1 0 0 0 0 0 0 9999 1 0 0 0 0 0 0",
  "  eno1: 1000 1 0 0 0 0 0 0 500 1 0 0 0 0 0 0",
  "wlp4s0: 2000 1 0 0 0 0 0 0 700 1 0 0 0 0 0 0",
  "docker0: 5555 1 0 0 0 0 0 0 5555 1 0 0 0 0 0 0",
  "tailscale0: 777 1 0 0 0 0 0 0 777 1 0 0 0 0 0 0"
].join("\n")
check("net sums real links only", M.parseNetDev(dev), { rx: 3000, tx: 1200, ok: true })
check("rate", M.rate(1000, 3000, 2), 1000)
check("counter reset reads zero", M.rate(3000, 10, 2), 0)
check("zero interval reads zero", M.rate(0, 10, 0), 0)

// ---- misc /proc
check("load", M.parseLoad("0.80 0.49 0.35 1/1350 12126"), [0.8, 0.49, 0.35])
check("uptime", M.parseUptime("1362.66 21235.44"), 1362)
check("uptime parts", M.uptimeParts(90061), { days: 1, hours: 1, minutes: 1 })
check("temp", M.parseTemp("54250\n"), 54.25)
check("temp junk", isNaN(M.parseTemp("hot")), true)
check("temp impossible", isNaN(M.parseTemp("999000")), true)

// ---- sensor choice
const hw = "/sys/class/hwmon/hwmon0\tADP0\n/sys/class/hwmon/hwmon2\tnvme\n/sys/class/hwmon/hwmon5\tacpitz\n/sys/class/hwmon/hwmon3\tk10temp\n"
check("prefers k10temp", M.pickSensor(hw), "/sys/class/hwmon/hwmon3/temp1_input")
check("falls back to acpitz", M.pickSensor("/sys/class/hwmon/hwmon5\tacpitz"), "/sys/class/hwmon/hwmon5/temp1_input")
check("no sensor", M.pickSensor("/sys/class/hwmon/hwmon2\tnvme"), "")
check("rejects odd paths", M.pickSensor("/etc/passwd\tk10temp"), "")

// ---- disk
check("df with header", M.parseDf("     1B-blocks        Used\n998037782528 45540020224\n"), { size: 998037782528, used: 45540020224, ok: true })
check("df garbage", M.parseDf("df: /: No such file").ok, false)

// ---- top: names are untrusted text from other programs
const top = [
  "    PID USER      PR  NI    VIRT    RES    SHR S  %CPU  %MEM     TIME+ COMMAND",
  "  10786 sancho    20   0 5739712 478064 124272 S  12.5   6.0   0:19.50 claude",
  "  12121 sancho    20   0    7456   5668   3504 R   2.4   0.1   0:00.02 top",
  "   4242 sancho    20   0    7456   5668   3504 S   3.0   1.5   0:00.02 Web Content",
  "   4243 sancho    20   0    7456   5668   3504 S   1.0   0.5   0:00.02 <img src=x.invalid>",
  "   4244 sancho    20   0    7456   5668   3504 S   0.5   0.5   0:00.02 a-really-long-process-name-that-goes-on"
].join("\n")
const procs = M.parseTop(top, 5)
check("top skips header and itself", procs.map(p => p.name).slice(0, 2), ["claude", "Web Content"])
check("top cpu", procs[0].cpu, 12.5)
check("markup is neutralized", procs[2].name, "img src=x.invalid")
check("long names are bounded", procs[3].name.length, 24)
check("top respects limit", M.parseTop(top, 1).length, 1)
check("control characters dropped", M.cleanName("ev\u0007il\nname"), "evilname")

// ---- formatting
check("bytes GB", M.formatBytes(4.6 * 1024 ** 3), "4.6 GB")
check("bytes big", M.formatBytes(930 * 1024 ** 3), "930 GB")
check("bytes small", M.formatBytes(512), "512 B")
check("rate", M.formatRate(1.25 * 1024 * 1024), "1.3 MB/s")
check("localized digits", M.formatBytes(4.5 * 1024 ** 3, (v, d) => Number(v).toFixed(d).replace(".", ",")), "4,5 GB")

check("pair shares unit", M.formatPair(4.4 * 1024 ** 3, 7.6 * 1024 ** 3), "4.4/7.6 GB")
check("pair mixed units", M.formatPair(40 * 1024, 13.2 * 1024 ** 3), "40.0 KB/13.2 GB")

// ---- mood
check("mood waking", M.mood(-1), "waking")
check("mood idle", M.mood(3), "idle")
check("mood calm", M.mood(10), "calm")
check("mood busy", M.mood(40), "busy")
check("mood hard", M.mood(70), "hard")
check("mood redline follows alert", M.mood(85, 80), "redline")

// ---- history
let h = []
for (let i = 0; i < 30; i++) h = M.pushHistory(h, i, 24)
check("history bounded", h.length, 24)
check("history keeps newest", h[23], 29)

if (failures > 0) {
  console.log(failures + " check(s) failed")
  Deno.exit(1)
}
console.log("model.test.js: all checks passed")
