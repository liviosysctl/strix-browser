// One window: the tabs down the left side, the address over the page. The same plate, measures
// and rows as the search of the shell, which grows into this window.
//
// The back end (backend/, Rust) keeps the settings, the history and the tabs of the last session,
// and decides about every request a page makes with the filter lists of uBlock Origin; this file
// talks to it over the line every Strix front end has (Backend, service "browser").
//
// Ctrl T a new tab, Ctrl W closes it, Ctrl Shift T brings the last closed one back, Ctrl Tab and
// Ctrl Shift Tab go through them. Ctrl L the address, Ctrl R again, Alt Left and Alt Right back
// and forward, Ctrl F finds in the page, Ctrl + - 0 the size, Ctrl , the settings, F12 the
// developer tools.
//
// A tab in the background lets go of its page after a while (Settings): Chromium discards it and
// loads it again when the tab is chosen. That is where the memory goes in a browser, not into
// what is drawn around the pages.
import QtQuick
import QtWebEngine
import Quickshell
import Quickshell.Io
import Strix
import Strix.Shell

Scope {
    id: root

    /// The window is on the screen. The search of the shell starts the browser without it
    /// (STRIX_BROWSER_HIDDEN), so the page loads while the search grows into the window's
    /// place, and shows it when it has arrived (ipc: browser reveal)
    property bool shown: !Quickshell.env("STRIX_BROWSER_HIDDEN")

    /// The tab that is shown
    property int at: 0
    readonly property var view: pages.count > 0 ? pages.itemAt(root.at) : null

    /// What the back end keeps (store.rs): the settings, and how the filter stands
    property var settings: ({ search: "https://duckduckgo.com/?q=%s", home: "", blocker: true, restore: true, discard: 5, downloads: "", zoom: 1, history: true })
    property var filter: ({ enabled: true, rules: 0, blocked: 0, fetched: 0, fetching: false })
    /// The settings stand where the page does
    property bool options: false
    /// A page fills the window (a video): tabs and address step aside
    property bool full: false
    /// The addresses of the tabs that were closed, the last one last
    property var closed: []
    /// What is being downloaded and what was, newest first
    property var downloads: []
    /// A page asks for the camera, the place, notifications…: the request, until it is answered
    property var asking: null
    /// The history that matches what is typed into the address, and the one chosen with the arrows
    property var hits: []
    property int pick: -1
    property bool finding: false

    /// What is typed into the address: an address as it is, a file by its path, a host with
    /// https, anything else a search
    function address(text) {
        text = text.trim()
        if (text.startsWith("/")) return "file://" + text
        if (/^[a-z][a-z0-9+.-]*:/i.test(text)) return text
        if (/^(localhost|[^\s/]+\.[^\s/]+)(:\d+)?(\/\S*)?$/i.test(text)) return "https://" + text
        return root.settings.search.replace("%s", encodeURIComponent(text))
    }

    function open(text) {
        tabs.append({ title: "", address: text ? root.address(text) : root.settings.home, fresh: true })
        root.at = tabs.count - 1
        root.options = false
        if (!text && !root.settings.home) field.field.forceActiveFocus()
    }

    function close(index) {
        const gone = tabs.get(index).address
        if (gone) root.closed = root.closed.concat([gone])
        if (tabs.count === 1) {
            root.keep()
            Qt.quit()
            return
        }
        tabs.remove(index)
        if (root.at > index || root.at >= tabs.count) root.at -= 1
    }

    function reopen() {
        if (root.closed.length === 0) return
        const last = root.closed[root.closed.length - 1]
        root.closed = root.closed.slice(0, -1)
        root.open(last)
    }

    function turn(step) {
        root.options = false
        root.at = (root.at + step + tabs.count) % tabs.count
    }

    /// Goes where the address says, in the tab that is shown
    function go(text) {
        if (!root.view || text.trim() === "") return
        root.hits = []
        root.options = false
        root.view.loaded = true
        root.view.url = root.address(text)
        root.view.forceActiveFocus()
    }

    function take(state) {
        if (!state) return
        root.settings = state.settings
        root.filter = state.filter
    }

    function set(values) { backend.call("set", values, state => root.take(state)) }

    /// The tabs as they stand, for the next start
    function keep() {
        if (!backend.connected || !root.begun) return
        const list = []
        for (let i = 0; i < tabs.count; i++) {
            const tab = tabs.get(i)
            if (tab.address) list.push({ url: tab.address, title: tab.title })
        }
        backend.call("keep", { tabs: list })
    }

    ListModel {
        id: tabs
        onCountChanged: later.restart()
    }
    Timer { id: later; interval: 800; onTriggered: root.keep() }

    // ---------------------------------------------------------------- the back end
    Backend {
        id: backend
        service: "browser"
        retry: 300
        onConnectedChanged: if (connected) backend.call("state", {}, state => {
            root.take(state)
            root.begin()
        })
        onFailed: (method, message) => console.warn("Browser: " + method + ": " + message)
    }

    /// The first tabs: the ones of the last session, unloaded until they are chosen, and the
    /// address the browser was started with
    property bool begun: false
    function begin() {
        if (root.begun) return
        root.begun = true
        // Cookies, the cache and what pages store stay between sessions
        WebEngine.defaultProfile.storageName = "strix"
        WebEngine.defaultProfile.offTheRecord = false
        if (root.settings.downloads) WebEngine.defaultProfile.downloadPath = root.settings.downloads
        const first = Quickshell.env("STRIX_BROWSER_OPEN") || ""
        const start = () => { if (first || tabs.count === 0) root.open(first); else root.at = tabs.count - 1 }
        if (!backend.connected) {
            start()
            return
        }
        backend.call("session", {}, list => {
            for (const tab of list || []) tabs.append({ title: tab.title || "", address: tab.url, fresh: false })
            start()
        })
    }
    // Without its back end the browser still opens: nothing is kept and nothing is blocked
    Timer { interval: 2500; running: !root.begun; onTriggered: root.begin() }

    Connections {
        target: WebEngine.defaultProfile
        function onDownloadRequested(download) {
            download.accept()
            root.downloads = [download].concat(root.downloads)
        }
    }

    IpcHandler {
        target: "browser"
        function open(address: string): void {
            root.open(address)
            root.shown = true
        }
        function reveal(): void { root.shown = true }
        function settings(): void {
            root.options = true
            root.shown = true
        }
        function tabs(): int { return tabs.count }
        function current(): string { return root.view ? root.view.url.toString() : "" }
        function title(): string { return root.view ? root.view.title : "" }
        function blocked(): int { return root.filter.blocked }
    }

    FloatingWindow {
        id: window
        title: root.options ? "Settings" : root.view && root.view.title ? root.view.title : "Browser"
        implicitWidth: 1280
        implicitHeight: 800
        // Smoked glass: the compositor blurs what lies behind the window
        color: Theme.smoke(Theme.surface)
        visible: root.shown
        // Closed by the person; hidden at the start it waits for its sign
        onVisibleChanged: if (!visible && root.shown) {
            root.keep()
            Qt.quit()
        }

        readonly property int side: 220
        /// Tabs and address take their place, or none while a page fills the window
        readonly property int edge: root.full ? 0 : Theme.space2

        // ------------------------------------------------------------ the tabs
        Item {
            id: strip
            visible: !root.full
            x: Theme.space2
            y: Theme.space2
            width: window.side
            height: parent.height - 2 * Theme.space2

            ListView {
                id: list
                width: parent.width
                height: Math.min(contentHeight, parent.height - below.height - Theme.control - 2 * Theme.space1)
                clip: true
                spacing: Theme.space1
                model: tabs
                currentIndex: root.options ? -1 : root.at
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
                    selected: !root.options && index === root.at
                    glide: true
                    onClicked: {
                        root.options = false
                        root.at = index
                    }
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

            // What is downloaded, and the way to the settings, at the foot of the strip
            Column {
                id: below
                anchors.bottom: parent.bottom
                width: parent.width
                spacing: Theme.space1

                Repeater {
                    model: root.downloads.slice(0, 3)
                    ListRow {
                        required property var modelData
                        width: below.width
                        iconName: "download"
                        text: modelData.downloadFileName
                        detail: modelData.state === WebEngineDownloadRequest.DownloadCompleted ? "done"
                            : modelData.state === WebEngineDownloadRequest.DownloadInProgress
                                ? (modelData.totalBytes > 0 ? Math.round(100 * modelData.receivedBytes / modelData.totalBytes) + "%" : "…")
                                : "stopped"
                        // Its folder, in the file manager
                        onClicked: Quickshell.execDetached(["xdg-open", modelData.downloadDirectory])
                    }
                }
                ListRow {
                    width: parent.width
                    iconName: "settings"
                    text: "Settings"
                    detail: root.filter.enabled && root.filter.blocked > 0 ? root.filter.blocked + " blocked" : ""
                    selected: root.options
                    onClicked: root.options = !root.options
                }
            }
        }

        // ------------------------------------------------------------ the address
        Row {
            id: top
            visible: !root.full
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
                onAccepted: root.go(root.pick >= 0 && root.hits[root.pick] ? root.hits[root.pick].url : text)
                // What was opened before and matches what is typed
                onTextChanged: {
                    root.pick = -1
                    if (!field.field.activeFocus || text.trim() === "" || !backend.connected) root.hits = []
                    else backend.call("history", { text: text, limit: 6 }, list => root.hits = field.field.activeFocus ? list || [] : [])
                }
                Keys.onDownPressed: root.pick = Math.min(root.pick + 1, root.hits.length - 1)
                Keys.onUpPressed: root.pick = Math.max(root.pick - 1, -1)
                Keys.onEscapePressed: if (root.view) root.view.forceActiveFocus()
                // It shows where the tab is, unless something is being typed
                Binding {
                    target: field
                    property: "text"
                    value: root.options ? "" : root.view ? root.view.url.toString() : ""
                    when: !field.field.activeFocus
                }
                Connections {
                    target: field.field
                    function onActiveFocusChanged() { if (!field.field.activeFocus) root.hits = [] }
                }
            }
        }

        // ------------------------------------------------------------ the pages
        Rectangle {
            id: well
            x: root.full ? 0 : top.x
            y: root.full ? 0 : top.y + Theme.control + Theme.space2
            width: root.full ? parent.width : top.width
            height: parent.height - y - window.edge
            radius: root.full ? 0 : Theme.radiusMd
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
                    required property bool fresh
                    /// A tab of the last session loads when it is first chosen
                    property bool loaded: false

                    anchors.fill: parent
                    visible: !root.options && index === root.at
                    // A page that names no colour of its own counts on white
                    backgroundColor: "white"
                    zoomFactor: root.settings.zoom

                    function load() {
                        if (page.loaded) return
                        page.loaded = true
                        if (page.address !== "") page.url = page.address
                    }
                    Component.onCompleted: if (fresh || visible) page.load()
                    onVisibleChanged: {
                        if (!visible) return
                        page.load()
                        lifecycleState = WebEngineView.LifecycleState.Active
                    }
                    onTitleChanged: if (title !== "") tabs.setProperty(index, "title", title)
                    onUrlChanged: {
                        if (url.toString() === "") return
                        tabs.setProperty(index, "address", url.toString())
                        later.restart()
                    }
                    onLoadingChanged: info => {
                        if (info.status !== WebEngineView.LoadSucceededStatus || !backend.connected) return
                        backend.call("visit", { url: url.toString(), title: title })
                        // How many requests the filter has blocked by now, for the strip
                        backend.call("state", {}, state => root.take(state))
                        // What the lists hide on this page
                        backend.call("cosmetic", { url: url.toString() }, hide => {
                            if (!hide || hide.length === 0) return
                            const rule = JSON.stringify(hide.join(",") + "{display:none!important}")
                            page.runJavaScript("(function(){const s=document.createElement('style');s.textContent=" + rule + ";document.documentElement.appendChild(s)})()")
                        })
                    }
                    // What a page opens goes into a tab beside it
                    onNewWindowRequested: request => {
                        root.open("")
                        const beside = pages.itemAt(tabs.count - 1)
                        beside.loaded = true
                        request.openIn(beside)
                    }
                    onFullScreenRequested: request => {
                        request.accept()
                        root.full = request.toggleOn
                    }
                    onPermissionRequested: permission => root.asking = permission
                    Timer {
                        interval: Math.max(1, root.settings.discard) * 60 * 1000
                        running: root.settings.discard > 0 && page.loaded && !page.visible && !page.recentlyAudible
                            && page.lifecycleState !== WebEngineView.LifecycleState.Discarded
                        onTriggered: page.lifecycleState = WebEngineView.LifecycleState.Discarded
                    }
                }
            }

            // How far the page has come
            Rectangle {
                visible: !root.options && !!root.view && root.view.loading
                width: parent.width * (root.view ? root.view.loadProgress / 100 : 0)
                height: 2 * Theme.lineHair
                color: Theme.accent
                Behavior on width { NumberAnimation { duration: Theme.durFast } }
            }

            Options {
                anchors.fill: parent
                visible: root.options
                settings: root.settings
                filter: root.filter
                onChange: values => root.set(values)
                onLists: backend.call("lists", {}, state => root.take(state))
                onForget: backend.call("forget", {})
                onEmptyCache: WebEngine.defaultProfile.clearHttpCache()
                // The figures of the filter move while the page is open
                Timer {
                    interval: 2000
                    repeat: true
                    running: root.options && backend.connected
                    onTriggered: backend.call("state", {}, state => root.take(state))
                }
            }

            // A page asks for something of the machine
            Surface {
                visible: root.asking !== null
                anchors { top: parent.top; horizontalCenter: parent.horizontalCenter; topMargin: Theme.space2 }
                width: Math.min(parent.width - 2 * Theme.space2, ask.implicitWidth + 2 * Theme.space3)
                height: Theme.control + 2 * Theme.space2
                elevation: "panel"
                Row {
                    id: ask
                    anchors.centerIn: parent
                    spacing: Theme.space2
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        textStyle: "label"
                        color: Theme.text
                        text: root.asking ? root.asking.origin.toString().replace(/\/$/, "") + " asks for " + root.wish(root.asking.permissionType) : ""
                    }
                    Button { text: "Allow"; onClicked: { root.asking.grant(); root.asking = null } }
                    Button { variant: "quiet"; text: "Deny"; onClicked: { root.asking.deny(); root.asking = null } }
                }
            }

            // Finding in the page
            Surface {
                visible: root.finding
                anchors { top: parent.top; right: parent.right; margins: Theme.space2 }
                width: 320
                height: Theme.control + 2 * Theme.space2
                elevation: "panel"
                SearchField {
                    id: finder
                    x: Theme.space2
                    y: Theme.space2
                    width: parent.width - 2 * Theme.space2
                    placeholderText: "Find in the page"
                    KeyCaps { keys: "Esc" }
                    onTextChanged: if (root.view) root.view.findText(text)
                    onAccepted: if (root.view) root.view.findText(text)
                    Keys.onEscapePressed: root.find(false)
                }
            }
        }

        // What was opened before, under the address
        Surface {
            visible: root.hits.length > 0
            x: top.x + field.x
            y: top.y + Theme.control + Theme.space1
            width: field.width
            height: found.implicitHeight + 2 * Theme.space2
            elevation: "panel"
            Column {
                id: found
                x: Theme.space2
                y: Theme.space2
                width: parent.width - 2 * Theme.space2
                Repeater {
                    model: root.hits
                    ListRow {
                        required property var modelData
                        required property int index
                        width: found.width
                        iconName: "history"
                        text: modelData.title || modelData.url
                        detail: modelData.url.replace(/^https?:\/\/(www\.)?/, "").slice(0, 40)
                        selected: index === root.pick
                        onClicked: root.go(modelData.url)
                    }
                }
            }
        }

        Shortcut { sequence: "Ctrl+T"; onActivated: root.open("") }
        Shortcut { sequence: "Ctrl+W"; onActivated: root.close(root.at) }
        Shortcut { sequence: "Ctrl+Shift+T"; onActivated: root.reopen() }
        Shortcut { sequence: "Ctrl+Tab"; onActivated: root.turn(1) }
        Shortcut { sequence: "Ctrl+Shift+Tab"; onActivated: root.turn(-1) }
        Shortcut { sequences: ["Ctrl+R", "F5"]; onActivated: if (root.view) root.view.reload() }
        Shortcut { sequence: "Alt+Left"; onActivated: if (root.view) root.view.goBack() }
        Shortcut { sequence: "Alt+Right"; onActivated: if (root.view) root.view.goForward() }
        Shortcut { sequence: "Ctrl+F"; onActivated: root.find(true) }
        Shortcut { sequence: "Ctrl+,"; onActivated: root.options = !root.options }
        Shortcut { sequences: ["Ctrl++", "Ctrl+="]; onActivated: root.size(0.1) }
        Shortcut { sequence: "Ctrl+-"; onActivated: root.size(-0.1) }
        Shortcut { sequence: "Ctrl+0"; onActivated: root.size(0) }
        Shortcut { sequence: "F12"; onActivated: root.inspect() }
        Shortcut {
            sequence: "Ctrl+L"
            onActivated: {
                field.field.forceActiveFocus()
                field.field.selectAll()
            }
        }
    }

    function find(on) {
        root.finding = on
        if (on) {
            finder.field.forceActiveFocus()
            finder.field.selectAll()
        } else if (root.view) {
            root.view.findText("")
            root.view.forceActiveFocus()
        }
    }

    /// Larger or smaller by a step, or back to the size of the settings
    function size(step) {
        if (!root.view) return
        root.view.zoomFactor = step === 0 ? root.settings.zoom : Math.max(0.3, Math.min(3, root.view.zoomFactor + step))
    }

    /// The developer tools of the page that is shown, in a tab beside it
    function inspect() {
        const inspected = root.view
        if (!inspected) return
        root.open("")
        const tools = pages.itemAt(tabs.count - 1)
        tools.loaded = true
        tools.inspectedView = inspected
    }

    /// What a page asks for, in words
    function wish(type) {
        const types = WebEnginePermission.PermissionType || {}
        if (type === types.Geolocation) return "where you are"
        if (type === types.MediaAudioCapture) return "the microphone"
        if (type === types.MediaVideoCapture) return "the camera"
        if (type === types.MediaAudioVideoCapture) return "the camera and the microphone"
        if (type === types.Notifications) return "notifications"
        if (type === types.DesktopVideoCapture || type === types.DesktopAudioVideoCapture) return "your screen"
        if (type === types.ClipboardReadWrite) return "the clipboard"
        return "more rights"
    }
}
