import QtQuick
import qs.Commons
import qs.Ui

// The "bars" look: one icon and one slim meter per metric.
//
// Horizontal bar:  [icon]▮ [icon]▮ [icon]▮   meters fill upward
// Vertical bar:    icon over a meter that fills rightward, three stacked
//
// Geometry is set explicitly for both orientations rather than through
// conditional anchors, so turning the bar never leaves a stale offset.
Item {
  id: root

  // [{ icon, value: 0..1, hot: bool, known: bool }]
  property var items: []
  property color color: "white"
  property color hotColor: "red"
  property string fontFamily: Style.font.family
  property bool vertical: false
  property real barSize: Style.bar.sizeHorizontal

  readonly property real box: Style.bar.iconCanvas
  readonly property real cross: vertical ? Math.max(box, barSize - Style.space(10)) : box
  readonly property real glyphSize: Math.round(Style.bar.iconSize * 0.92)
  readonly property real thick: Math.max(2, Style.spaceReal(3))
  readonly property real innerGap: Style.spaceReal(vertical ? 3 : 2.5)
  readonly property real groupGap: Style.spaceReal(vertical ? 8 : 7)
  readonly property real groupLength: box + innerGap + thick
  readonly property int count: items.length

  implicitWidth: vertical ? cross : count * groupLength + Math.max(0, count - 1) * groupGap
  implicitHeight: vertical ? count * groupLength + Math.max(0, count - 1) * groupGap : box

  Repeater {
    model: root.count

    Item {
      id: group
      required property int index
      readonly property var item: root.items[index] || ({})
      readonly property real value: Math.max(0, Math.min(1, Number(item.value) || 0))
      readonly property color tone: item.hot ? root.hotColor : root.color

      x: root.vertical ? 0 : index * (root.groupLength + root.groupGap)
      y: root.vertical ? index * (root.groupLength + root.groupGap) : 0
      width: root.vertical ? root.box : root.groupLength
      height: root.vertical ? root.groupLength : root.box

      MetricIcon {
        x: 0
        y: 0
        size: root.box
        glyphSize: root.glyphSize
        metric: group.item.id || ""
        fontFamily: root.fontFamily
        color: group.tone
        opacity: group.item.known === false ? 0.35 : 0.85
      }

      Item {
        id: track
        x: root.vertical ? 0 : root.box + root.innerGap
        y: root.vertical ? root.box + root.innerGap : 0
        width: root.vertical ? root.box : root.thick
        height: root.vertical ? root.thick : root.box
        opacity: group.item.known === false ? 0.35 : 1

        Rectangle {
          anchors.fill: parent
          radius: root.thick / 2
          color: Qt.rgba(group.tone.r, group.tone.g, group.tone.b, 0.2)
        }

        // At least a dot, so an idle meter still reads as a meter.
        Rectangle {
          radius: root.thick / 2
          color: group.tone
          x: 0
          width: root.vertical ? Math.max(root.thick, track.width * group.value) : track.width
          height: root.vertical ? track.height : Math.max(root.thick, track.height * group.value)
          y: root.vertical ? 0 : track.height - height

          Behavior on width { NumberAnimation { duration: Style.duration(220); easing.type: Easing.OutCubic } }
          Behavior on height { NumberAnimation { duration: Style.duration(220); easing.type: Easing.OutCubic } }
          Behavior on color { ColorAnimation { duration: Style.duration(200) } }
        }
      }
    }
  }
}
