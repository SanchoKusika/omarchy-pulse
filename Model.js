// Pure helpers for Pulse: parsing /proc and /sys text, turning counters into
// rates and percentages, and normalizing the widget's shell.json entry.
// Nothing here touches QML, so tests/model.test.js runs it under Deno.

var STYLES = ["pulse", "bars", "text"]
// What the pulse and number looks follow; the bars look shows all three.
var METRICS = ["cpu", "mem", "gpu", "temp"]
// Nerd Font oct-cpu (a plain chip), fa-memory (a RAM stick), md-expansion_card (GPU) and
// md-thermometer: four distinct shapes that cannot be mistaken for one another.
var ICONS = { cpu: "\uF4BC", mem: "\uEFC5", gpu: "\uDB83\uDFB2", temp: "\uDB81\uDD0F" }
// Panel rows: md-swap-horizontal, harddisk, download, upload, gauge, clock-outline, vram.
var ROW_ICONS = {
  swap: "󰓡", disk: "󰋊", down: "󰇚",
  up: "󰕒", load: "󰊚", uptime: "󰅐",
  vram: "\uDB81\uDE1A"
}
var DEFAULTS = { style: "pulse", metric: "cpu", metrics: ["cpu"], metricOrder: ["cpu", "mem", "gpu", "temp"], interval: 2, alert: 90 }

// Temperature meters span 30..100 °C: a CPU never idles at 0, so a scale
// from zero would leave every meter half full on a cold machine.
var TEMP_FLOOR = 30
var TEMP_CEIL = 100
var TEMP_HOT = 90
var MEM_HOT = 0.9
// An alert clears this far below its threshold, so it does not flicker.
var HYSTERESIS = 5
var HISTORY = 60          // samples kept for the panel graph
var BAR_HISTORY = 24      // samples drawn in the bar sparkline
var MAX_NAME = 24         // process name length shown in the panel
var MAX_PROCS = 5
var MAX_CORES = 256       // threads drawn in the panel's core map

// Interfaces that only mirror traffic already counted on a physical link.
var VIRTUAL_IFACE = /^(lo|veth|docker|br-|virbr|vnet|tailscale|tun|tap|wg|zt)/

// Hwmon drivers that report the CPU package, best first.
var SENSORS = ["k10temp", "zenpower", "coretemp", "cpu_thermal", "soc_thermal", "acpitz"]

function clamp(value, lo, hi) {
  return Math.max(lo, Math.min(hi, value))
}

function finite(value, fallback) {
  var n = Number(value)
  return isFinite(n) ? n : fallback
}

function normalize(settings) {
  var s = settings || {}
  var style = STYLES.indexOf(s.style) >= 0 ? s.style : DEFAULTS.style
  var interval = Math.round(clamp(finite(s.interval, DEFAULTS.interval), 1, 10))
  var alert = Math.round(clamp(finite(s.alert, DEFAULTS.alert), 50, 100))

  var metrics = []
  if (Array.isArray(s.metrics)) {
    for (var i = 0; i < s.metrics.length; i++) {
      var m = s.metrics[i]
      if (m === "all") {
        metrics = METRICS.slice()
        break
      }
      if (METRICS.indexOf(m) >= 0 && metrics.indexOf(m) < 0) {
        metrics.push(m)
      }
    }
  } else if (typeof s.metric === "string") {
    if (s.metric === "all") {
      metrics = METRICS.slice()
    } else if (METRICS.indexOf(s.metric) >= 0) {
      metrics = [s.metric]
    }
  }
  if (metrics.length === 0) {
    metrics = s.style === "bars" ? METRICS.slice() : [DEFAULTS.metric]
  }

  var metricOrder = []
  if (Array.isArray(s.metricOrder)) {
    for (var j = 0; j < s.metricOrder.length; j++) {
      var mo = s.metricOrder[j]
      if (METRICS.indexOf(mo) >= 0 && metricOrder.indexOf(mo) < 0) {
        metricOrder.push(mo)
      }
    }
  } else if (metrics.length > 0) {
    for (var k = 0; k < metrics.length; k++) {
      if (metricOrder.indexOf(metrics[k]) < 0) metricOrder.push(metrics[k])
    }
  }
  for (var l = 0; l < METRICS.length; l++) {
    if (metricOrder.indexOf(METRICS[l]) < 0) metricOrder.push(METRICS[l])
  }

  return {
    style: style,
    metric: metrics[0] || DEFAULTS.metric,
    metrics: metrics,
    metricOrder: metricOrder,
    interval: interval,
    alert: alert
  }
}

