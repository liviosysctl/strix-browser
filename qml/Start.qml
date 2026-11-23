// The start page: what stands in the window while no page does. The hour, the address, the
// essentials as large buttons, the bookmarks and what was opened lately. It is glass like the
// rest of the window, so the picture of the desktop shows through. The address is the one field
// of the window (Address.qml): this page only leaves its place free, `field`.
import QtQuick
import Strix

Item {
    id: root

    required property var browser
    /// A page was chosen: its address
    signal open(string address)
    /// An essential was chosen
    signal essential(string address)

    property var marks: []
    property var lately: []
    /// The field that takes the address of a new essential is out
    property bool adding: false
    property date now: new Date()
    /// Where the address stands, in this page
    readonly property rect field: Qt.rect(column.x, column.y + slot.y - flick.contentY, column.width, slot.height)
    property int fieldHeight: Theme.control + 2 * Theme.space2

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

    Flickable {
        id: flick
        anchors.fill: parent
        anchors.margins: Theme.lineHair
        contentHeight: column.implicitHeight + 2 * Theme.space7
        clip: contentHeight > height

        Column {
            id: column
            x: Math.max(Theme.space5, (parent.width - width) / 2)
            y: Theme.space7
            width: Math.min(root.width - 2 * Theme.space5, 640)
            spacing: Theme.space5

            Column {
                width: parent.width
                Label {
                    textStyle: "clock"
                    text: Qt.formatTime(root.now, "hh:mm")
                    Entrance {}
                }
                Label {
                    textStyle: "motto"
                    color: Theme.textMuted
                    text: root.browser.secret ? "A private window: nothing of what is opened here is kept"
                        : root.now.toLocaleDateString(Qt.locale("en_GB"), "dddd, d MMMM")
                    Entrance { delay: Theme.stagger }
                }
            }

            Item {
                id: slot
                width: parent.width
                height: root.fieldHeight
            }
            Label {
                visible: !root.browser.connected && root.browser.begun
                textStyle: "caption"
                color: Theme.warning
                text: "The back end of the browser does not answer: nothing is kept and nothing is blocked."
            }

            // ------------------------------------------------------------ the essentials
            Column {
                width: parent.width
                spacing: Theme.space2

                Label { textStyle: "aside"; color: Theme.textMuted; text: "Essentials" }
                Flow {
                    width: parent.width
                    spacing: Theme.space2

                    Repeater {
                        model: root.browser.essentials
                        Essential {
                            required property string url
                            required title
                            required icon
                            large: true
                            width: (column.width - 3 * Theme.space2) / 4
                            address: url
                            onClicked: root.essential(url)
                            onDropped: root.browser.pin(url, title)
                        }
                    }
                    // One more
                    Rectangle {
                        width: (column.width - 3 * Theme.space2) / 4
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
                            }
                        }
                    }
                }
                TextField {
                    id: fresh
                    visible: root.adding
                    width: parent.width / 2
                    iconName: "pin"
                    placeholderText: "Address of the page to keep here"
                    KeyCaps { keys: "Enter" }
                    onAccepted: {
                        if (text.trim() !== "") root.browser.pin(root.browser.address(text), "")
                        text = ""
                        root.adding = false
                    }
                    Keys.onEscapePressed: root.adding = false
                }
                Label {
                    visible: root.browser.essentials.count === 0 && !root.adding
                    textStyle: "caption"
                    color: Theme.textFaint
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "Pages you open every day. The pin beside the address keeps the page that is shown; the right button lets go of one."
                }
            }

            // ------------------------------------------------- bookmarks and the history
            Row {
                width: parent.width
                spacing: Theme.space5
                visible: root.marks.length > 0 || root.lately.length > 0

                Repeater {
                    model: [{ name: "Bookmarks", pages: root.marks }, { name: "Opened lately", pages: root.lately }]
                    Column {
                        id: half
                        required property var modelData
                        width: (parent.width - parent.spacing) / 2
                        spacing: Theme.space1
                        visible: modelData.pages.length > 0

                        Label { textStyle: "aside"; color: Theme.textMuted; text: half.modelData.name; bottomPadding: Theme.space1 }
                        Repeater {
                            model: half.modelData.pages
                            PageRow {
                                required property var modelData
                                width: half.width
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
