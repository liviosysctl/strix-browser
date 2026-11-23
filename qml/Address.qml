// The address: one field that floats over the page, as the search of the shell floats over the
// desktop. Ctrl T asks for a page in a new tab, Ctrl L for one in the tab that is shown; on the
// start page it stands in its place among the rest. Under it the bookmarks and the history that
// match what is typed; with nothing typed, the bookmarks.
import QtQuick
import Strix

Item {
    id: root

    required property var browser
    /// What Enter does, at the right of the field: "New tab" or "Go"
    property string doing: "Go"
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
        field.field.forceActiveFocus()
        field.field.selectAll()
        root.suggest()
    }

    function suggest() {
        root.pick = -1
        if (!root.visible || !root.browser.connected) {
            root.hits = []
            return
        }
        // An address that is only shown, all of it chosen, is not something typed
        const typed = field.field.selectedText === field.text ? "" : field.text.trim()
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
    onVisibleChanged: if (!visible) root.hits = []

    Bar {
        id: plate
        width: parent.width
        height: column.implicitHeight + 2 * Theme.space2

        Column {
            id: column
            x: Theme.space2
            y: Theme.space2
            width: parent.width - 2 * Theme.space2
            spacing: Theme.space1

            SearchField {
                id: field
                width: parent.width
                placeholderText: "Search or type an address"
                Label { textStyle: "micro"; color: Theme.textMuted; text: root.doing; anchors.verticalCenter: parent.verticalCenter }
                KeyCaps { keys: "Enter"; anchors.verticalCenter: parent.verticalCenter }
                onAccepted: root.go(root.pick >= 0 && root.hits[root.pick] ? root.hits[root.pick].url : text)
                onTextChanged: root.suggest()
                Keys.onDownPressed: root.pick = Math.min(root.pick + 1, root.hits.length - 1)
                Keys.onUpPressed: root.pick = Math.max(root.pick - 1, -1)
                Keys.onEscapePressed: root.away()
            }
            Repeater {
                model: root.hits
                PageRow {
                    required property var modelData
                    required property int index
                    width: column.width
                    title: modelData.title || modelData.url
                    icon: modelData.icon || ""
                    detail: modelData.url.replace(/^[a-z]+:\/\/(www\.)?/, "").replace(/\/$/, "")
                    selected: index === root.pick
                    onClicked: root.go(modelData.url)
                }
            }
        }
    }
}
