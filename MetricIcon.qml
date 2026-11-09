import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

Item {
  id: root
  property string metric: "cpu"
  property color color: "white"
  property real size: Style.bar.iconCanvas
  property real glyphSize: Math.round(Style.bar.iconSize * 0.92)
  property string fontFamily: Style.font.family

  implicitWidth: size
  implicitHeight: size

  OpticalGlyph {
    visible: root.metric !== "gpu"
    x: Math.round((root.width - width) / 2)
    y: Math.round((root.height - height) / 2)
    width: root.size
    height: root.size
    text: Model.ICONS[root.metric] || ""
    fontFamily: root.fontFamily
    fontSize: Style.bar.iconFont
    paintedSize: root.glyphSize
    color: root.color
    opacity: 0.85
    Behavior on color { ColorAnimation { duration: Style.duration(200) } }
  }

  GpuIcon {
    visible: root.metric === "gpu"
    anchors.centerIn: parent
    width: root.glyphSize
    height: root.glyphSize
    color: root.color
    opacity: 0.85
    Behavior on color { ColorAnimation { duration: Style.duration(200) } }
  }
}
