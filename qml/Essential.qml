// An essential: a page that stands as a button, over the tabs and on the start page. The left
// button opens it, or goes to it when it is open; the right one lets go of it; held down it is
// carried to another place among the others. `large` is the one of the start page, with its
// name under the picture.
import QtQuick
import Strix

Item {
    id: tile

    property string title
    property string address
    property string icon
    property bool large: false
    /// Its page is loaded in this window
    property bool open: false
    /// Its page is the one that is shown
    property bool selected: false
    /// Its place among the essentials, how many stand in a row, and the gap between them: what
    /// carrying it needs to know
    property int place: 0
    property int inRow: 1
    property int gap: Theme.space1
    property int count: 1

    signal clicked()
    signal dropped()
    /// It was carried to this place
    signal arranged(int to)

    readonly property string host: address.replace(/^[a-z]+:\/\/(www\.)?([^\/]+).*$/, "$2")

    implicitWidth: large ? 148 : 56
    implicitHeight: large ? 96 : Theme.control + Theme.space3
    // Carried, it lies over the others
    z: area.carrying ? 2 : 0

    // The place that takes the pointer stays; what is drawn of the tile follows the pointer
    MouseArea {
        id: area
        property bool carrying: false
        property point from: Qt.point(0, 0)
        property real dx: 0
        property real dy: 0
        /// The left button is down on this tile; letting go ends it before the tile is moved
        property bool held: false
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        preventStealing: true
        onPressed: mouse => {
            area.from = Qt.point(mouse.x, mouse.y)
            area.held = mouse.button === Qt.LeftButton
        }
        onPositionChanged: mouse => {
            if (!area.held || tile.count < 2) return
            const x = mouse.x - area.from.x
            const y = mouse.y - area.from.y
            if (!area.carrying && Math.abs(x) + Math.abs(y) > Theme.space2) area.carrying = true
            if (area.carrying) {
                area.dx = x
                area.dy = y
            }
        }
        onCanceled: {
            area.held = false
            area.carrying = false
            area.dx = 0
            area.dy = 0
        }
        onReleased: mouse => {
            area.held = false
            if (!area.carrying) {
                if (area.containsMouse) mouse.button === Qt.RightButton ? tile.dropped() : tile.clicked()
                return
            }
            const column = Math.max(0, Math.min(tile.inRow - 1, tile.place % tile.inRow + Math.round(area.dx / (tile.width + tile.gap))))
            const row = Math.max(0, Math.floor(tile.place / tile.inRow) + Math.round(area.dy / (tile.height + tile.gap)))
            area.carrying = false
            area.dx = 0
            area.dy = 0
            const to = Math.min(tile.count - 1, row * tile.inRow + column)
            if (to !== tile.place) tile.arranged(to)
        }
    }

    Rectangle {
        id: plate
        width: parent.width
        height: parent.height
        x: area.dx
        y: area.dy
        radius: Theme.radiusMd
        color: tile.selected ? Theme.surfaceRaised : Theme.alpha(Theme.text, area.containsMouse ? 0.09 : 0.04)
        border.width: Theme.lineHair
        border.color: area.containsMouse || tile.selected ? Theme.borderStrong : Theme.glassEdge
        scale: area.pressed && !area.carrying ? 0.97 : 1
        Behavior on color { ColorAnimation { duration: Theme.durFast } }
        Behavior on border.color { ColorAnimation { duration: Theme.durFast } }
        Behavior on scale { NumberAnimation { duration: Theme.durInstant } }

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
    }

    // Under the tile: the ones of the strip stand at the top of the window
    ToolTip { y: tile.height + Theme.space1; text: tile.title || tile.host; visible: area.containsMouse && !tile.large && !area.carrying }
}
