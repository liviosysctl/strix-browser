// The settings of the browser, where the page stands: where a search goes, the filter, the
// passwords, what comes back at the next start, when a tab in the background lets go of its
// page, the size of pages, the graphics card, the history. The back end keeps them (store.rs); this page only shows them and says what was
// chosen. Under them the keys of the browser, to read.
import QtQuick
import Strix

Item {
    id: root

    property var settings
    property var filter

    /// One or more settings were chosen: { name: value }
    signal change(var values)
    /// Fetch the filter lists again
    signal lists()
    /// Empty the history
    signal forget()
    /// Empty the cache of pages
    signal emptyCache()

    readonly property var engines: [
        { name: "DuckDuckGo", address: "https://duckduckgo.com/?q=%s" },
        { name: "Startpage", address: "https://www.startpage.com/sp/search?query=%s" },
        { name: "Brave", address: "https://search.brave.com/search?q=%s" },
        { name: "Google", address: "https://www.google.com/search?q=%s" }
    ]
    /// The keys (BrowserWindow.qml), in the groups they are shown in
    readonly property var keys: [
        { name: "Tabs", rows: [["A page in a new tab", "Ctrl T"], ["Close what is shown", "Ctrl W"], ["Bring the last closed tab back", "Ctrl Shift T"],
            ["Next and previous tab", "Ctrl Tab"], ["A tab by its place", "Ctrl 1…9"], ["Carry the tab up or down", "Ctrl Shift PgUp"],
            ["An essential by its place", "Alt 1…9"]] },
        { name: "Pages", rows: [["Change the address", "Ctrl L"], ["Back and forward", "Alt ← →"], ["Load again", "Ctrl R"], ["Find in the page", "Ctrl F"],
            ["Larger, smaller, as set", "Ctrl + − 0"], ["Source of the page", "Ctrl U"], ["Developer tools", "F12"]] },
        { name: "Keeping", rows: [["Keep as a bookmark", "Ctrl D"], ["Keep as an essential", "Ctrl Shift D"], ["Start page", "Alt Home"]] },
        { name: "Windows", rows: [["New window", "Ctrl N"], ["Private window", "Ctrl Shift N"], ["The strip away and back", "Ctrl Alt C"],
            ["Settings", "Ctrl ,"], ["Leave the browser", "Ctrl Q"]] }
    ]
    readonly property var rests: [5, 15, 60, 0]
    readonly property var sizes: [0.9, 1, 1.1, 1.25]

    Flickable {
        anchors.fill: parent
        contentHeight: rows.implicitHeight + 2 * Theme.space5
        clip: true

        Column {
            id: rows
            x: Theme.space5
            y: Theme.space5
            width: Math.min(parent.width - 2 * Theme.space5, 720)

            Label { textStyle: "title"; color: Theme.text; text: "Settings"; bottomPadding: Theme.space3 }

            SettingRow {
                width: parent.width
                title: "Search"
                text: "Where the words typed into the address go"
                Segmented {
                    id: engine
                    model: root.engines.map(e => e.name)
                    onActivated: index => root.change({ search: root.engines[index].address })
                    Binding { target: engine; property: "currentIndex"; value: root.engines.findIndex(e => e.address === root.settings.search) }
                }
            }
            SettingRow {
                width: parent.width
                title: "Block ads and trackers"
                text: root.filter.rules > 0
                    ? root.filter.rules.toLocaleString(Qt.locale("en_US"), "f", 0) + " rules from the lists of uBlock Origin, " + root.filter.blocked + " requests blocked since the start"
                    : "The lists of uBlock Origin are not there yet"
                Switch { checked: root.settings.blocker; onToggled: root.change({ blocker: checked }) }
            }
            SettingRow {
                width: parent.width
                title: "Filter lists"
                text: root.filter.fetched > 0
                    ? "Fetched " + Qt.formatDateTime(new Date(root.filter.fetched * 1000), "d MMM yyyy, HH:mm") + "; every four days by themselves"
                    : "Fetched at the first start"
                Button { variant: "quiet"; text: "Fetch now"; loading: root.filter.fetching; onClicked: root.lists() }
            }
            SettingRow {
                width: parent.width
                title: "Passwords"
                text: "Offer to keep a password that was typed into a page, and fill it in the next time. They are kept in the keyring of the session, which opens with the login"
                Switch { checked: root.settings.passwords; onToggled: root.change({ passwords: checked }) }
            }
            SettingRow {
                width: parent.width
                title: "Tabs of the last session"
                text: "Open them again when the browser starts"
                Switch { checked: root.settings.restore; onToggled: root.change({ restore: checked }) }
            }
            SettingRow {
                width: parent.width
                title: "Tabs in the background"
                text: "Let go of a page that has not been looked at for this long; it loads again when its tab is chosen"
                Segmented {
                    id: rest
                    model: ["5 min", "15 min", "1 h", "Never"]
                    onActivated: index => root.change({ discard: root.rests[index] })
                    Binding { target: rest; property: "currentIndex"; value: root.rests.indexOf(root.settings.discard) }
                }
            }
            SettingRow {
                width: parent.width
                title: "Size of pages"
                text: "Ctrl + and Ctrl - change it for one tab, Ctrl 0 goes back to this"
                Segmented {
                    id: size
                    model: ["90 %", "100 %", "110 %", "125 %"]
                    onActivated: index => root.change({ zoom: root.sizes[index] })
                    Binding { target: size; property: "currentIndex"; value: root.sizes.indexOf(root.settings.zoom) }
                }
            }
            SettingRow {
                width: parent.width
                title: "Graphics card"
                text: "Draw pages and play video with the graphics card. From the next start of the browser; chrome://gpu shows what is in use"
                Switch { checked: root.settings.gpu; onToggled: root.change({ gpu: checked }) }
            }
            SettingRow {
                width: parent.width
                title: "History"
                text: "Remember the pages that were opened; the address offers them while typing"
                Switch { checked: root.settings.history; onToggled: root.change({ history: checked }) }
            }
            SettingRow {
                width: parent.width
                last: true
                title: "Forget"
                text: "The history of pages, or the copies of pages the browser keeps to load them faster"
                Row {
                    spacing: Theme.space2
                    Button { variant: "quiet"; text: "Clear history"; onClicked: root.forget() }
                    Button { variant: "quiet"; text: "Clear cache"; onClicked: root.emptyCache() }
                }
            }

            Label { textStyle: "title"; color: Theme.text; text: "Keys"; topPadding: Theme.space6; bottomPadding: Theme.space3 }
            Flow {
                width: parent.width
                spacing: Theme.space5
                Repeater {
                    model: root.keys
                    Column {
                        id: group
                        required property var modelData
                        width: (rows.width - Theme.space5) / 2
                        spacing: Theme.space1
                        Label { textStyle: "aside"; color: Theme.textMuted; text: group.modelData.name; bottomPadding: Theme.space1 }
                        Repeater {
                            model: group.modelData.rows
                            Item {
                                required property var modelData
                                width: group.width
                                height: Theme.control
                                Label { anchors.verticalCenter: parent.verticalCenter; text: modelData[0]; color: Theme.textMuted }
                                KeyCaps { anchors { right: parent.right; verticalCenter: parent.verticalCenter } keys: modelData[1] }
                            }
                        }
                    }
                }
            }
        }
    }
}
