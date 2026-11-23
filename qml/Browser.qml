// One window: the tabs down the left side, the address over the page. The same plate, measures
// and rows as the search of the shell, which grows into this window.
//
// Ctrl T a new tab, Ctrl W closes it, Ctrl Tab and Ctrl Shift Tab go through them, Ctrl L the
// address, Ctrl R again, Alt Left and Alt Right back and forward.
//
// A tab that has not been looked at for five minutes and plays nothing is discarded: Chromium
// lets go of its page and loads it again when the tab is chosen. That is where the memory goes
// in a browser, not into what is drawn around the pages.
import QtQuick
import QtWebEngine
import Quickshell
import Quickshell.Io
import Strix

Scope {
    id: root

    /// The tab that is shown
    property int at: 0
    readonly property var view: pages.count > 0 ? pages.itemAt(root.at) : null

    /// What is typed into the address: an address as it is, a host with https, anything else a search
    function address(text) {
        text = text.trim()
        if (/^[a-z][a-z0-9+.-]*:/i.test(text)) return text
        if (/^(localhost|[^\s/]+\.[^\s/]+)(:\d+)?(\/\S*)?$/i.test(text)) return "https://" + text
        return "https://duckduckgo.com/?q=" + encodeURIComponent(text)
    }

    function open(text) {
        tabs.append({ title: "", address: text ? root.address(text) : "" })
        root.at = tabs.count - 1
        if (!text) field.field.forceActiveFocus()
    }

    function close(index) {
        if (tabs.count === 1) {
            Qt.quit()
            return
        }
        tabs.remove(index)
        if (root.at > index || root.at >= tabs.count) root.at -= 1
    }

    function turn(step) { root.at = (root.at + step + tabs.count) % tabs.count }

    ListModel { id: tabs }
    Component.onCompleted: {
        const blocker = Quickshell.env("STRIX_BROWSER_BLOCKER")
        if (blocker) root.profile.extensionManager.loadExtension(blocker)
        root.open(Quickshell.env("STRIX_BROWSER_OPEN") || "")
    }

    IpcHandler {
        target: "browser"
        function open(address: string): void { root.open(address) }
        function tabs(): int { return tabs.count }
        function current(): string { return root.view ? root.view.url.toString() : "" }
    }

    // What every tab shares: the cookies and the cache stay between sessions, and the one
    // extension there is, the ad blocker, is loaded and switched on (Qt loads extensions off)
    WebEngineProfilePrototype {
        id: prototype
        storageName: "strix"
    }
    readonly property WebEngineProfile profile: prototype.instance()
    Connections {
        target: root.profile
        function onDownloadRequested(download) { download.accept() }
    }
    Connections {
        target: root.profile ? root.profile.extensionManager : null
        ignoreUnknownSignals: true
        function onLoadFinished(extension) { root.profile.extensionManager.setExtensionEnabled(extension, true) }
    }

    FloatingWindow {
        id: window
        title: root.view && root.view.title ? root.view.title : "Browser"
        implicitWidth: 1280
        implicitHeight: 800
        // Smoked glass: the compositor blurs what lies behind the window
        color: Theme.smoke(Theme.surface)
        onVisibleChanged: if (!visible) Qt.quit()

        readonly property int side: 220

        // ------------------------------------------------------------ the tabs
        Item {
            id: strip
            x: Theme.space2
            y: Theme.space2
            width: window.side
            height: parent.height - 2 * Theme.space2

            ListView {
                id: list
                width: parent.width
                height: Math.min(contentHeight, parent.height - Theme.control - Theme.space1)
                clip: true
                spacing: Theme.space1
                model: tabs
                currentIndex: root.at
                highlight: Glide {}
                highlightFollowsCurrentItem: true
                highlightMoveDuration: Theme.durBase
                highlightMoveVelocity: -1
                highlightResizeDuration: 0
                delegate: ListRow {
                    id: tab
                    required property int index
                    required property string title
                    required property string address
                    width: list.width
                    text: title || address || "New tab"
                    selected: index === root.at
                    glide: true
                    onClicked: root.at = index
                    // The middle button closes a tab, as the cross under the pointer does
                    TapHandler {
                        acceptedButtons: Qt.MiddleButton
                        onTapped: root.close(tab.index)
                    }
                    IconButton {
                        visible: tab.hovered
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        iconName: "x"
                        onClicked: root.close(tab.index)
                    }
                }
            }
            ListRow {
                y: list.height + Theme.space1
                width: parent.width
                iconName: "plus"
                text: "New tab"
                onClicked: root.open("")
            }
        }

        // ------------------------------------------------------------ the address
        Row {
            id: top
            x: strip.x + strip.width + Theme.space2
            y: Theme.space2
            width: parent.width - x - Theme.space2
            spacing: Theme.space2

            Row {
                id: steps
                spacing: Theme.space1
                IconButton { iconName: "chevron-left"; enabled: !!root.view && root.view.canGoBack; onClicked: root.view.goBack() }
                IconButton { iconName: "chevron-right"; enabled: !!root.view && root.view.canGoForward; onClicked: root.view.goForward() }
                IconButton {
                    iconName: root.view && root.view.loading ? "x" : "rotate-cw"
                    onClicked: root.view.loading ? root.view.stop() : root.view.reload()
                }
            }
            SearchField {
                id: field
                width: parent.width - x
                placeholderText: "Search or type an address"
                onAccepted: {
                    if (!root.view || text.trim() === "") return
                    root.view.url = root.address(text)
                    root.view.forceActiveFocus()
                }
                // It shows where the tab is, unless something is being typed
                Binding {
                    target: field
                    property: "text"
                    value: root.view ? root.view.url.toString() : ""
                    when: !field.field.activeFocus
                }
            }
        }

        // ------------------------------------------------------------ the pages
        Rectangle {
            x: top.x
            y: top.y + Theme.control + Theme.space2
            width: top.width
            height: parent.height - y - Theme.space2
            radius: Theme.radiusMd
            // A well in the glass of the window
            color: Theme.alpha(Theme.text, 0.04)
            clip: true

            Repeater {
                id: pages
                model: tabs

                WebEngineView {
                    id: page
                    required property int index
                    required property string address

                    anchors.fill: parent
                    visible: index === root.at
                    profile: root.profile
                    backgroundColor: "transparent"
                    Component.onCompleted: if (address !== "") url = address
                    onTitleChanged: tabs.setProperty(index, "title", title)
                    onUrlChanged: tabs.setProperty(index, "address", url.toString())
                    // What a page opens goes into a tab beside it
                    onNewWindowRequested: request => {
                        root.open("")
                        request.openIn(pages.itemAt(tabs.count - 1))
                    }
                    onVisibleChanged: if (visible) lifecycleState = WebEngineView.LifecycleState.Active
                    Timer {
                        interval: 5 * 60 * 1000
                        running: !page.visible && !page.recentlyAudible && page.lifecycleState !== WebEngineView.LifecycleState.Discarded
                        onTriggered: page.lifecycleState = WebEngineView.LifecycleState.Discarded
                    }
                }
            }

            // How far the page has come
            Rectangle {
                visible: !!root.view && root.view.loading
                width: parent.width * (root.view ? root.view.loadProgress / 100 : 0)
                height: 2 * Theme.lineHair
                color: Theme.accent
                Behavior on width { NumberAnimation { duration: Theme.durFast } }
            }
        }

        Shortcut { sequence: "Ctrl+T"; onActivated: root.open("") }
        Shortcut { sequence: "Ctrl+W"; onActivated: root.close(root.at) }
        Shortcut { sequence: "Ctrl+Tab"; onActivated: root.turn(1) }
        Shortcut { sequence: "Ctrl+Shift+Tab"; onActivated: root.turn(-1) }
        Shortcut { sequence: "Ctrl+R"; onActivated: if (root.view) root.view.reload() }
        Shortcut { sequence: "Alt+Left"; onActivated: if (root.view) root.view.goBack() }
        Shortcut { sequence: "Alt+Right"; onActivated: if (root.view) root.view.goForward() }
        Shortcut {
            sequence: "Ctrl+L"
            onActivated: {
                field.field.forceActiveFocus()
                field.field.selectAll()
            }
        }
    }
}
