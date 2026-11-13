import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// Pulse's panel: the machine at a glance.
//
// A hero with the CPU load and a word for how hard the machine is working,
// a two-minute graph of CPU over memory, meters for memory, swap,
// temperature and disk, network and load figures, the busiest processes,
// and the bar look picker.
//
// Keys: Left/Right (h/l) switch the bar look, Enter or b opens btop,
// Escape closes, Tab moves to the neighbouring bar panel.
Panel {
  id: root
  moduleName: "io.github.sanchokusika.pulse"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  readonly property var s: hostWidget ? hostWidget.sampler : null
  readonly property var cfg: hostWidget ? hostWidget.cfg : Model.normalize({})

  readonly property color fg: bar ? bar.foreground : Commons.Color.foreground
  readonly property color urgent: bar ? bar.urgent : Commons.Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property real cpu: s ? s.cpu : -1
  readonly property bool cpuHot: hostWidget ? hostWidget.cpuHot : false
  readonly property bool gpuHot: hostWidget ? hostWidget.gpuHot : false
  readonly property bool tempHot: hostWidget ? hostWidget.tempHot : false
  readonly property bool memHot: hostWidget ? hostWidget.memHot : false
  readonly property color tone: cpuHot ? urgent : fg

  function num(value, decimals) { return Commons.I18n.formatNumber(value, decimals) }
  function bytes(value) { return Model.formatBytes(value, Commons.I18n.formatNumber) }
  function speed(value) { return Model.formatRate(value, Commons.I18n.formatNumber) }
  function pair(used, total) { return Model.formatPair(used, total, Commons.I18n.formatNumber) }

  readonly property string moodText: strings.t("mood." + Model.mood(cpu, cfg.alert))
  readonly property string statusText: {
    var n = s ? s.threads : 0
    if (n <= 0) return moodText
    return moodText + "  ·  " + strings.tn("threads", n).arg(num(n))
  }

  readonly property string uptimeText: {
    var p = Model.uptimeParts(s ? s.uptime : 0)
    if (p.days > 0) return strings.t("uptime.days").arg(num(p.days)).arg(num(p.hours))
    if (p.hours > 0) return strings.t("uptime.hours").arg(num(p.hours)).arg(num(p.minutes))
    return strings.t("uptime.minutes").arg(num(p.minutes))
  }

  readonly property string windowText: strings.t("graph.window")
    .arg(num(Math.max(1, Math.round(Model.HISTORY * cfg.interval / 60))))

  function open() { root.controller.show() }
  function close() { root.controller.hide() }
  function toggle() { if (root.opened) root.close(); else root.open() }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function setStyle(name) { if (root.hostWidget) root.hostWidget.setStyle(name) }
  function stepStyle(dx) { setStyle(Model.nextStyle(root.cfg.style, dx)) }

  function openMonitor() {
    if (root.hostWidget) root.hostWidget.openMonitor()
    root.close()
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight)

    content: PanelKeyCatcher {
      anchors.fill: parent
      implicitHeight: column.implicitHeight
      onMoveRequested: function(dx, dy) {
        if (dx !== 0) root.stepStyle(dx)
        else if (dy !== 0 && root.hostWidget) root.hostWidget.stepMetric(dy)
      }
      onActivateRequested: root.openMonitor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t, modifiers) { if (t === "b") root.openMonitor() }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        // ---------- Hero: title and mood · CPU load ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroLabels.implicitHeight, heroNumber.implicitHeight)

          Column {
            id: heroLabels
            anchors.left: parent.left
            anchors.right: heroNumber.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            PlainText {
              text: strings.t("title")
              font.pixelSize: Style.font.title
              font.bold: true
              width: parent.width
              elide: Text.ElideRight
            }

            PlainText {
              text: root.statusText.toUpperCase()
              color: root.cpuHot ? root.urgent : Qt.darker(root.fg, 1.4)
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              width: parent.width
              elide: Text.ElideRight
            }
          }

          Row {
            id: heroNumber
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            PlainText {
              id: bigNumber
              text: root.cpu >= 0 ? root.num(Math.round(root.cpu)) : "–"
              color: root.tone
              font.pixelSize: Style.font.displayLarge
              font.bold: true
              font.features: ({ "tnum": 1 })
            }

            PlainText {
              text: "%"
              color: root.tone
              opacity: 0.6
              font.pixelSize: Style.font.title
              font.bold: true
              anchors.baseline: bigNumber.baseline
            }
          }
        }

        // ---------- Graph: CPU over memory ----------
        Column {
          width: parent.width
          spacing: Style.space(6)

          Item {
            width: parent.width
            height: Style.space(78)

            Repeater {
              model: [0.25, 0.5, 0.75]
              Rectangle {
                required property var modelData
                width: parent.width
                height: 1
                y: Math.round(parent.height * (1 - modelData))
                color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, modelData === 0.5 ? 0.08 : 0.04)
              }
            }

            Rectangle {
              width: parent.width
              height: 1
              anchors.bottom: parent.bottom
              color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.12)
            }

            Spark {
              anchors.fill: parent
              values: root.s ? root.s.memHistory : []
              capacity: Model.HISTORY
              color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.45)
              lineWidth: Style.spaceReal(1)
              fillAlpha: 0.06
              showHead: false
            }

            Spark {
              anchors.fill: parent
              visible: root.s && root.s.hasGpu && root.s.gpuHistory.length > 0
              values: root.s ? root.s.gpuHistory : []
              capacity: Model.HISTORY
              color: root.gpuHot ? root.urgent : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.7)
              lineWidth: Style.spaceReal(1.25)
              fillAlpha: 0.1
              showHead: false
            }

            Spark {
              anchors.fill: parent
              values: root.s ? root.s.cpuHistory : []
              capacity: Model.HISTORY
              color: root.tone
              lineWidth: Style.spaceReal(1.75)
              fillAlpha: 0.24
              headSize: Style.spaceReal(5)
              beat: root.opened
            }
          }

          Item {
            width: parent.width
            implicitHeight: legendRow.implicitHeight

            Row {
              id: legendRow
              spacing: Style.space(12)
              Legend { label: strings.t("legend.cpu"); swatch: root.tone }
              Legend { label: strings.t("legend.mem"); swatch: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.45) }
              Legend { visible: root.s && root.s.hasGpu; label: strings.t("legend.gpu"); swatch: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.7) }
            }

            Caption {
              anchors.right: parent.right
              anchors.verticalCenter: legendRow.verticalCenter
              text: root.windowText
            }
          }
        }

        // ---------- Core map: one cell per thread, brighter when busier ----------
        Grid {
          id: coreMap
          width: parent.width
          visible: cores.length > 1
          readonly property var cores: root.s ? root.s.cores : []
          columns: Math.max(1, Math.min(cores.length, 16))
          spacing: Style.space(3)
          readonly property real cell: (width - spacing * (columns - 1)) / columns

          Repeater {
            model: coreMap.cores.length

            Rectangle {
              required property int index
              readonly property real load: Number(coreMap.cores[index])
              readonly property bool hot: load >= root.cfg.alert
              readonly property color tone: hot ? root.urgent : root.fg
              width: coreMap.cell
              height: Math.max(Style.space(6), Math.round(coreMap.cell * 0.45))
              radius: Math.min(height / 2, Math.max(1, Style.cornerRadius / 2))
              color: Qt.rgba(tone.r, tone.g, tone.b, load >= 0 ? 0.08 + 0.82 * Math.min(1, load / 100) : 0.05)
              Behavior on color { ColorAnimation { duration: Style.duration(240); easing.type: Easing.OutCubic } }
            }
          }
        }

        // ---------- Meters ----------
        Grid {
          id: meters
          width: parent.width
          columns: 2
          columnSpacing: Style.space(20)
          rowSpacing: Style.space(12)
          readonly property real cellWidth: (width - columnSpacing) / 2

          Meter {
            width: meters.cellWidth
            metric: "mem"
            label: strings.t("stat.memory")
            value: root.s && root.s.memTotal > 0 ? root.pair(root.s.memUsed, root.s.memTotal) : "—"
            fraction: root.s ? root.s.memFraction : 0
            hot: root.memHot
          }

          Meter {
            width: meters.cellWidth
            metric: "gpu"
            label: strings.t("stat.gpu")
            value: root.s && root.s.hasGpu ? (root.s.gpu >= 0 ? strings.t("unit.percent").arg(root.num(Math.round(root.s.gpu))) + (isFinite(root.s.gpuTemp) ? " · " + root.num(Math.round(root.s.gpuTemp)) + "°" : "") : "—") : strings.t("stat.off")
            fraction: root.s && root.s.hasGpu && root.s.gpu >= 0 ? root.s.gpu / 100 : 0
            hot: root.gpuHot
          }

          Meter {
            width: meters.cellWidth
            icon: Model.ROW_ICONS.swap
            label: strings.t("stat.swap")
            value: root.s && root.s.swapTotal > 0 ? root.pair(root.s.swapUsed, root.s.swapTotal) : strings.t("stat.off")
            fraction: root.s ? root.s.swapFraction : 0
            hot: fraction >= 0.8
          }

          Meter {
            width: meters.cellWidth
            icon: Model.ROW_ICONS.vram
            label: strings.t("stat.vram")
            value: root.s && root.s.hasGpu && root.s.vramTotal > 0 ? root.pair(root.s.vramUsed, root.s.vramTotal) : (root.s && root.s.hasGpu ? "—" : strings.t("stat.off"))
            fraction: root.s && root.s.hasGpu ? root.s.vramFraction : 0
            hot: fraction >= 0.9
          }

          Meter {
            width: meters.cellWidth
            metric: "temp"
            label: strings.t("stat.temp")
            value: root.s && root.s.hasTemp ? strings.t("unit.celsius").arg(root.num(Math.round(root.s.temp))) : "—"
            fraction: root.s ? Model.tempFraction(root.s.temp) : 0
            hot: root.tempHot
          }

          Meter {
            width: meters.cellWidth
            icon: Model.ROW_ICONS.disk
            label: strings.t("stat.disk")
            value: root.s && root.s.diskSize > 0 ? root.pair(root.s.diskUsed, root.s.diskSize) : "—"
            fraction: root.s ? root.s.diskFraction : 0
            hot: fraction >= 0.9
          }
        }

        // ---------- Network, load, uptime ----------
        Row {
          width: parent.width
          spacing: Style.space(20)

          Column {
            width: (parent.width - parent.spacing) / 2
            spacing: Style.spacing.labelGap
            InfoPair { icon: Model.ROW_ICONS.down; label: strings.t("stat.down"); value: root.speed(root.s ? root.s.rxRate : 0) }
            InfoPair { icon: Model.ROW_ICONS.up; label: strings.t("stat.up"); value: root.speed(root.s ? root.s.txRate : 0) }
          }

          Column {
            width: (parent.width - parent.spacing) / 2
            spacing: Style.spacing.labelGap
            InfoPair {
              icon: Model.ROW_ICONS.load
              label: strings.t("stat.load")
              value: root.s ? root.s.load.map(function(v) { return root.num(v, 2) }).join(" ") : "—"
            }
            InfoPair { icon: Model.ROW_ICONS.uptime; label: strings.t("stat.uptime"); value: root.uptimeText }
          }
        }

        PanelSeparator { foreground: root.fg }

        // ---------- Busiest processes ----------
        Column {
          width: parent.width
          spacing: Style.space(6)

          Item {
            width: parent.width
            implicitHeight: Math.max(procHeader.implicitHeight, btopButton.height)

            PanelSectionHeader {
              id: procHeader
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: strings.t("section.processes")
              foreground: root.fg
              fontFamily: root.fontFamily
            }

            PanelActionButton {
              id: btopButton
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              iconText: ""
              tooltipText: strings.t("action.btop")
              foreground: root.fg
              fontFamily: root.fontFamily
              onClicked: root.openMonitor()
            }
          }

          Caption {
            visible: !root.s || root.s.procs.length === 0
            text: strings.t("processes.loading")
          }

          Repeater {
            model: root.s ? root.s.procs : []

            Item {
              id: proc
              required property var modelData
              required property int index
              readonly property real lead: root.s && root.s.procs.length > 0 ? Math.max(1, root.s.procs[0].cpu) : 1

              width: parent.width
              height: Style.space(22)

              // Share of the busiest process, as a faint bar behind the row.
              Rectangle {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                height: parent.height
                radius: Style.cornerRadius > 0 ? Math.min(Style.cornerRadius, height / 2) : 0
                width: Math.max(0, parent.width * Math.min(1, proc.modelData.cpu / proc.lead))
                color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, proc.index === 0 ? 0.09 : 0.05)
                Behavior on width { NumberAnimation { duration: Style.duration(220); easing.type: Easing.OutCubic } }
              }

              PlainText {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(8)
                anchors.right: procCpu.left
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                text: proc.modelData.name
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }

              PlainText {
                id: procCpu
                anchors.right: procMem.left
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                width: cpuColumn.advanceWidth
                horizontalAlignment: Text.AlignRight
                text: strings.t("unit.percent").arg(root.num(proc.modelData.cpu, 1))
                font.pixelSize: Style.font.bodySmall
                font.features: ({ "tnum": 1 })
              }

              PlainText {
                id: procMem
                anchors.right: parent.right
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                width: memColumn.advanceWidth
                horizontalAlignment: Text.AlignRight
                text: strings.t("unit.mem").arg(root.num(proc.modelData.mem, 1))
                opacity: 0.55
                font.pixelSize: Style.font.bodySmall
                font.features: ({ "tnum": 1 })
              }
            }
          }
        }

        PanelSeparator { foreground: root.fg }

        // ---------- Bar look ----------
        Column {
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: strings.t("section.bar")
            foreground: root.fg
            fontFamily: root.fontFamily
          }

          Row {
            id: styleRow
            width: parent.width
            spacing: Style.space(6)
            readonly property real cellWidth: (width - spacing * (Model.STYLES.length - 1)) / Model.STYLES.length

            Repeater {
              model: Model.STYLES
              Button {
                required property var modelData
                width: styleRow.cellWidth
                text: strings.t("style." + modelData)
                fontSize: Style.font.bodySmall
                foreground: root.fg
                fontFamily: root.fontFamily
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
                bordered: true
                active: root.cfg.style === modelData
                onClicked: root.setStyle(modelData)
              }
            }
          }

          // ---------- Unified Metric Selection & Ordering ----------
          Column {
            width: parent.width
            spacing: Style.space(8)

            Item {
              width: parent.width
              implicitHeight: Math.max(metricHeader.implicitHeight, allButton.height)

              PanelSectionHeader {
                id: metricHeader
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: strings.t("section.metrics")
                foreground: root.fg
                fontFamily: root.fontFamily
              }

              Button {
                id: allButton
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: strings.t("metric.all")
                fontSize: Style.font.caption
                fontFamily: root.fontFamily
                foreground: root.fg
                horizontalPadding: Style.space(10)
                verticalPadding: Style.space(3)
                bordered: true
                active: root.hostWidget && root.hostWidget.isMetricActive("all")
                onClicked: if (root.hostWidget) root.hostWidget.toggleMetric("all")
              }
            }

            Grid {
              id: metricGrid
              width: parent.width
              columns: 3
              spacing: Style.space(4)
              readonly property var list: root.hostWidget ? root.hostWidget.orderedMetrics : []
              readonly property real cellWidth: Math.floor((width - spacing * (columns - 1)) / columns)

              Repeater {
                model: metricGrid.list

                BorderSurface {
                  id: chip
                  required property var modelData
                  required property int index
                  readonly property bool active: root.hostWidget && root.hostWidget.isMetricActive(modelData)
                  readonly property int total: metricGrid.list.length
                  readonly property bool temperature: modelData === "temp" || modelData === "gpuTemp"

                  width: metricGrid.cellWidth
                  height: Style.space(38)
                  radius: Style.cornerRadius
                  borderSpec: chip.active
                    ? Border.controlSpec("selected", root.fg, Style.accent)
                    : Border.controlSpec("normal", root.fg, Style.accent)
                  color: chip.active
                    ? Style.selectedFillFor(root.fg, Style.accent)
                    : (centerMouse.containsMouse ? Style.hoverFillFor(root.fg, Style.accent) : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.04))
                  opacity: chip.active ? 1.0 : (centerMouse.containsMouse ? 0.75 : 0.45)

                  Behavior on opacity { NumberAnimation { duration: Style.duration(150) } }
                  Behavior on color { ColorAnimation { duration: Style.duration(150) } }

                  // Left arrow: moves metric left
                  Button {
                    id: leftArrow
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.margins: Style.space(1)
                    width: Style.space(14)
                    enabled: chip.index > 0
                    opacity: enabled ? 0.9 : 0.15
                    horizontalPadding: 0
                    verticalPadding: 0
                    text: "‹"
                    fontSize: Style.font.bodySmall
                    foreground: root.fg
                    bordered: false
                    onClicked: if (root.hostWidget) root.hostWidget.moveMetric(chip.index, -1)
                  }

                  // Right arrow: moves metric right
                  Button {
                    id: rightArrow
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.margins: Style.space(1)
                    width: Style.space(14)
                    enabled: chip.index < chip.total - 1
                    opacity: enabled ? 0.9 : 0.15
                    horizontalPadding: 0
                    verticalPadding: 0
                    text: "›"
                    fontSize: Style.font.bodySmall
                    foreground: root.fg
                    bordered: false
                    onClicked: if (root.hostWidget) root.hostWidget.moveMetric(chip.index, 1)
                  }

                  // Center toggle area: click toggles metric on/off
                  Item {
                    id: centerArea
                    anchors.left: leftArrow.right
                    anchors.right: rightArrow.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom

                    Row {
                      anchors.centerIn: parent
                      spacing: Style.space(3)
                      width: Math.min(implicitWidth, parent.width)

                      MetricIcon {
                        id: chipIcon
                        visible: !chip.temperature
                        size: Style.font.body
                        glyphSize: Style.font.body
                        metric: chip.modelData
                        color: root.fg
                        anchors.verticalCenter: parent.verticalCenter
                      }

                      PlainText {
                        text: strings.t("metric." + chip.modelData)
                        width: Math.min(implicitWidth, Math.max(0, centerArea.width - (chipIcon.visible ? chipIcon.width + parent.spacing : 0)))
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: Style.font.bodySmall
                        font.bold: chip.active
                        color: root.fg
                        anchors.verticalCenter: parent.verticalCenter
                      }
                    }

                    MouseArea {
                      id: centerMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: if (root.hostWidget) root.hostWidget.toggleMetric(chip.modelData)
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  // Column widths for the process rows, measured on the widest figures so
  // the numbers line up and never run into each other in any language.
  TextMetrics {
    id: cpuColumn
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    text: strings.t("unit.percent").arg(root.num(888.8, 1))
  }

  TextMetrics {
    id: memColumn
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    text: strings.t("unit.mem").arg(root.num(88.8, 1))
  }

  // ---------- Building blocks ----------

  component PlainText: Text {
    textFormat: Text.PlainText
    color: root.fg
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
  }

  component Caption: PlainText {
    opacity: 0.6
    font.pixelSize: Style.font.caption
  }

  component Legend: Row {
    property string label: ""
    property color swatch: root.fg
    spacing: Style.space(5)

    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(10)
      height: Math.max(2, Style.space(2))
      radius: height / 2
      color: parent.swatch
    }

    Caption { text: parent.label }
  }

  component Meter: Column {
    id: meter
    property string metric: ""
    property string icon: ""
    property string label: ""
    property string value: ""
    property real fraction: 0
    property bool hot: false
    readonly property color tone: hot ? root.urgent : root.fg
    spacing: Style.space(5)

    Item {
      width: parent.width
      implicitHeight: Math.max(meterLabelRow.implicitHeight, meterValue.implicitHeight)

      Row {
        id: meterLabelRow
        anchors.left: parent.left
        anchors.right: meterValue.left
        anchors.rightMargin: Style.space(6)
        spacing: Style.space(5)

        MetricIcon {
          visible: meter.metric !== ""
          metric: meter.metric
          size: Style.font.bodySmall
          glyphSize: Style.font.bodySmall
          color: root.fg
          opacity: 0.6
          anchors.verticalCenter: parent.verticalCenter
        }

        PlainText {
          visible: meter.metric === "" && meter.icon !== ""
          text: meter.icon
          opacity: 0.6
          font.pixelSize: Style.font.bodySmall
          anchors.verticalCenter: parent.verticalCenter
        }

        PlainText {
          id: meterLabel
          text: meter.label
          opacity: 0.6
          elide: Text.ElideRight
          font.pixelSize: Style.font.bodySmall
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      PlainText {
        id: meterValue
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: meter.value
        color: meter.tone
        font.pixelSize: Style.font.bodySmall
        font.features: ({ "tnum": 1 })
      }
    }

    Item {
      width: parent.width
      height: Math.max(2, Style.space(3))

      Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.12)
      }

      Rectangle {
        height: parent.height
        radius: height / 2
        width: Math.max(height, parent.width * Math.max(0, Math.min(1, meter.fraction)))
        color: meter.tone
        Behavior on width { NumberAnimation { duration: Style.duration(260); easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: Style.duration(200) } }
      }
    }
  }

  component InfoPair: Item {
    property string icon: ""
    property string label: ""
    property string value: ""
    width: parent.width
    implicitHeight: Math.max(pairLabel.implicitHeight, pairValue.implicitHeight)

    PlainText {
      id: pairLabel
      anchors.left: parent.left
      anchors.right: pairValue.left
      anchors.rightMargin: Style.space(6)
      text: parent.icon !== "" ? parent.icon + " " + parent.label : parent.label
      opacity: 0.6
      elide: Text.ElideRight
      font.pixelSize: Style.font.bodySmall
    }

    PlainText {
      id: pairValue
      anchors.right: parent.right
      text: parent.value
      font.pixelSize: Style.font.bodySmall
      font.features: ({ "tnum": 1 })
    }
  }
}
