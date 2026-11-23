// The start page: what stands in the window while no page does. The hour, the essentials as
// large buttons, the bookmarks and what was opened lately, one under the other around the
// middle of the page. It is glass like the rest of the window, so the picture of the desktop
// shows through. It has no field of its own: Ctrl T, or simply typing, lets the address float.
import QtQuick
import Strix

Item {
    id: root

    required property var browser
    /// A page was chosen: its address
    signal open(string address)
    /// An essential was chosen
    signal essential(string address)
    /// The address is wanted, with these letters already typed
    signal ask(string text)

    property var marks: []
    property var lately: []
    /// The field that takes the address of a new essential is out
    property bool adding: false
    property date now: new Date()

    /// The width of a large essential and how many stand in a row
    readonly property int tile: 148
    readonly property int perRow: Math.max(1, Math.min(4, Math.floor((column.width + Theme.space2) / (tile + Theme.space2))))
    /// The lists that have something to show
    readonly property var lists: [{ name: "Bookmarks", pages: root.marks }, { name: "Opened lately", pages: root.lately }].filter(list => list.pages.length > 0)

    function look() {
        root.now = new Date()
        root.browser.look()
        root.browser.call("bookmarks", { text: "", limit: 6 }, pages => root.marks = pages || [])
        if (!root.browser.secret) root.browser.call("history", { text: "", limit: 6 }, pages => root.lately = pages || [])
    }
    onVisibleChanged: if (visible) root.look()
    Connections {
        target: root.browser
        function onConnectedChanged() { if (root.visible) root.look() }
    }
    Timer {
        interval: 1000 * (60 - root.now.getSeconds())
        running: root.visible
        onTriggered: root.now = new Date()
    }

    /// Where a page lives, for the end of its row
    function short(address) { return address.replace(/^[a-z]+:\/\/(www\.)?/, "").replace(/[\/?#].*$/, "") }

    // A letter typed on the start page is the first letter of an address
    Keys.onPressed: event => {
        if (root.adding || event.text === "" || event.text.charCodeAt(0) < 32 || (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) return
        event.accepted = true
        root.ask(event.text)
    }

    Flickable {
        id: flick
        anchors.fill: parent
        anchors.margins: Theme.lineHair
        contentHeight: column.y + column.implicitHeight + Theme.space6
        clip: contentHeight > height

        Column {
            id: column
            x: (flick.width - width) / 2
            // A little above the middle while there is room
            y: Math.max(Theme.space6, (flick.height - implicitHeight) * 0.36)
            width: Math.min(flick.width - 2 * Theme.space5, 4 * root.tile + 3 * Theme.space2)
            spacing: Theme.space6

            // ------------------------------------------------------------ the hour
            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.space1
                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    textStyle: "clock"
                    text: Qt.formatTime(root.now, "hh:mm")
                }
                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    textStyle: "motto"
                    color: Theme.textMuted
                    text: root.browser.secret ? "A private window: nothing of what is opened here is kept"
                        : root.now.toLocaleDateString(Qt.locale("en_GB"), "dddd, d MMMM")
                }
                // The way to a page: the address, which floats when it is asked for
                Item {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: way.width + 2 * Theme.space3
                    height: Theme.control + Theme.space4
                    Row {
                        id: way
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: Theme.space2
                        spacing: Theme.space2
                        KeyCaps { keys: "Ctrl T"; anchors.verticalCenter: parent.verticalCenter }
                        Label { textStyle: "caption"; color: wayArea.containsMouse ? Theme.text : Theme.textFaint; text: "or type, to search or go to an address"; anchors.verticalCenter: parent.verticalCenter }
                    }
                    MouseArea {
                        id: wayArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.ask("")
                    }
                }
            }

            Label {
                visible: !root.browser.connected && root.browser.begun
                anchors.horizontalCenter: parent.horizontalCenter
                textStyle: "caption"
                color: Theme.warning
                text: "The back end of the browser does not answer: nothing is kept and nothing is blocked."
            }

            // ------------------------------------------------------------ the essentials
            Column {
                width: parent.width
                spacing: Theme.space2

                Rule { width: parent.width }
                Label { anchors.horizontalCenter: parent.horizontalCenter; textStyle: "aside"; color: Theme.textMuted; text: "Essentials" }
                Flow {
                    // As wide as its rows, so they stand around the middle
                    readonly property int inRow: Math.min(root.perRow, root.browser.essentials.count + 1)
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: inRow * root.tile + (inRow - 1) * Theme.space2
                    spacing: Theme.space2

                    Repeater {
                        model: root.browser.essentials
                        Essential {
                            required property string url
                            required title
                            required icon
                            required property int index
                            large: true
                            width: root.tile
                            place: index
                            inRow: root.perRow
                            gap: Theme.space2
                            count: root.browser.essentials.count
                            onArranged: to => root.browser.arrange(url, to)
                            address: url
                            onClicked: root.essential(url)
                            onDropped: root.browser.pin(url, title)
                        }
                    }
                    // One more
                    Rectangle {
                        width: root.tile
                        height: 96
                        radius: Theme.radiusMd
                        color: Theme.alpha(Theme.text, more.containsMouse || root.adding ? 0.07 : 0)
                        border.width: Theme.lineHair
                        border.color: Theme.glassEdge
                        Behavior on color { ColorAnimation { duration: Theme.durFast } }
                        Icon { anchors.centerIn: parent; name: "plus"; hovered: more.containsMouse }
                        MouseArea {
                            id: more
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.adding = !root.adding
                                if (root.adding) fresh.field.forceActiveFocus()
                                else root.forceActiveFocus()
                            }
                        }
                    }
                }
                TextField {
                    id: fresh
                    visible: root.adding
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(parent.width, 2 * root.tile + Theme.space2)
                    iconName: "pin"
                    placeholderText: "Address of the page to keep here"
                    KeyCaps { keys: "Enter" }
                    function done() {
                        text = ""
                        root.adding = false
                        root.forceActiveFocus()
                    }
                    onAccepted: {
                        if (text.trim() !== "") root.browser.pin(root.browser.address(text), "")
                        done()
                    }
                    Keys.onEscapePressed: done()
                }
                Label {
                    visible: root.browser.essentials.count === 0 && !root.adding
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    textStyle: "caption"
                    color: Theme.textFaint
                    text: "Pages you open every day. The pin beside the address keeps the page that is shown; the right button lets go of one."
                }
            }

            // ------------------------------------------------- bookmarks and the history
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.space5
                visible: root.lists.length > 0

                Repeater {
                    model: root.lists
                    Column {
                        id: list
                        required property var modelData
                        // Two lists share the width; one alone stands in the middle
                        width: root.lists.length > 1 ? (column.width - Theme.space5) / 2 : Math.min(column.width, 2 * root.tile + 2 * Theme.space5)
                        spacing: Theme.lineBold

                        Label { anchors.horizontalCenter: parent.horizontalCenter; textStyle: "aside"; color: Theme.textMuted; text: list.modelData.name; bottomPadding: Theme.space2 }
                        Repeater {
                            model: list.modelData.pages
                            PageRow {
                                required property var modelData
                                width: list.width
                                title: modelData.title || modelData.url
                                icon: modelData.icon || ""
                                detail: root.short(modelData.url)
                                onClicked: root.open(modelData.url)
                            }
                        }
                    }
                }
            }
        }
    }
}
