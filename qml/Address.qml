// The address: one plate that floats over the page while it is asked for, as the search of the
// shell floats over the desktop. Ctrl T asks for a page in a new tab, Ctrl L for one in the tab
// that is shown. What is typed stands large in its first row; under it the bookmarks and the
// history that match, with nothing typed the bookmarks; at its foot the keys.
import QtQuick
import QtQuick.Templates as T
import Strix

Item {
    id: root

    required property var browser
    /// What Enter does, at the foot: "Open in a new tab" or "Go there"
    property string doing: "Go there"
    property alias text: field.text
    property var hits: []
    property int pick: -1

    /// Enter: what was typed, or the address of the hit that was chosen
    signal go(string address)
    /// Esc
    signal away()

    implicitHeight: plate.height

    /// Takes the keys, with `text` in the field and all of it chosen
    function take(text) {
        field.text = text
        field.forceActiveFocus()
        field.selectAll()
        root.suggest()
    }
    /// Takes the keys with the first letters already typed
    function begin(text) {
        field.text = text
        field.forceActiveFocus()
        field.cursorPosition = text.length
    }

    function suggest() {
        root.pick = -1
        if (!root.visible || !root.browser.connected) {
            root.hits = []
            return
        }
        // An address that is only shown, all of it chosen, is not something typed
        const typed = field.selectedText === field.text ? "" : field.text.trim()
        root.browser.call("bookmarks", { text: typed, limit: typed === "" ? 6 : 3 }, marks => {
            const first = marks || []
            if (typed === "" || root.browser.secret) {
                root.hits = root.visible ? first : []
                return
            }
            root.browser.call("history", { text: typed, limit: 6 }, pages => {
                const rest = (pages || []).filter(page => !first.some(mark => mark.url === page.url))
                root.hits = root.visible ? first.concat(rest).slice(0, 7) : []
            })
        })
    }
    onVisibleChanged: {
        if (!visible) root.hits = []
        else arrive.restart()
    }

    // It comes forward a little as it appears
    transformOrigin: Item.Top
    ParallelAnimation {
        id: arrive
        NumberAnimation { target: root; property: "opacity"; from: 0; to: 1; duration: Theme.durFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
        NumberAnimation { target: root; property: "scale"; from: 0.98; to: 1; duration: Theme.durFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
    }

    Bar {
        id: plate
        width: parent.width
        height: column.implicitHeight

        Column {
            id: column
            width: parent.width

            // ------------------------------------------------------------ what is typed
            Item {
                width: parent.width
                height: Theme.control + Theme.space5

                Icon {
                    id: glass
                    x: Theme.space4
                    anchors.verticalCenter: parent.verticalCenter
                    name: "search"
                    size: Theme.icon + Theme.lineBold
                    color: field.length > 0 ? Theme.text : Theme.textMuted
                }
                T.TextField {
                    id: field
                    x: glass.x + glass.width + Theme.space3
                    width: parent.width - x - Theme.space4
                    height: parent.height
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.text
                    placeholderTextColor: Theme.textFaint
                    selectionColor: Theme.accentSoft
                    selectedTextColor: Theme.text
                    font.family: Theme.sans
                    font.pixelSize: Theme.styles.heading.pixelSize + Theme.lineBold
                    padding: 0
                    placeholderText: "Search or type an address"
                    cursorDelegate: Rectangle { width: Theme.lineBold; color: Theme.accent; visible: field.cursorVisible }
                    onAccepted: root.go(root.pick >= 0 && root.hits[root.pick] ? root.hits[root.pick].url : text)
                    onTextChanged: root.suggest()
                    Keys.onDownPressed: root.pick = Math.min(root.pick + 1, root.hits.length - 1)
                    Keys.onUpPressed: root.pick = Math.max(root.pick - 1, -1)
                    Keys.onEscapePressed: root.away()
                    background: Label {
                        visible: field.length === 0 && !field.preeditText
                        height: field.height
                        text: field.placeholderText
                        font.pixelSize: field.font.pixelSize
                        color: Theme.textFaint
                        elide: Text.ElideRight
                    }
                }
            }

            // ------------------------------------------------------------ what matches
            Rectangle {
                visible: root.hits.length > 0
                x: Theme.space2
                width: parent.width - 2 * Theme.space2
                height: Theme.lineHair
                color: Theme.glassEdge
            }
            Column {
                visible: root.hits.length > 0
                x: Theme.space2
                width: parent.width - 2 * Theme.space2
                topPadding: Theme.space2
                bottomPadding: Theme.space1
                spacing: Theme.lineBold
                Repeater {
                    model: root.hits
                    PageRow {
                        required property var modelData
                        required property int index
                        width: parent.width
                        title: modelData.title || modelData.url
                        icon: modelData.icon || ""
                        detail: modelData.url.replace(/^[a-z]+:\/\/(www\.)?/, "").replace(/\/$/, "")
                        selected: index === root.pick
                        onClicked: root.go(modelData.url)
                    }
                }
            }

            // ------------------------------------------------------------ the keys
            Rectangle {
                x: Theme.space2
                width: parent.width - 2 * Theme.space2
                height: Theme.lineHair
                color: Theme.glassEdge
            }
            Item {
                width: parent.width
                height: Theme.control + Theme.space1

                Row {
                    x: Theme.space4
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.space2
                    KeyCaps { keys: "Enter"; anchors.verticalCenter: parent.verticalCenter }
                    Label { textStyle: "micro"; color: Theme.textMuted; text: root.doing; anchors.verticalCenter: parent.verticalCenter }
                }
                Row {
                    anchors { right: parent.right; rightMargin: Theme.space4; verticalCenter: parent.verticalCenter }
                    spacing: Theme.space2
                    KeyCaps { visible: root.hits.length > 0; keys: "↑ ↓"; anchors.verticalCenter: parent.verticalCenter }
                    Label { visible: root.hits.length > 0; textStyle: "micro"; color: Theme.textMuted; text: "Choose"; rightPadding: Theme.space2; anchors.verticalCenter: parent.verticalCenter }
                    KeyCaps { keys: "Esc"; anchors.verticalCenter: parent.verticalCenter }
                    Label { textStyle: "micro"; color: Theme.textMuted; text: "Close"; anchors.verticalCenter: parent.verticalCenter }
                }
            }
        }
    }
}
