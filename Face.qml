import QtQuick
import qs.Commons
import qs.Ui

// The "pulse" and "number" looks: the followed metric's icon, then either
// its sparkline or its value. Supports multiple metrics side-by-side (horizontal)
// or stacked (vertical).
//
// Horizontal bar:  [icon] ∿∿∿∿   [icon] ∿∿∿∿   or  [icon] 23%  [icon] 45%
// Vertical bar:    [icon] over horizontal ∿∿∿∿ sparkline, or over value
Item {
  id: root

  property string look: "pulse"          // "pulse" | "text"
  property var items: []                 // [{ icon, values, label, tone, beat, lift }, ...]
  property string icon: ""
  property var values: []                 // 0..1 history for the sparkline (fallback)
  property string label: ""
  property string widestLabel: "100%"
  property color tone: "white"
  property bool beat: false
  property bool lift: false
  property bool vertical: false
  property real barSize: Style.bar.sizeHorizontal
  property string fontFamily: Style.font.family
  property int capacity: 24

  readonly property var actualItems: items && items.length > 0
    ? items
    : [{ icon: root.icon, values: root.values, label: root.label, tone: root.tone, beat: root.beat, lift: root.lift }]
  readonly property int count: actualItems.length

  readonly property real box: Style.bar.iconCanvas
  readonly property real gap: Style.spaceReal(vertical ? 2.5 : 3.5)
  readonly property real itemGap: Style.spaceReal(vertical ? 8 : 7)
  readonly property real sparkLength: Style.space(30)
  readonly property real sparkHeight: vertical ? Math.max(12, Style.space(16)) : box
  readonly property real cross: vertical ? Math.max(box, barSize - Style.space(10)) : box
  readonly property real labelLength: vertical
    ? Math.ceil(widest.tightBoundingRect.height) + Style.space(2)
    : Math.ceil(widest.advanceWidth)
  readonly property real labelHeight: vertical
    ? Math.ceil(widest.tightBoundingRect.height) + Style.space(2)
    : box
  readonly property real bodyLength: look === "pulse" ? sparkLength : labelLength

  readonly property real itemWidth: box + gap + bodyLength
  readonly property real itemHeight: box + gap + (look === "pulse" ? sparkHeight : labelHeight)

  implicitWidth: vertical
    ? cross
    : count * itemWidth + Math.max(0, count - 1) * itemGap
  implicitHeight: vertical
    ? count * itemHeight + Math.max(0, count - 1) * itemGap
    : box

  TextMetrics {
    id: widest
    font.family: root.fontFamily
    font.pixelSize: Style.bar.iconFont
    text: root.widestLabel
  }

  FontMetrics {
    id: figures
    font.family: root.fontFamily
    font.pixelSize: Style.bar.iconFont
  }

  Repeater {
    model: root.count

    Item {
      id: cell
      required property int index
      readonly property var item: root.actualItems[index] || ({})
      readonly property color itemTone: item.tone || root.tone

      x: root.vertical ? 0 : index * (root.itemWidth + root.itemGap)
      y: root.vertical ? index * (root.itemHeight + root.itemGap) : 0
      width: root.vertical ? root.cross : root.itemWidth
      height: root.vertical ? root.itemHeight : root.box

      MetricIcon {
        x: root.vertical ? Math.round((root.cross - root.box) / 2) : 0
        y: 0
        size: root.box
        metric: cell.item.id || "cpu"
        fontFamily: root.fontFamily
        color: cell.itemTone
      }

      Item {
        x: root.vertical ? 0 : root.box + root.gap
        y: root.vertical ? root.box + root.gap : 0
        width: root.vertical ? root.cross : root.bodyLength
        height: root.vertical ? (root.look === "pulse" ? root.sparkHeight : root.labelHeight) : root.box

        Spark {
          anchors.fill: parent
          visible: root.look === "pulse"
          values: cell.item.values || []
          capacity: root.capacity
          vertical: false
          color: cell.itemTone
          lineWidth: Math.max(1, Style.spaceReal(1.25))
          fillAlpha: 0.28
          headSize: Style.spaceReal(3)
          lift: cell.item.lift === true
          autoScale: true
          beat: cell.item.beat === true
          Behavior on color { ColorAnimation { duration: Style.duration(200) } }
        }

        Text {
          visible: root.look === "text"
          width: parent.width
          y: (parent.height - height) / 2
            + (root.vertical ? 0 : (figures.descent - figures.ascent + figures.tightBoundingRect("0").height) / 2)
          textFormat: Text.PlainText
          text: cell.item.label || ""
          horizontalAlignment: root.vertical ? Text.AlignHCenter : Text.AlignLeft
          color: cell.itemTone
          font.family: root.fontFamily
          font.pixelSize: Style.bar.iconFont
          font.features: ({ "tnum": 1 })
          renderType: Text.NativeRendering
          Behavior on color { ColorAnimation { duration: Style.duration(200) } }
        }
      }
    }
  }
}
