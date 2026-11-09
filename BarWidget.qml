import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// Pulse: a quiet system monitor for the bar.
//
// Three looks, picked with a right click or in the panel:
//   pulse  the followed metrics' icons and live sparklines of them
//   bars   an icon and a slim meter each for selected metrics
//   text   the followed metrics' icons and their values
// The scroll wheel switches the followed metric presets (CPU, RAM, GPU, Temp, All).
//
// A metric turns the theme's urgent color at its alert (CPU/GPU at `alert`,
// memory at 90%, CPU temperature at 90 °C) and clears 5 points below it.
// While any followed metric is alerting the sparkline's head ripples.
//
// Left click opens the panel, middle click opens btop.
//
// shell.json entry: { "id": "io.github.sanchokusika.pulse",
//                     "style": "pulse" | "bars" | "text",
//                     "metrics": ["cpu", "mem", "gpu", "temp"],
//                     "interval": 1..10 (seconds), "alert": 50..100 (CPU %) }
BarWidget {
  id: root
  moduleName: "io.github.sanchokusika.pulse"

  readonly property var cfg: Model.normalize(root.settings)
  property alias sampler: sampler

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  Sampler {
    id: sampler
    interval: root.cfg.interval
    detailed: root.opened
  }

  // ---- Alerts, with hysteresis so they do not flicker at the line.

  property bool cpuHot: false
  property bool memHot: false
  property bool gpuHot: false
  property bool tempHot: false

  Connections {
    target: sampler
    function onSampled() {
      root.cpuHot = Model.alertState(root.cpuHot, sampler.cpu, root.cfg.alert, Model.HYSTERESIS)
      root.memHot = Model.alertState(root.memHot, sampler.memTotal > 0 ? sampler.memFraction * 100 : -1,
                                     Model.MEM_HOT * 100, Model.HYSTERESIS)
      root.gpuHot = Model.alertState(root.gpuHot, sampler.hasGpu ? sampler.gpu : -1, root.cfg.alert, Model.HYSTERESIS)
      root.tempHot = Model.alertState(root.tempHot, sampler.hasTemp ? sampler.temp : NaN,
                                      Model.TEMP_HOT, Model.HYSTERESIS)
    }
  }

  readonly property bool hot: cpuHot || memHot || gpuHot || tempHot

  function isHot(metric) {
    if (metric === "mem") return root.memHot
    if (metric === "gpu") return root.gpuHot
    if (metric === "temp") return root.tempHot
    return root.cpuHot
  }

  readonly property color fg: root.bar ? root.bar.barForeground : Commons.Color.foreground
  readonly property color urgent: root.bar ? root.bar.urgent : Commons.Color.urgent

  // ---- The followed metrics and available sequence.

  readonly property var allAvailableMetrics: {
    var out = ["cpu", "mem"]
    if (sampler.hasGpu) out.push("gpu")
    if (sampler.hasTemp) out.push("temp")
    return out
  }

  readonly property var orderedMetrics: {
    var pref = (root.settings && root.settings.metricOrder) ? root.settings.metricOrder : (root.cfg.metricOrder || root.cfg.metrics || [])
    var available = root.allAvailableMetrics
    var res = []
    for (var i = 0; i < pref.length; i++) {
      var m = pref[i]
      if (available.indexOf(m) >= 0 && res.indexOf(m) < 0) res.push(m)
    }
    for (var j = 0; j < available.length; j++) {
      var a = available[j]
      if (res.indexOf(a) < 0) res.push(a)
    }
    return res
  }

  readonly property var activeMetrics: {
    var activeList = root.cfg.metrics || [root.cfg.metric]
    var res = []
    var ordered = root.orderedMetrics
    for (var i = 0; i < ordered.length; i++) {
      var m = ordered[i]
      if (activeList.indexOf(m) >= 0) res.push(m)
    }
    return res.length > 0 ? res : (ordered.length > 0 ? [ordered[0]] : ["cpu"])
  }

  readonly property string metric: activeMetrics[0] || "cpu"
  readonly property bool metricHot: isHot(root.metric)
  readonly property color tone: root.metricHot ? root.urgent : root.fg

  function valueText(metric, withUnit) {
    if (metric === "mem") {
      if (sampler.memTotal <= 0) return "–"
      var m = Commons.I18n.formatNumber(Math.round(sampler.memFraction * 100))
      return withUnit ? m + "%" : m
    }
    if (metric === "gpu") {
      if (!sampler.hasGpu || sampler.gpu < 0) return "–"
      var g = Commons.I18n.formatNumber(Math.round(sampler.gpu))
      return withUnit ? g + "%" : g
    }
    if (metric === "temp") {
      if (!sampler.hasTemp) return "–"
      var t = Commons.I18n.formatNumber(Math.round(sampler.temp))
      return withUnit ? t + "°" : t
    }
    if (sampler.cpu < 0) return "–"
    var c = Commons.I18n.formatNumber(Math.round(sampler.cpu))
    return withUnit ? c + "%" : c
  }

  function historyOf(metric) {
    if (metric === "mem") return sampler.memHistory
    if (metric === "gpu") return sampler.gpuHistory
    if (metric === "temp") return sampler.tempHistory
    return sampler.cpuHistory
  }

  readonly property var faceItems: {
    var out = []
    var list = root.activeMetrics
    for (var i = 0; i < list.length; i++) {
      var m = list[i]
      var hot = root.isHot(m)
      out.push({
        id: m,
        icon: Model.ICONS[m],
        values: root.historyOf(m),
        label: root.valueText(m, !root.vertical),
        tone: hot ? root.urgent : root.fg,
        beat: hot,
        lift: m === "cpu"
      })
    }
    return out
  }

  readonly property var barItems: {
    var out = []
    var list = root.activeMetrics
    for (var i = 0; i < list.length; i++) {
      var m = list[i]
      var val = 0
      var known = false
      if (m === "cpu") {
        val = sampler.cpu >= 0 ? sampler.cpu / 100 : 0
        known = sampler.cpu >= 0
      } else if (m === "mem") {
        val = sampler.memFraction
        known = sampler.memTotal > 0
      } else if (m === "gpu") {
        val = sampler.gpu >= 0 ? sampler.gpu / 100 : 0
        known = sampler.hasGpu && sampler.gpu >= 0
      } else if (m === "temp") {
        val = Model.tempFraction(sampler.temp)
        known = sampler.hasTemp
      }
      out.push({
        id: m,
        icon: Model.ICONS[m],
        value: val,
        hot: root.isHot(m),
        known: known
      })
    }
    return out
  }

  readonly property string tooltip: {
    var lines = [Model.ICONS.cpu + "  " + strings.t("tip.cpu").arg(valueText("cpu", false)),
                 Model.ICONS.mem + "  " + strings.t("tip.mem").arg(valueText("mem", false))]
    if (sampler.hasGpu) lines.push(Model.ICONS.gpu + "  " + strings.t("tip.gpu").arg(valueText("gpu", false)))
    if (sampler.hasTemp) lines.push(Model.ICONS.temp + "  " + strings.t("tip.temp").arg(valueText("temp", false)))
    return lines.join("\n")
  }

  // ---- Settings, applied locally first so the bar redraws on the click.

  property var localSettings: null
  property real holdUntil: 0

  function saveSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]
    root.localSettings = entry
    root.holdUntil = Date.now() + 2000
    root.settings = entry
    persistTimer.restart()
  }

  Timer {
    id: persistTimer
    interval: 350
    onTriggered: {
      root.holdUntil = Date.now() + 1500
      if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
        root.bar.shell.updateEntryInline(root.moduleName, root.localSettings)
    }
  }

  onSettingsChanged: {
    if (root.localSettings && Date.now() < root.holdUntil
        && !Model.sameEntry(root.settings, root.localSettings)) {
      Qt.callLater(function() { root.settings = root.localSettings })
      return
    }
    injectPanel()
  }

  function setStyle(name) {
    if (Model.STYLES.indexOf(name) >= 0 && name !== root.cfg.style) saveSettings({ style: name })
  }

  function setMetrics(list) {
    if (!Array.isArray(list) || list.length === 0) return
    saveSettings({ metrics: list, metric: list[0] })
  }

  function setMetric(name) {
    if (name === "all") {
      var all = ["cpu", "mem"]
      if (sampler.hasGpu) all.push("gpu")
      if (sampler.hasTemp) all.push("temp")
      setMetrics(all)
    } else if (Model.METRICS.indexOf(name) >= 0) {
      setMetrics([name])
    }
  }

  function toggleMetric(name) {
    if (name === "all") {
      var all = root.allAvailableMetrics
      var isAll = root.activeMetrics.length === all.length
      var newActive = isAll ? [root.orderedMetrics[0] || "cpu"] : all.slice()
      saveSettings({ metricOrder: root.orderedMetrics, metrics: newActive, metric: newActive[0] })
      return
    }

    var ordered = root.orderedMetrics.slice()
    var currentActive = root.activeMetrics.slice()
    var idx = currentActive.indexOf(name)
    var newActive = []

    if (idx >= 0) {
      if (currentActive.length > 1) {
        for (var i = 0; i < ordered.length; i++) {
          if (ordered[i] !== name && currentActive.indexOf(ordered[i]) >= 0) {
            newActive.push(ordered[i])
          }
        }
      } else {
        newActive = currentActive
      }
    } else {
      for (var j = 0; j < ordered.length; j++) {
        if (ordered[j] === name || currentActive.indexOf(ordered[j]) >= 0) {
          newActive.push(ordered[j])
        }
      }
    }

    saveSettings({ metricOrder: ordered, metrics: newActive, metric: newActive[0] })
  }

  function moveMetric(fromIndex, delta) {
    var list = root.orderedMetrics.slice()
    var toIndex = fromIndex + delta
    if (fromIndex < 0 || fromIndex >= list.length) return
    if (toIndex < 0 || toIndex >= list.length) return
    var item = list.splice(fromIndex, 1)[0]
    list.splice(toIndex, 0, item)

    var newActive = []
    for (var i = 0; i < list.length; i++) {
      if (root.activeMetrics.indexOf(list[i]) >= 0) newActive.push(list[i])
    }
    if (newActive.length === 0) newActive = [list[0]]

    saveSettings({ metricOrder: list, metrics: newActive, metric: newActive[0] })
  }

  function isMetricActive(name) {
    if (name === "all") {
      return root.activeMetrics.length === root.allAvailableMetrics.length
    }
    return root.activeMetrics.indexOf(name) >= 0
  }

  function cycleStyle() { setStyle(Model.nextStyle(root.cfg.style)) }

  function openMonitor() {
    if (root.bar) root.bar.run("omarchy-launch-or-focus-tui btop")
  }

  // A notch of a mouse wheel is 120; touchpads send many small steps.
  property real wheelAccum: 0
  function handleWheel(delta) {
    wheelAccum += delta
    if (Math.abs(wheelAccum) < 120) return
    var presets = [["cpu"], ["mem"]]
    if (sampler.hasGpu) presets.push(["gpu"])
    if (sampler.hasTemp) presets.push(["temp"])
    var all = ["cpu", "mem"]
    if (sampler.hasGpu) all.push("gpu")
    if (sampler.hasTemp) all.push("temp")
    presets.push(all)

    var curIdx = -1
    for (var p = 0; p < presets.length; p++) {
      if (JSON.stringify(presets[p]) === JSON.stringify(root.activeMetrics)) {
        curIdx = p
        break
      }
    }
    var step = wheelAccum > 0 ? 1 : -1
    var nextIdx = ((curIdx + step) % presets.length + presets.length) % presets.length
    setMetrics(presets[nextIdx])
    wheelAccum = 0
  }

  // ---- Panel, same wiring as Omarchy's own popup widgets.

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    target.bar = root.bar
    target.settings = root.settings
    target.anchorItem = button
    target.hostWidget = root
  }

  onBarChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: { root.injectPanel(); Qt.callLater(root.injectPanel) }
  }

  ShellIpc {
    target: "io.github.sanchokusika.pulse"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function style(name: string): void { root.setStyle(name) }
    function metric(name: string): void { root.setMetric(name) }
    function metrics(names: string): void { root.setMetrics(names.split(",")) }
    function move(from: int, delta: int): void { root.moveMetric(from, delta) }
    function toggleMetric(name: string): void { root.toggleMetric(name) }
  }

  // ---- The face.

  readonly property bool barsLook: root.cfg.style === "bars"
  readonly property real padding: Style.space(root.vertical ? 12 : 16)

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    hasVisualContent: true
    fixedWidth: root.vertical ? -1 : Math.round(content.width + root.padding)
    fixedHeight: root.vertical ? Math.round(content.height + root.padding) : -1
    tooltipText: root.opened ? "" : root.tooltip

    onPressed: function(b) {
      if (b === Qt.RightButton) root.cycleStyle()
      else if (b === Qt.MiddleButton) root.openMonitor()
      else root.togglePanel()
    }
    onWheelMoved: function(delta) { root.handleWheel(delta) }

    Item {
      id: content
      x: Math.round((button.width - width) / 2)
      y: Math.round((button.height - height) / 2)
      width: root.barsLook ? bars.implicitWidth : face.implicitWidth
      height: root.barsLook ? bars.implicitHeight : face.implicitHeight
      scale: button.pressScale

      Face {
        id: face
        visible: !root.barsLook
        width: implicitWidth
        height: implicitHeight
        look: root.cfg.style === "text" ? "text" : "pulse"
        items: root.faceItems
        capacity: Model.BAR_HISTORY
        widestLabel: root.vertical ? "100" : "100%"
        vertical: root.vertical
        barSize: root.barSize
        fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
      }

      Bars {
        id: bars
        visible: root.barsLook
        width: implicitWidth
        height: implicitHeight
        vertical: root.vertical
        barSize: root.barSize
        color: root.fg
        hotColor: root.urgent
        fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
        items: root.barItems
      }
    }
  }
}
