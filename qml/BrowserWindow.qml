// One window of the browser: the tabs down the left side, the address over the page. The same
// plate, measures and rows as the search of the shell, which grows into this window.
//
// Ctrl T a new tab, Ctrl W closes it, Ctrl Shift T brings the last closed one back, Ctrl Tab and
// Ctrl Shift Tab go through them. Ctrl N a new window, Ctrl Shift N a private one. Ctrl L the
// address, Ctrl D keeps the page as a bookmark, Ctrl R again, Alt Left and Alt Right back and
// forward, Ctrl F finds in the page, Ctrl + - 0 the size, Ctrl , the settings, F12 the developer
// tools.
//
// A tab in the background lets go of its page after a while (Settings): Chromium discards it and
// loads it again when the tab is chosen. That is where the memory goes in a browser, not into
// what is drawn around the pages.
import QtQuick
import QtWebEngine
import Quickshell
import Strix

FloatingWindow {
    id: window

    /// What the windows share (Browser.qml), and the number of this one
    required property var browser
    required property int ident

    /// The tab that is shown
    property int at: 0
    readonly property var view: pages.count > 0 ? pages.itemAt(window.at) : null
    readonly property int count: tabs.count
    /// The settings stand where the page does
    property bool options: false
    /// A page fills the window (a video): tabs and address step aside
    property bool full: false
    /// The addresses of the tabs that were closed, the last one last
    property var closed: []
    /// A page asks for the camera, the place, notifications…: the request, until it is answered
    property var asking: null
    /// A password was typed into a page: { url, username, password }, until it is kept or not
    property var offer: null
    /// Bookmarks and history that match what is typed into the address, and the one chosen with
    /// the arrows
    property var hits: []
    property int pick: -1
    property bool finding: false
    /// The page that is shown is a bookmark
    property bool marked: false

    readonly property int side: 220
    /// Tabs and address take their place, or none while a page fills the window
    readonly property int edge: window.full ? 0 : Theme.space2

    title: (window.options ? "Settings" : window.view && window.view.title ? window.view.title : "Browser")
        + (browser.secret ? " (private)" : "")
    implicitWidth: 1280
    implicitHeight: 800
    // Smoked glass: the compositor blurs what lies behind the window
    color: Theme.smoke(Theme.surface)
    visible: browser.shown
    // Closed by the person; hidden at the start it waits for its sign
    onVisibleChanged: if (!visible && browser.shown) browser.leave(window.ident)

    Component.onCompleted: {
        browser.frames[window.ident] = window
        browser.front = window.ident
        const start = browser.starts[window.ident] || { address: "", tabs: [] }
        for (const tab of start.tabs) tabs.append({ title: tab.title || "", address: tab.url, fresh: false })
        if (start.address || tabs.count === 0) window.open(start.address)
        else window.at = tabs.count - 1
    }

    function open(text) {
        tabs.append({ title: "", address: text ? browser.address(text) : browser.settings.home, fresh: true })
        window.at = tabs.count - 1
        window.options = false
        if (!text && !browser.settings.home) field.field.forceActiveFocus()
    }

    function close(index) {
        const gone = tabs.get(index).address
        if (gone) window.closed = window.closed.concat([gone])
        if (tabs.count === 1) {
            browser.leave(window.ident)
            return
        }
        tabs.remove(index)
        if (window.at > index || window.at >= tabs.count) window.at -= 1
    }

    function reopen() {
        if (window.closed.length === 0) return
        const last = window.closed[window.closed.length - 1]
        window.closed = window.closed.slice(0, -1)
        window.open(last)
    }

    function turn(step) {
        window.options = false
        window.at = (window.at + step + tabs.count) % tabs.count
    }

    /// Goes where the address says, in the tab that is shown
    function go(text) {
        if (!window.view || text.trim() === "") return
        window.hits = []
        window.options = false
        window.view.loaded = true
        window.view.url = browser.address(text)
        window.view.forceActiveFocus()
    }

    /// The tabs as they stand, for the next start
    function kept() {
        const list = []
        for (let i = 0; i < tabs.count; i++) {
            const tab = tabs.get(i)
            if (tab.address) list.push({ url: tab.address, title: tab.title })
        }
        return list
    }

    function find(on) {
        window.finding = on
        if (on) {
            finder.field.forceActiveFocus()
            finder.field.selectAll()
        } else if (window.view) {
            window.view.findText("")
            window.view.forceActiveFocus()
        }
    }

    /// Larger or smaller by a step, or back to the size of the settings
    function size(step) {
        if (!window.view) return
        window.view.zoomFactor = step === 0 ? browser.settings.zoom : Math.max(0.3, Math.min(3, window.view.zoomFactor + step))
    }

    /// The developer tools of the page that is shown, in a tab beside it
    function inspect() {
        const inspected = window.view
        if (!inspected) return
        window.open("")
        const tools = pages.itemAt(tabs.count - 1)
        tools.loaded = true
        tools.inspectedView = inspected
    }

    /// Keeps the page that is shown as a bookmark, or lets go of it
    function mark() {
        if (!window.view || window.view.url.toString() === "") return
        browser.call("bookmark", { url: window.view.url.toString(), title: window.view.title }, kept => window.marked = kept)
    }
    function lookMarked() {
        if (!window.view || window.options) window.marked = false
        else browser.call("bookmarked", { url: window.view.url.toString() }, kept => window.marked = kept)
    }
    onViewChanged: window.lookMarked()

    /// What matches the address being typed: the bookmarks first, then the history; with nothing
    /// typed, the bookmarks
    function suggest(text) {
        window.pick = -1
        if (!field.field.activeFocus || !browser.connected) {
            window.hits = []
            return
        }
        const typed = text.trim()
        browser.call("bookmarks", { text: typed, limit: typed === "" ? 8 : 3 }, marks => {
            const first = (marks || []).map(page => ({ url: page.url, title: page.title, mark: true }))
            if (typed === "" || browser.secret) {
                window.hits = field.field.activeFocus ? first : []
                return
            }
            browser.call("history", { text: typed, limit: 6 }, pages => {
                const rest = (pages || []).filter(page => !first.some(mark => mark.url === page.url))
                window.hits = field.field.activeFocus ? first.concat(rest).slice(0, 8) : []
            })
        })
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

    // ---------------------------------------------------------------- passwords
    // A script apart from the page's own (its world) finds the field for the password and the
    // one for the name before it. Filling in writes the kept login into them; watching tells
    // the browser what was typed when a form is sent, on the console of that world, which the
    // page cannot read. The login goes to the keyring only when the person says so.
    readonly property string fields: "const pw=[...document.querySelectorAll('input[type=password]')].find(e=>e.offsetParent!==null)||document.querySelector('input[type=password]');"
        + "let user=null;if(pw){const all=[...(pw.form?pw.form.elements:document.querySelectorAll('input'))];"
        + "for(const e of all){if(e===pw)break;if(e.tagName==='INPUT'&&['text','email','tel'].includes((e.type||'text').toLowerCase()))user=e}}"
    function fillIn(page, login) {
        const write = "const put=(el,v)=>{Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value').set.call(el,v);"
            + "el.dispatchEvent(new Event('input',{bubbles:true}));el.dispatchEvent(new Event('change',{bubbles:true}))};"
        page.runJavaScript("(function(u,p){" + window.fields + "if(!pw||pw.value)return;" + write + "if(user&&u&&!user.value)put(user,u);put(pw,p)})("
            + JSON.stringify(login.username) + "," + JSON.stringify(login.password) + ")", WebEngineScript.ApplicationWorld)
    }
    function watch(page) {
        page.runJavaScript("(function(){if(window.strixWatches)return;window.strixWatches=true;"
            + "const tell=()=>{" + window.fields + "if(pw&&pw.value)console.log('\\u0001strix-login'+JSON.stringify({u:user?user.value:'',p:pw.value}))};"
            + "document.addEventListener('submit',tell,true);"
            + "document.addEventListener('keydown',e=>{if(e.key==='Enter'&&e.target&&e.target.tagName==='INPUT')tell()},true);"
            + "document.addEventListener('click',e=>{if(e.target&&e.target.closest&&e.target.closest('button,input[type=submit],[role=button]'))tell()},true)})()",
            WebEngineScript.ApplicationWorld)
    }
    /// A login was typed: offer to keep it, unless the keyring has exactly this one
    function typed(url, text) {
        if (!browser.settings.passwords || browser.secret) return
        let login
        try { login = JSON.parse(text) } catch (e) { return }
        if (!login || !login.p) return
        browser.call("logins", { url: url }, list => {
            if ((list || []).some(known => known.username === login.u && known.password === login.p)) return
            window.offer = { url: url, username: login.u, password: login.p }
        })
    }

    ListModel {
        id: tabs
        onCountChanged: browser.changed()
    }

    // The window that has the focus is the one a link from outside opens in
    Item {
        Window.onActiveChanged: if (Window.active) browser.front = window.ident
    }

    // ------------------------------------------------------------ the tabs
    Item {
        id: strip
        visible: !window.full
        x: Theme.space2
        y: Theme.space2
        width: window.side
        height: parent.height - 2 * Theme.space2

        // Nothing of this window is kept
        ListRow {
            id: hidden
            visible: browser.secret
            width: parent.width
            height: visible ? implicitHeight : 0
            enabled: false
            iconName: "eye-off"
            text: "Private window"
        }

        ListView {
            id: list
            y: hidden.height + (hidden.visible ? Theme.space1 : 0)
            width: parent.width
            height: Math.min(contentHeight, parent.height - y - below.height - Theme.control - 2 * Theme.space1)
            clip: true
            spacing: Theme.space1
            model: tabs
            currentIndex: window.options ? -1 : window.at
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
                selected: !window.options && index === window.at
                glide: true
                onClicked: {
                    window.options = false
                    window.at = index
                }
                // The middle button closes a tab, as the cross under the pointer does
                TapHandler {
                    acceptedButtons: Qt.MiddleButton
                    onTapped: window.close(tab.index)
                }
                IconButton {
                    visible: tab.hovered
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    iconName: "x"
                    onClicked: window.close(tab.index)
                }
            }
        }
        ListRow {
            y: list.y + list.height + Theme.space1
            width: parent.width
            iconName: "plus"
            text: "New tab"
            onClicked: window.open("")
        }

        // What is downloaded, and the way to the settings, at the foot of the strip
        Column {
            id: below
            anchors.bottom: parent.bottom
            width: parent.width
            spacing: Theme.space1

            Repeater {
                model: browser.downloads.slice(0, 3)
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
                detail: browser.filter.enabled && browser.filter.blocked > 0 ? browser.filter.blocked + " blocked" : ""
                selected: window.options
                onClicked: window.options = !window.options
            }
        }
    }

    // ------------------------------------------------------------ the address
    Row {
        id: top
        visible: !window.full
        x: strip.x + strip.width + Theme.space2
        y: Theme.space2
        width: parent.width - x - Theme.space2
        spacing: Theme.space2

        Row {
            id: steps
            spacing: Theme.space1
            IconButton { iconName: "chevron-left"; enabled: !!window.view && window.view.canGoBack; onClicked: window.view.goBack() }
            IconButton { iconName: "chevron-right"; enabled: !!window.view && window.view.canGoForward; onClicked: window.view.goForward() }
            IconButton {
                iconName: window.view && window.view.loading ? "x" : "rotate-cw"
                onClicked: window.view.loading ? window.view.stop() : window.view.reload()
            }
        }
        SearchField {
            id: field
            width: parent.width - x - keeper.width - Theme.space2
            placeholderText: "Search or type an address"
            onAccepted: window.go(window.pick >= 0 && window.hits[window.pick] ? window.hits[window.pick].url : text)
            onTextChanged: window.suggest(text)
            Keys.onDownPressed: window.pick = Math.min(window.pick + 1, window.hits.length - 1)
            Keys.onUpPressed: window.pick = Math.max(window.pick - 1, -1)
            Keys.onEscapePressed: if (window.view) window.view.forceActiveFocus()
            // It shows where the tab is, unless something is being typed
            Binding {
                target: field
                property: "text"
                value: window.options ? "" : window.view ? window.view.url.toString() : ""
                when: !field.field.activeFocus
            }
            Connections {
                target: field.field
                // Taking the field shows the bookmarks, leaving it folds the list away
                function onActiveFocusChanged() {
                    if (field.field.activeFocus) window.suggest(field.text === (window.view ? window.view.url.toString() : "") ? "" : field.text)
                    else window.hits = []
                }
            }
        }
        // The page as a bookmark: lit while it is one
        IconButton {
            id: keeper
            iconName: "book-open"
            checked: window.marked
            enabled: !!window.view && !window.options
            onClicked: window.mark()
        }
    }

    // ------------------------------------------------------------ the pages
    Rectangle {
        id: well
        x: window.full ? 0 : top.x
        y: window.full ? 0 : top.y + Theme.control + Theme.space2
        width: window.full ? parent.width : top.width
        height: parent.height - y - window.edge
        radius: window.full ? 0 : Theme.radiusMd
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
                visible: !window.options && index === window.at
                // A page that names no colour of its own counts on white
                backgroundColor: "white"
                zoomFactor: window.browser.settings.zoom

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
                    window.browser.changed()
                    if (visible) window.lookMarked()
                }
                onLoadingChanged: info => {
                    if (info.status !== WebEngineView.LoadSucceededStatus) return
                    const here = url.toString()
                    if (!window.browser.secret) window.browser.call("visit", { url: here, title: title })
                    // How many requests the filter has blocked by now, for the strip
                    window.browser.call("state", {}, state => window.browser.take(state))
                    // What the lists hide on this page
                    window.browser.call("cosmetic", { url: here }, hide => {
                        if (!hide || hide.length === 0) return
                        const rule = JSON.stringify(hide.join(",") + "{display:none!important}")
                        page.runJavaScript("(function(){const s=document.createElement('style');s.textContent=" + rule + ";document.documentElement.appendChild(s)})()", WebEngineScript.ApplicationWorld)
                    })
                    if (!window.browser.settings.passwords) return
                    page.watch()
                    window.browser.call("logins", { url: here }, list => {
                        // Still the page the logins were asked for
                        if (list && list.length > 0 && page.url.toString() === here) window.fillIn(page, list[0])
                    })
                }
                function watch() { window.watch(page) }
                onJavaScriptConsoleMessage: (level, message, line, source) => {
                    if (message.startsWith("\u0001strix-login")) window.typed(url.toString(), message.slice(12))
                }
                // What a page opens goes into a tab beside it
                onNewWindowRequested: request => {
                    window.open("")
                    const beside = pages.itemAt(tabs.count - 1)
                    beside.loaded = true
                    request.openIn(beside)
                }
                onFullScreenRequested: request => {
                    request.accept()
                    window.full = request.toggleOn
                }
                onPermissionRequested: permission => window.asking = permission
                Timer {
                    interval: Math.max(1, window.browser.settings.discard) * 60 * 1000
                    running: window.browser.settings.discard > 0 && page.loaded && !page.visible && !page.recentlyAudible
                        && page.lifecycleState !== WebEngineView.LifecycleState.Discarded
                    onTriggered: page.lifecycleState = WebEngineView.LifecycleState.Discarded
                }
            }
        }

        // How far the page has come
        Rectangle {
            visible: !window.options && !!window.view && window.view.loading
            width: parent.width * (window.view ? window.view.loadProgress / 100 : 0)
            height: 2 * Theme.lineHair
            color: Theme.accent
            Behavior on width { NumberAnimation { duration: Theme.durFast } }
        }

        Options {
            anchors.fill: parent
            visible: window.options
            settings: window.browser.settings
            filter: window.browser.filter
            onChange: values => window.browser.set(values)
            onLists: window.browser.call("lists", {}, state => window.browser.take(state))
            onForget: window.browser.call("forget", {})
            onEmptyCache: WebEngine.defaultProfile.clearHttpCache()
            // The figures of the filter move while the page is open
            Timer {
                interval: 2000
                repeat: true
                running: window.options
                onTriggered: window.browser.call("state", {}, state => window.browser.take(state))
            }
        }

        // What the browser asks the person, one under the other at the top of the page
        Column {
            anchors { top: parent.top; horizontalCenter: parent.horizontalCenter; topMargin: Theme.space2 }
            spacing: Theme.space2

            // A page asks for something of the machine
            Bar {
                visible: window.asking !== null
                anchors.horizontalCenter: parent.horizontalCenter
                width: ask.implicitWidth + 2 * Theme.space3
                height: Theme.control + 2 * Theme.space2
                Row {
                    id: ask
                    anchors.centerIn: parent
                    spacing: Theme.space2
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        textStyle: "label"
                        color: Theme.text
                        text: window.asking ? window.asking.origin.toString().replace(/\/$/, "") + " asks for " + window.wish(window.asking.permissionType) : ""
                    }
                    Button { text: "Allow"; onClicked: { window.asking.grant(); window.asking = null } }
                    Button { variant: "quiet"; text: "Deny"; onClicked: { window.asking.deny(); window.asking = null } }
                }
            }

            // A password was typed
            Bar {
                visible: window.offer !== null
                anchors.horizontalCenter: parent.horizontalCenter
                width: keep.implicitWidth + 2 * Theme.space3
                height: Theme.control + 2 * Theme.space2
                Row {
                    id: keep
                    anchors.centerIn: parent
                    spacing: Theme.space2
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        textStyle: "label"
                        color: Theme.text
                        text: window.offer ? "Keep the password" + (window.offer.username ? " of " + window.offer.username : "") + " for "
                            + window.offer.url.replace(/^https?:\/\/([^\/]+).*$/, "$1") + "?" : ""
                    }
                    Button {
                        text: "Keep"
                        onClicked: {
                            window.browser.call("login", window.offer)
                            window.offer = null
                        }
                    }
                    Button { variant: "quiet"; text: "Not now"; onClicked: window.offer = null }
                }
            }
        }

        // Finding in the page
        Bar {
            visible: window.finding
            anchors { top: parent.top; right: parent.right; margins: Theme.space2 }
            width: 320
            height: Theme.control + 2 * Theme.space2
            SearchField {
                id: finder
                x: Theme.space2
                y: Theme.space2
                width: parent.width - 2 * Theme.space2
                placeholderText: "Find in the page"
                KeyCaps { keys: "Esc" }
                onTextChanged: if (window.view) window.view.findText(text)
                onAccepted: if (window.view) window.view.findText(text)
                Keys.onEscapePressed: window.find(false)
            }
        }
    }

    // Bookmarks and what was opened before, under the address
    Bar {
        visible: window.hits.length > 0
        x: top.x + field.x
        y: top.y + Theme.control + Theme.space1
        width: field.width
        height: found.implicitHeight + 2 * Theme.space2
        Column {
            id: found
            x: Theme.space2
            y: Theme.space2
            width: parent.width - 2 * Theme.space2
            Repeater {
                model: window.hits
                ListRow {
                    required property var modelData
                    required property int index
                    width: found.width
                    iconName: modelData.mark ? "book-open" : "history"
                    text: modelData.title || modelData.url
                    detail: modelData.url.replace(/^https?:\/\/(www\.)?/, "").slice(0, 40)
                    selected: index === window.pick
                    onClicked: window.go(modelData.url)
                }
            }
        }
    }

    Shortcut { sequence: "Ctrl+T"; onActivated: window.open("") }
    Shortcut { sequence: "Ctrl+W"; onActivated: window.close(window.at) }
    Shortcut { sequence: "Ctrl+Shift+T"; onActivated: window.reopen() }
    Shortcut { sequence: "Ctrl+N"; onActivated: window.browser.window("", []) }
    Shortcut { sequence: "Ctrl+Shift+N"; onActivated: Quickshell.execDetached(["strix-browser", "--private"]) }
    Shortcut { sequence: "Ctrl+Tab"; onActivated: window.turn(1) }
    Shortcut { sequence: "Ctrl+Shift+Tab"; onActivated: window.turn(-1) }
    Shortcut { sequences: ["Ctrl+R", "F5"]; onActivated: if (window.view) window.view.reload() }
    Shortcut { sequence: "Alt+Left"; onActivated: if (window.view) window.view.goBack() }
    Shortcut { sequence: "Alt+Right"; onActivated: if (window.view) window.view.goForward() }
    Shortcut { sequence: "Ctrl+F"; onActivated: window.find(true) }
    Shortcut { sequence: "Ctrl+D"; onActivated: window.mark() }
    Shortcut { sequence: "Ctrl+,"; onActivated: window.options = !window.options }
    Shortcut { sequences: ["Ctrl++", "Ctrl+="]; onActivated: window.size(0.1) }
    Shortcut { sequence: "Ctrl+-"; onActivated: window.size(-0.1) }
    Shortcut { sequence: "Ctrl+0"; onActivated: window.size(0) }
    Shortcut { sequence: "F12"; onActivated: window.inspect() }
    Shortcut {
        sequence: "Ctrl+L"
        onActivated: {
            field.field.forceActiveFocus()
            field.field.selectAll()
        }
    }
}
