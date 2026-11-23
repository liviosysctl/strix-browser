// An essential: a page that stands as a button, over the tabs and on the start page. The left
// button opens it, or goes to it when it is open; the right one lets go of it. `large` is the
// one of the start page, with its name under the picture.
import QtQuick
import Strix

Rectangle {
    id: tile

    property string title
    property string address
    property string icon
    property bool large: false
    /// Its page is loaded in this window
    property bool open: false
    /// Its page is the one that is shown
    property bool selected: false

    signal clicked()
    signal dropped()

    readonly property string host: address.replace(/^[a-z]+:\/\/(www\.)?([^\/]+).*$/, "$2")

    implicitWidth: large ? 148 : 56
    implicitHeight: large ? 96 : Theme.control + Theme.space3
    radius: Theme.radiusMd
    color: selected ? Theme.surfaceRaised : Theme.alpha(Theme.text, area.containsMouse ? 0.09 : 0.04)
    border.width: Theme.lineHair
    border.color: area.containsMouse || selected ? Theme.borderStrong : Theme.glassEdge
    scale: area.pressed ? 0.97 : 1
    Behavior on color { ColorAnimation { duration: Theme.durFast } }
    Behavior on border.color { ColorAnimation { duration: Theme.durFast } }
    Behavior on scale { NumberAnimation { duration: Theme.durInstant } }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => mouse.button === Qt.RightButton ? tile.dropped() : tile.clicked()
    }

    Column {
        anchors.centerIn: parent
        width: parent.width - 2 * Theme.space2
        spacing: Theme.space2
        Favicon {
            anchors.horizontalCenter: parent.horizontalCenter
            source: tile.icon
            name: tile.title || tile.host
            size: tile.large ? 28 : 18
        }
        Label {
            visible: tile.large
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: tile.title || tile.host
            textStyle: "label"
            color: area.containsMouse ? Theme.text : Theme.textMuted
            elide: Text.ElideRight
        }
    }

    // A short line in the accent under an essential that is open, a longer one under the one shown
    Rectangle {
        anchors { bottom: parent.bottom; bottomMargin: Theme.space1; horizontalCenter: parent.horizontalCenter }
        width: tile.selected ? Theme.icon : tile.open ? Theme.space1 : 0
        height: Theme.lineBold
        radius: height / 2
        color: Theme.accent
        Behavior on width { NumberAnimation { duration: Theme.durBase; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
    }

    ToolTip { text: tile.title || tile.host; visible: area.containsMouse && !tile.large }
}
