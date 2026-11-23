// One page in a list: a tab, a bookmark, something that was opened before. Its picture, its
// name, and at the right a word about it or, under the pointer, the cross that lets go of it.
// A tab is chosen as the button goes down and can be carried to another place in its list; the
// middle button lets go of it, the right one asks for its menu.
import QtQuick
import Strix

Item {
    id: row

    property string title
    property string icon
    /// What the letter is taken from while the page has no picture; empty shows a globe
    property string named: title
    /// Small text at the right: where the page lives
    property string detail
    property bool selected: false
    /// The selected look comes from a Glide that moves between the rows
    property bool glide: false
    /// The page is on its way
    property bool busy: false
    /// The page plays sound
    property bool sounding: false
    /// The sound of the page is off
    property bool muted: false
    /// It can be let go of: the cross and the middle button
    property bool closable: false
    /// It can be carried up and down
    property bool movable: false
    /// It is being carried
    readonly property bool carried: area.carrying
    readonly property bool hovered: area.containsMouse || cross.hovered || speaker.hovered

    signal clicked()
    signal closed()
    /// The right button, at this place in the row
    signal asked(real x, real y)
    /// The speaker was pressed
    signal sound()
    /// Carried: the pointer is at this height in the row; and let go
    signal carry(real y)
    signal drop()

    implicitWidth: 320
    implicitHeight: Theme.control + Theme.space2 - Theme.lineBold
    opacity: carried ? 0.6 : 1

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusMd
        color: row.hovered && !(row.glide && row.selected) || row.selected && !row.glide ? Theme.surfaceRaised : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.durFast } }
    }
    MouseArea {
        id: area
        property bool carrying: false
        property real from: 0
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        // The list it stands in does not take the pointer away while a row is carried
        preventStealing: row.movable
        onPressed: mouse => {
            if (mouse.button === Qt.RightButton) row.asked(mouse.x, mouse.y)
            else if (mouse.button === Qt.LeftButton) {
                area.from = mouse.y
                row.clicked()
            }
        }
        onPositionChanged: mouse => {
            if (!row.movable || !(mouse.buttons & Qt.LeftButton)) return
            if (!area.carrying && Math.abs(mouse.y - area.from) > Theme.space2) area.carrying = true
            if (area.carrying) row.carry(mouse.y)
        }
        onReleased: mouse => {
            if (mouse.button === Qt.MiddleButton && row.closable && area.containsMouse) row.closed()
            if (!area.carrying) return
            area.carrying = false
            row.drop()
        }
    }

    Row {
        x: Theme.space3
        width: parent.width - x - Theme.space2
        height: parent.height
        spacing: Theme.space2

        Item {
            width: Theme.icon
            height: Theme.icon
            anchors.verticalCenter: parent.verticalCenter
            Favicon {
                visible: !row.busy
                source: row.icon
                name: row.named
            }
            Icon {
                visible: row.busy
                name: "refresh-cw"
                color: Theme.accentText
                tinted: false
                RotationAnimator on rotation { running: row.busy; from: 0; to: 360; duration: Theme.durLoop; loops: Animation.Infinite }
            }
        }
        Label {
            width: parent.width - Theme.icon - parent.spacing - (tail.width > 0 ? tail.width + parent.spacing : 0)
            anchors.verticalCenter: parent.verticalCenter
            text: row.title
            color: row.selected || row.hovered ? Theme.text : Theme.textMuted
            elide: Text.ElideRight
            Behavior on color { ColorAnimation { duration: Theme.durFast } }
        }
        Row {
            id: tail
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.space1
            IconButton {
                id: speaker
                visible: row.sounding || row.muted
                iconName: row.muted ? "volume-x" : "volume-2"
                onClicked: row.sound()
            }
            Label {
                visible: row.detail !== "" && !cross.visible
                text: row.detail
                textStyle: "caption"
                color: Theme.textFaint
                width: Math.min(implicitWidth, row.width * 0.4)
                elide: Text.ElideRight
                anchors.verticalCenter: parent.verticalCenter
            }
            IconButton {
                id: cross
                visible: row.closable && row.hovered
                iconName: "x"
                onClicked: row.closed()
            }
        }
    }
}
