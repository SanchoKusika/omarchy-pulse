import QtQuick
import QtQuick.Shapes
import qs.Commons

Item {
  id: root
  property color color: "white"
  property real strokeWidth: 2

  implicitWidth: 16
  implicitHeight: 16

  Shape {
    anchors.centerIn: parent
    width: 24
    height: 24
    scale: Math.min(root.width, root.height) / 24
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      strokeColor: root.color
      strokeWidth: root.strokeWidth
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      fillColor: "transparent"
      PathSvg {
        path: "M 2 17 L 20 17 C 21.1046 17 22 16.1046 22 15 L 22 7 C 22 5.89543 21.1046 5 20 5 L 2 5 M 2 21 L 2 3 M 7 17 L 7 20 C 7 20.5523 7.44772 21 8 21 L 13 21 C 13.5523 21 14 20.5523 14 20 L 14 17 M 14 11 A 2 2 0 1 0 18 11 A 2 2 0 1 0 14 11 M 6 11 A 2 2 0 1 0 10 11 A 2 2 0 1 0 6 11"
      }
    }
  }
}
