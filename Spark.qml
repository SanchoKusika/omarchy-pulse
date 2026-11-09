import QtQuick
import QtQuick.Shapes
import qs.Commons

// A smoothed sparkline of 0..1 values, newest at the end, drawn as vectors so
// it stays crisp at any scale. The area under the line fades out toward the
// baseline. A dot marks the newest sample; with `beat` it sends out a small
// ring each time a sample lands.
//
// Horizontal: time runs left to right, value grows upward.
// Vertical (left/right bars): time runs top to bottom, value grows rightward.
Item {
  id: root

  property var values: []
  property int capacity: 24
  property color color: "white"
  property real lineWidth: 1.5
  property real fillAlpha: 0.22
  property bool vertical: false
  property bool showHead: true
  property bool beat: false
  property real headSize: lineWidth * 2.6
  // Square-root scale: lifts the low loads a quiet machine spends its time
  // at, so an idle line still breathes instead of lying on the baseline.
  property bool lift: false
  // Scale the top of the plot to the visible peak (with headroom), never
  // below `scaleFloor`, so small changes still show at bar size.
  property bool autoScale: false
  property real scaleFloor: 0.25

  readonly property real inset: Math.max(lineWidth, showHead ? headSize / 2 : 0)
  readonly property var raw: project()
  readonly property var line: smooth(raw)
  readonly property var area: close(line)
  readonly property point head: raw.length > 0 ? raw[raw.length - 1] : Qt.point(-100, -100)

  function clamp01(v) { return Math.max(0, Math.min(1, Number(v) || 0)) }

  function map(t, v) {
    var w = Math.max(0, width - inset * 2)
    var h = Math.max(0, height - inset * 2)
    return Qt.point(inset + t * w, inset + (1 - v) * h)
  }

  function project() {
    var vals = values || []
    var n = Math.min(vals.length, capacity)
    var start = vals.length - n
    var span = Math.max(1, capacity - 1)
    var scaled = []
    var peak = 0
    for (var i = 0; i < n; i++) {
      var v = clamp01(vals[start + i])
      if (lift) v = Math.sqrt(v)
      scaled.push(v)
      peak = Math.max(peak, v)
    }
    var top = autoScale ? Math.min(1, Math.max(scaleFloor, peak * 1.2)) : 1
    var pts = []
    for (var j = 0; j < n; j++)
      pts.push(map((capacity - n + j) / span, clamp01(scaled[j] / top)))
    return pts
  }

  // Catmull-Rom through the samples, a few steps per segment, held inside
  // the plot so the curve never overshoots past 0 or 100%.
  function smooth(pts) {
    if (pts.length < 3) return pts
    var lo = inset, hiX = width - inset, hiY = height - inset
    var out = [pts[0]]
    var steps = 4
    for (var i = 0; i < pts.length - 1; i++) {
      var p0 = pts[Math.max(0, i - 1)], p1 = pts[i], p2 = pts[i + 1], p3 = pts[Math.min(pts.length - 1, i + 2)]
      for (var s = 1; s <= steps; s++) {
        var t = s / steps, t2 = t * t, t3 = t2 * t
        var x = 0.5 * (2 * p1.x + (-p0.x + p2.x) * t + (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2 + (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * t3)
        var y = 0.5 * (2 * p1.y + (-p0.y + p2.y) * t + (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2 + (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * t3)
        out.push(Qt.point(Math.max(lo, Math.min(hiX, x)), Math.max(lo, Math.min(hiY, y))))
      }
    }
    return out
  }

  function close(pts) {
    if (pts.length < 2) return []
    var first = pts[0], last = pts[pts.length - 1]
    var out = pts.slice()
    out.push(Qt.point(last.x, height - inset))
    out.push(Qt.point(first.x, height - inset))
    out.push(first)
    return out
  }

  onValuesChanged: if (beat && showHead && raw.length > 0) ripple.restart()

  Shape {
    anchors.fill: parent
    visible: root.line.length > 1
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      strokeColor: "transparent"
      strokeWidth: 0
      fillGradient: LinearGradient {
        x1: 0
        y1: 0
        x2: 0
        y2: root.height
        GradientStop { position: 0; color: Qt.rgba(root.color.r, root.color.g, root.color.b, root.fillAlpha) }
        GradientStop { position: 1; color: Qt.rgba(root.color.r, root.color.g, root.color.b, 0) }
      }
      PathPolyline { path: root.area }
    }

    ShapePath {
      strokeColor: root.color
      strokeWidth: root.lineWidth
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      PathPolyline { path: root.line }
    }
  }

  Rectangle {
    id: ring
    visible: root.showHead && root.beat
    width: root.headSize
    height: width
    radius: width / 2
    x: root.head.x - width / 2
    y: root.head.y - height / 2
    color: "transparent"
    border.width: Math.max(1, root.lineWidth * 0.7)
    border.color: root.color
    opacity: 0
  }

  ParallelAnimation {
    id: ripple
    NumberAnimation { target: ring; property: "scale"; from: 1; to: 2.6; duration: Style.duration(280); easing.type: Easing.OutCubic }
    NumberAnimation { target: ring; property: "opacity"; from: 0.7; to: 0; duration: Style.duration(280); easing.type: Easing.OutCubic }
  }

  Rectangle {
    visible: root.showHead && root.raw.length > 0
    width: root.headSize
    height: width
    radius: width / 2
    x: root.head.x - width / 2
    y: root.head.y - height / 2
    color: root.color
    Behavior on color { ColorAnimation { duration: Style.duration(200) } }
  }
}