// Two shell.json entries with the same keys and values, in any key order.
function sameEntry(a, b) {
  var x = a || {}, y = b || {}
  var kx = Object.keys(x), ky = Object.keys(y)
  if (kx.length !== ky.length) return false
  for (var i = 0; i < kx.length; i++)
    if (JSON.stringify(x[kx[i]]) !== JSON.stringify(y[kx[i]])) return false
  return true
}

function cycle(list, current, delta) {
  var i = list.indexOf(current)
  if (i < 0) i = 0
  var d = delta === undefined ? 1 : delta
  return list[((i + d) % list.length + list.length) % list.length]
}

function nextStyle(style, delta) { return cycle(STYLES, style, delta) }
function nextMetric(metric, delta) { return cycle(METRICS, metric, delta) }

// 0..1 position of a temperature on the 30..100 °C meter; 0 when unknown.
function tempFraction(celsius) {
  if (!isFinite(celsius)) return 0
  return clamp((celsius - TEMP_FLOOR) / (TEMP_CEIL - TEMP_FLOOR), 0, 1)
}

// Alert state with hysteresis: it turns on at `threshold` and only turns
// off again once the value falls `margin` below it. Unknown values clear it.
function alertState(wasOn, value, threshold, margin) {
  if (!isFinite(value) || value < 0) return false
  return wasOn ? value >= threshold - margin : value >= threshold
}

// /proc/stat: the aggregate "cpu" line plus one "cpuN" line per thread.
// Idle time counts iowait too, as top does.
function parseCpu(text) {
  var lines = String(text || "").split("\n")
  var out = { idle: 0, total: 0, threads: 0, cores: [], ok: false }
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (line.indexOf("cpu") !== 0) {
      if (out.ok) break
      continue
    }
    var fields = line.trim().split(/\s+/)
    var total = 0
    for (var f = 1; f < fields.length && f <= 8; f++) total += finite(fields[f], 0)
    var idle = finite(fields[4], 0) + finite(fields[5], 0)
    if (fields[0] === "cpu") {
      out.total = total
      out.idle = idle
      out.ok = total > 0
    } else if (/^cpu\d+$/.test(fields[0]) && out.cores.length < MAX_CORES) {
      out.threads++
      out.cores.push({ idle: idle, total: total, ok: total > 0 })
    }
  }
  return out
}

// Busy share of each thread between two snapshots, 0..100 (-1 unknown).
function corePercents(prev, next) {
  var a = prev && prev.cores ? prev.cores : []
  var b = next && next.cores ? next.cores : []
  var out = []
  for (var i = 0; i < b.length; i++) out.push(i < a.length ? cpuPercent(a[i], b[i]) : -1)
  return out
}

// Busy share between two /proc/stat snapshots, 0..100, or -1 when unknown.
function cpuPercent(prev, next) {
  if (!prev || !next || !prev.ok || !next.ok) return -1
  var total = next.total - prev.total
  var idle = next.idle - prev.idle
  if (total <= 0 || idle < 0) return -1
  return clamp((1 - idle / total) * 100, 0, 100)
}

// /proc/meminfo, in bytes.
function parseMeminfo(text) {
  var lines = String(text || "").split("\n")
  var kb = {}
  for (var i = 0; i < lines.length; i++) {
    var m = lines[i].match(/^(\w+):\s+(\d+)/)
    if (m) kb[m[1]] = Number(m[2])
  }
  var total = (kb.MemTotal || 0) * 1024
  var available = (kb.MemAvailable !== undefined ? kb.MemAvailable : (kb.MemFree || 0)) * 1024
  var swapTotal = (kb.SwapTotal || 0) * 1024
  var swapFree = (kb.SwapFree || 0) * 1024
  return {
    total: total,
    used: Math.max(0, total - available),
    swapTotal: swapTotal,
    swapUsed: Math.max(0, swapTotal - swapFree),
    ok: total > 0
  }
}

// /proc/net/dev: bytes received and sent over every real interface.
function parseNetDev(text) {
  var lines = String(text || "").split("\n")
  var rx = 0, tx = 0, found = false
  for (var i = 2; i < lines.length; i++) {
    var colon = lines[i].indexOf(":")
    if (colon < 0) continue
    var name = lines[i].substring(0, colon).trim()
    if (VIRTUAL_IFACE.test(name)) continue
    var fields = lines[i].substring(colon + 1).trim().split(/\s+/)
    if (fields.length < 9) continue
    rx += finite(fields[0], 0)
    tx += finite(fields[8], 0)
    found = true
  }
  return { rx: rx, tx: tx, ok: found }
}

