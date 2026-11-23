// The browser: what all its windows share. The back end (backend/, Rust) keeps the settings, the
// history, the bookmarks, the passwords and the tabs of the last session, and decides about
// every request a page makes with the filter lists of uBlock Origin; this file talks to it over
// the line every Strix front end has (Backend, service "browser"). A window is BrowserWindow.
//
// A private browser (STRIX_BROWSER_PRIVATE) is a process of its own whose pages leave nothing
// behind: no cookies and no cache on the disk, no history, no session. The filter still asks.
import QtQuick
import QtWebEngine
import Quickshell
import Quickshell.Io
import Strix
import Strix.Shell

Scope {
    id: root

    /// Nothing of what is opened here is kept
    readonly property bool secret: !!Quickshell.env("STRIX_BROWSER_PRIVATE")
    /// The windows are on the screen. The search of the shell starts the browser without them
    /// (STRIX_BROWSER_HIDDEN), so the page loads while the search grows into the window's place,
    /// and shows them when it has arrived (ipc: browser reveal)
    property bool shown: !Quickshell.env("STRIX_BROWSER_HIDDEN")

    /// What the back end keeps (store.rs): the settings, and how the filter stands
    property var settings: ({ search: "https://duckduckgo.com/?q=%s", home: "", blocker: true, restore: true, discard: 5, downloads: "", zoom: 1, history: true, gpu: true, passwords: true })
    property var filter: ({ enabled: true, rules: 0, blocked: 0, fetched: 0, fetching: false })
    /// What is being downloaded and what was, newest first
    property var downloads: []

    /// The windows, by a number each; `frames` holds the window of every number
    property var windows: []
    property var frames: ({})
    property int count: 0
    /// The window that had the focus last
    property int front: -1
    /// What a new window starts with: { address, tabs }
    property var starts: ({})

    readonly property bool connected: backend.connected

    /// What is typed into the address: an address as it is, a file by its path, a host with
    /// https, anything else a search
    function address(text) {
        text = text.trim()
        if (text.startsWith("/")) return "file://" + text
        if (/^[a-z][a-z0-9+.-]*:/i.test(text)) return text
        if (/^(localhost|[^\s/]+\.[^\s/]+)(:\d+)?(\/\S*)?$/i.test(text)) return "https://" + text
        return root.settings.search.replace("%s", encodeURIComponent(text))
    }

    /// Asks the back end; without it nothing happens and `done` is not called
    function call(method, params, done) {
        if (backend.connected) backend.call(method, params, done)
    }

    function take(state) {
        if (!state) return
        root.settings = state.settings
        root.filter = state.filter
    }

    function set(values) { root.call("set", values, state => root.take(state)) }

    /// A new window with the address it shows first and the tabs it brings along
    function window(address, tabs) {
        const id = root.count++
        root.starts[id] = { address: address || "", tabs: tabs || [] }
        root.windows = root.windows.concat([id])
    }

    function leave(id) {
        root.keep()
        delete root.frames[id]
        root.windows = root.windows.filter(other => other !== id)
        if (root.windows.length === 0) Qt.quit()
    }

    /// The window to open something in: the one that had the focus last
    function frame() {
        return root.frames[root.front] || root.frames[root.windows[root.windows.length - 1]] || null
    }

    /// The tabs of every window as they stand, for the next start
    function keep() {
        if (root.secret || !root.begun) return
        let list = []
        for (const id of root.windows) if (root.frames[id]) list = list.concat(root.frames[id].kept())
        root.call("keep", { tabs: list })
    }
    Timer { id: later; interval: 800; onTriggered: root.keep() }
    function changed() { later.restart() }

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

    /// The first window: the tabs of the last session, unloaded until they are chosen, and the
    /// address the browser was started with
    property bool begun: false
    function begin() {
        if (root.begun) return
        root.begun = true
        if (!root.secret) {
            // Cookies, the cache and what pages store stay between sessions
            WebEngine.defaultProfile.storageName = "strix"
            WebEngine.defaultProfile.offTheRecord = false
        }
        if (root.settings.downloads) WebEngine.defaultProfile.downloadPath = root.settings.downloads
        const first = Quickshell.env("STRIX_BROWSER_OPEN") || ""
        if (root.secret || !backend.connected) root.window(first, [])
        else backend.call("session", {}, list => root.window(first, list || []))
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
            const frame = root.frame()
            if (frame) frame.open(address)
            root.shown = true
        }
        function reveal(): void { root.shown = true }
        function window(): void {
            root.window("", [])
            root.shown = true
        }
        function settings(): void {
            const frame = root.frame()
            if (frame) frame.options = true
            root.shown = true
        }
        function windows(): int { return root.windows.length }
        function tabs(): int { return root.frame() ? root.frame().count : 0 }
        function current(): string { return root.frame() && root.frame().view ? root.frame().view.url.toString() : "" }
        function title(): string { return root.frame() && root.frame().view ? root.frame().view.title : "" }
        function blocked(): int { return root.filter.blocked }
    }

    Variants {
        model: root.windows

        BrowserWindow {
            required property var modelData
            browser: root
            ident: modelData
        }
    }
}
