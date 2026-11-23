// The settings of the browser, where the page stands: where a search goes, the filter, what comes
// back at the next start, when a tab in the background lets go of its page, the size of pages,
// the history. The back end keeps them (store.rs); this page only shows them and says what was
// chosen.
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
        }
    }
}