// Bytes per second between two counter readings; a reset reads as zero.
function rate(prev, next, seconds) {
  if (!(seconds > 0)) return 0
  var delta = Number(next) - Number(prev)
  return delta > 0 && isFinite(delta) ? delta / seconds : 0
}

function parseLoad(text) {
  var fields = String(text || "").trim().split(/\s+/)
  var out = []
  for (var i = 0; i < 3; i++) out.push(Math.max(0, finite(fields[i], 0)))
  return out
}

function parseUptime(text) {
  return Math.max(0, Math.floor(finite(String(text || "").trim().split(/\s+/)[0], 0)))
}

// A hwmon temp*_input holds millidegrees Celsius. NaN when unreadable or
// outside what a CPU can physically report.
function parseTemp(text) {
  var raw = String(text || "").trim()
  if (!/^-?\d+$/.test(raw)) return NaN
  var c = Number(raw) / 1000
  return c > -40 && c < 150 ? c : NaN
}

// Lines of "<hwmon dir>\t<driver name>"; returns the CPU's temp1_input path.
function pickSensor(text) {
  var lines = String(text || "").split("\n")
  var best = "", rank = SENSORS.length
  for (var i = 0; i < lines.length && i < 64; i++) {
    var parts = lines[i].split("\t")
    if (parts.length < 2) continue
    var dir = parts[0].trim()
    if (!/^\/sys\/class\/hwmon\/hwmon\d+$/.test(dir)) continue
    var r = SENSORS.indexOf(parts[1].trim())
    if (r >= 0 && r < rank) { rank = r; best = dir + "/temp1_input" }
  }
  return best
}

// `df -B1 --output=size,used /`, header line optional.
function parseDf(text) {
  var lines = String(text || "").trim().split("\n")
  for (var i = lines.length - 1; i >= 0; i--) {
    var f = lines[i].trim().split(/\s+/)
    if (f.length >= 2 && /^\d+$/.test(f[0]) && /^\d+$/.test(f[1]))
      return { size: Number(f[0]), used: Number(f[1]), ok: Number(f[0]) > 0 }
  }
  return { size: 0, used: 0, ok: false }
}

// Process names come from other programs: keep printable characters only and
// bound the length before anything displays them.
function cleanName(name) {
  var s = String(name || "").replace(/[\u0000-\u001f\u007f-\u009f<>&]/g, "").trim()
  if (s.length > MAX_NAME) s = s.substring(0, MAX_NAME - 1) + "…"
  return s
}

// Rows of top's process table: PID USER PR NI VIRT RES SHR S %CPU %MEM TIME+ COMMAND.
// The COMMAND column may hold spaces ("Web Content"), so it is the rest of the line.
function parseTop(text, limit) {
  var max = limit || MAX_PROCS
  var lines = String(text || "").split("\n")
  var out = []
  for (var i = 0; i < lines.length && out.length < max && i < 200; i++) {
    var f = lines[i].trim().split(/\s+/)
    if (f.length < 12 || !/^\d+$/.test(f[0])) continue
    var name = cleanName(f.slice(11).join(" "))
    if (name === "" || name === "top") continue
    out.push({
      pid: Number(f[0]),
      name: name,
      cpu: clamp(finite(f[8], 0), 0, 100 * 1024),
      mem: clamp(finite(f[9], 0), 0, 100)
    })
  }
  return out
}

function pushHistory(list, value, max) {
  var next = (list || []).slice(Math.max(0, (list || []).length - max + 1))
  next.push(value)
  return next
}

// Number formatting goes through fmt(value, decimals) so the caller can hand
// in Commons.I18n.formatNumber; units stay as they are in every language.
function defaultFmt(value, decimals) {
  return decimals === undefined ? String(value) : Number(value).toFixed(decimals)
}

function scaled(bytes, units) {
  var v = Math.max(0, Number(bytes) || 0)
  var u = 0
  while (v >= 1024 && u < units.length - 1) { v /= 1024; u++ }
  return { value: v, unit: units[u] }
}

