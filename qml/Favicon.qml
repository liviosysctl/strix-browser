// The small picture a page brings along. Until it is there, or for a page that has none, the
// first letter of its name stands in its place, or a globe.
import QtQuick
import Strix

Item {
    id: root

    /// The address of the picture
    property string source
    /// The name of the page, for its letter
    property string name
    property int size: Theme.icon

    implicitWidth: size
    implicitHeight: size

    Image {
        id: picture
        anchors.fill: parent
        source: root.source
        sourceSize: Qt.size(2 * root.size, 2 * root.size)
        asynchronous: true
        visible: status === Image.Ready && implicitWidth > 0
    }
    Label {
        visible: !picture.visible && root.name !== ""
        anchors.centerIn: parent
        text: root.name.replace(/^(https?:\/\/)?(www\.)?/, "").charAt(0).toUpperCase()
        textStyle: "subtitle"
        font.pixelSize: root.size
        lineHeight: root.size
        color: Theme.textMuted
    }
    Icon {
        visible: !picture.visible && root.name === ""
        name: "globe"
        size: root.size
    }
}
