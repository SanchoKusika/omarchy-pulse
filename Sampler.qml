import QtQuick
import Quickshell.Io
import "Model.js" as Model

// Reads the machine's vitals on a timer. The cheap counters (/proc/stat,
// meminfo, net/dev, loadavg, uptime and the CPU sensor) come through
// FileView, which reloads them synchronously without spawning anything.
// Disk usage and the process list need a command each, so they only run
// while `detailed` is set, i.e. while the panel is open.
Item {
  id: root

  property int interval: 2
  property bool detailed: false

  // Latest readings. cpu is -1 until two /proc/stat snapshots exist.
  property real cpu: -1
  property int threads: 0
  property var cores: []           // 0..100 per thread, -1 unknown
  property real memUsed: 0
  property real memTotal: 0
  property real swapUsed: 0
  property real swapTotal: 0
  property real temp: NaN
  property real gpu: -1
  property real vramUsed: 0
  property real vramTotal: 0
  property real gpuTemp: NaN
  property real rxRate: 0
  property real txRate: 0
  property var load: [0, 0, 0]
  property int uptime: 0
  property real diskUsed: 0
  property real diskSize: 0
  property var procs: []

  readonly property real memFraction: Model.fraction(memUsed, memTotal)
  readonly property real swapFraction: Model.fraction(swapUsed, swapTotal)
  readonly property real diskFraction: Model.fraction(diskUsed, diskSize)
  readonly property real vramFraction: Model.fraction(vramUsed, vramTotal)
  readonly property bool hasTemp: !isNaN(temp)
  property bool hasGpu: false
  property string gpuType: "none"

  // 0..1 series, newest last.
  property var cpuHistory: []
  property var memHistory: []
  property var tempHistory: []     // on the 30..100 °C scale
  property var gpuHistory: []

  property string sensorPath: ""
  property var prevCpu: null
  property var prevNet: null
  property real prevTime: 0

  signal sampled()

  function sample() {
    var now = Date.now()
    var seconds = prevTime > 0 ? (now - prevTime) / 1000 : 0
    prevTime = now

    statFile.reload()
    var c = Model.parseCpu(statFile.text())
    if (c.ok) {
      cpu = Model.cpuPercent(prevCpu, c)
      cores = Model.corePercents(prevCpu, c)
      threads = c.threads
      prevCpu = c
    }

    memFile.reload()
    var m = Model.parseMeminfo(memFile.text())
    if (m.ok) {
      memUsed = m.used
      memTotal = m.total
      swapUsed = m.swapUsed
      swapTotal = m.swapTotal
    }

    netFile.reload()
    var n = Model.parseNetDev(netFile.text())
    if (n.ok) {
      if (prevNet && seconds > 0) {
        rxRate = Model.rate(prevNet.rx, n.rx, seconds)
        txRate = Model.rate(prevNet.tx, n.tx, seconds)
      }
      prevNet = n
    }

    loadFile.reload()
    load = Model.parseLoad(loadFile.text())
    uptimeFile.reload()
    uptime = Model.parseUptime(uptimeFile.text())

    if (sensorPath !== "") {
      tempFile.reload()
      temp = Model.parseTemp(tempFile.text())
    }

    if (cpu >= 0) {
      cpuHistory = Model.pushHistory(cpuHistory, cpu / 100, Model.HISTORY)
      memHistory = Model.pushHistory(memHistory, memFraction, Model.HISTORY)
      tempHistory = Model.pushHistory(tempHistory, Model.tempFraction(temp), Model.HISTORY)
    }

    if (hasGpu && !gpuProc.running) gpuProc.running = true

    if (detailed) {
      if (!topProc.running) topProc.running = true
      if (!diskProc.running && (diskSize === 0 || ++diskTick % 15 === 0)) diskProc.running = true
    }

    sampled()
  }

  property int diskTick: 0

  onDetailedChanged: {
    if (!detailed) return
    diskTick = 0
    if (!diskProc.running) diskProc.running = true
    if (!topProc.running) topProc.running = true
  }

  FileView { id: statFile; path: "/proc/stat"; blockLoading: true; printErrors: false }
  FileView { id: memFile; path: "/proc/meminfo"; blockLoading: true; printErrors: false }
  FileView { id: netFile; path: "/proc/net/dev"; blockLoading: true; printErrors: false }
  FileView { id: loadFile; path: "/proc/loadavg"; blockLoading: true; printErrors: false }
  FileView { id: uptimeFile; path: "/proc/uptime"; blockLoading: true; printErrors: false }
  FileView { id: tempFile; path: root.sensorPath; blockLoading: true; printErrors: false }

  // Finds the CPU's hwmon sensor once; Model.pickSensor only accepts
  // /sys/class/hwmon/hwmonN paths, so nothing else can end up being read.
  Process {
    id: sensorProc
    running: true
    command: ["sh", "-c", "for h in /sys/class/hwmon/hwmon*; do printf '%s\\t%s\\n' \"$h\" \"$(cat \"$h/name\" 2>/dev/null)\"; done"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.sensorPath = Model.pickSensor(text)
    }
  }

  // Second frame of top: its %CPU is measured over the delay, not averaged
  // over each process's lifetime as ps reports it.
  Process {
    id: topProc
    command: ["sh", "-c", "LC_ALL=C top -bn2 -d0.5 -o %CPU -w 512 | awk '/^top -/{f++} f==2 && /^ *[0-9]/' | head -n 8"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.procs = Model.parseTop(text, 5)
    }
  }

  Process {
    id: diskProc
    command: ["df", "-B1", "--output=size,used", "/"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var d = Model.parseDf(text)
        if (!d.ok) return
        root.diskSize = d.size
        root.diskUsed = d.used
      }
    }
  }

  Process {
    id: gpuDetectProc
    running: true
    command: ["sh", "-c", "if command -v nvidia-smi >/dev/null 2>&1; then echo nvidia; elif ls /sys/class/drm/card*/device/gpu_busy_percent >/dev/null 2>&1; then echo amdgpu; else echo none; fi"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var t = String(text || "").trim()
        if (t === "nvidia") {
          root.gpuType = "nvidia"
          root.hasGpu = true
          gpuProc.command = ["nvidia-smi", "--query-gpu=utilization.gpu,utilization.memory,memory.used,memory.total,temperature.gpu", "--format=csv,noheader,nounits"]
          if (!gpuProc.running) gpuProc.running = true
        } else if (t === "amdgpu") {
          root.gpuType = "amdgpu"
          root.hasGpu = true
          gpuProc.command = ["sh", "-c", "cat /sys/class/drm/card*/device/gpu_busy_percent 2>/dev/null"]
          if (!gpuProc.running) gpuProc.running = true
        } else {
          root.gpuType = "none"
          root.hasGpu = false
        }
      }
    }
  }

  Process {
    id: gpuProc
    command: ["true"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var g = Model.parseGpu(text, root.gpuType)
        if (g.ok) {
          root.gpu = g.gpu
          root.vramUsed = g.vramUsed
          root.vramTotal = g.vramTotal
          root.gpuTemp = g.temp
          root.gpuHistory = Model.pushHistory(root.gpuHistory, root.gpu / 100, Model.HISTORY)
        }
      }
    }
  }

  Timer {
    interval: root.interval * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.sample()
  }
}