function formatBytes(bytes, fmt) {
  var f = typeof fmt === "function" ? fmt : defaultFmt
  var s = scaled(bytes, ["B", "KB", "MB", "GB", "TB"])
  var d = s.unit === "B" || s.value >= 100 ? 0 : 1
  return f(Number(s.value.toFixed(d)), d) + " " + s.unit
}

// "4.4/7.6 GB" when both share a unit, "40 KB/13.2 GB" when they don't.
function formatPair(used, total, fmt) {
  var a = formatBytes(used, fmt), b = formatBytes(total, fmt)
  var ua = a.substring(a.lastIndexOf(" ") + 1), ub = b.substring(b.lastIndexOf(" ") + 1)
  return ua === ub ? a.substring(0, a.lastIndexOf(" ")) + "/" + b : a + "/" + b
}

function formatRate(bytesPerSecond, fmt) {
  var f = typeof fmt === "function" ? fmt : defaultFmt
  var s = scaled(bytesPerSecond, ["B/s", "KB/s", "MB/s", "GB/s"])
  var d = s.unit === "B/s" || s.value >= 100 ? 0 : 1
  return f(Number(s.value.toFixed(d)), d) + " " + s.unit
}

function uptimeParts(seconds) {
  var s = Math.max(0, Math.floor(Number(seconds) || 0))
  return { days: Math.floor(s / 86400), hours: Math.floor(s % 86400 / 3600), minutes: Math.floor(s % 3600 / 60) }
}

// One word for how hard the machine is working, used as the panel's status.
function mood(cpu, alert) {
  if (!(cpu >= 0)) return "waking"
  if (cpu >= (alert || DEFAULTS.alert)) return "redline"
  if (cpu >= 60) return "hard"
  if (cpu >= 30) return "busy"
  if (cpu >= 8) return "calm"
  return "idle"
}

function fraction(used, total) {
  return total > 0 ? clamp(used / total, 0, 1) : 0
}

function parseGpu(text, type) {
  var lines = String(text || "").trim().split("\n")
  if (lines.length === 0 || !lines[0]) return { ok: false, gpu: -1, vramUsed: 0, vramTotal: 0, temp: NaN }

  if (type === "nvidia") {
    var fields = lines[0].split(",")
    if (fields.length >= 4) {
      var gpu = clamp(finite(fields[0].trim(), -1), 0, 100)
      var vramUsed = finite(fields[2].trim(), 0) * 1024 * 1024
      var vramTotal = finite(fields[3].trim(), 0) * 1024 * 1024
      var temp = fields.length >= 5 ? finite(fields[4].trim(), NaN) : NaN
      return {
        ok: gpu >= 0,
        gpu: gpu,
        vramUsed: vramUsed,
        vramTotal: vramTotal,
        temp: isFinite(temp) ? temp : NaN
      }
    }
  } else if (type === "amdgpu") {
    var f = lines[0].split(",")
    var g = clamp(finite(f[0].trim(), -1), 0, 100)
    var u = f.length > 1 ? finite(f[1].trim(), 0) : 0
    var tot = f.length > 2 ? finite(f[2].trim(), 0) : 0
    return {
      ok: g >= 0,
      gpu: g,
      vramUsed: u,
      vramTotal: tot,
      temp: NaN
    }
  }
  return { ok: false, gpu: -1, vramUsed: 0, vramTotal: 0, temp: NaN }
}

if (typeof module !== "undefined") {
  module.exports = {
    STYLES: STYLES, METRICS: METRICS, ICONS: ICONS, DEFAULTS: DEFAULTS, HISTORY: HISTORY, BAR_HISTORY: BAR_HISTORY,
    TEMP_HOT: TEMP_HOT, MEM_HOT: MEM_HOT, HYSTERESIS: HYSTERESIS,
    sameEntry: sameEntry, tempFraction: tempFraction, alertState: alertState, nextMetric: nextMetric,
    normalize: normalize, nextStyle: nextStyle, parseCpu: parseCpu, cpuPercent: cpuPercent, corePercents: corePercents,
    parseMeminfo: parseMeminfo, parseNetDev: parseNetDev, rate: rate, parseLoad: parseLoad,
    parseUptime: parseUptime, parseTemp: parseTemp, pickSensor: pickSensor, parseDf: parseDf,
    cleanName: cleanName, parseTop: parseTop, pushHistory: pushHistory, formatBytes: formatBytes,
    formatRate: formatRate, formatPair: formatPair, ROW_ICONS: ROW_ICONS, uptimeParts: uptimeParts, mood: mood, fraction: fraction,
    parseGpu: parseGpu
  }
}
