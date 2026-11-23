// One window of the browser. Everything but the page stands in the strip down the left side:
// back, forward and again, where the page is, the essentials (pages kept as buttons) and under
// them the tabs. The page has the rest of the window to itself. The address is one plate that
// floats over the page when it is asked for, as the search of the shell floats over the desktop;
// that search grows into this window, so both use the same glass, measures and rows. While no
// page is shown the start page stands in its place.
//
// The keys (Options.qml lists them for the person):
//   Ctrl T asks for a page in a new tab, Ctrl L, Ctrl K, F6 for one in the tab that is shown
//   Ctrl W closes what is shown, Ctrl Shift T brings the last closed tab back
//   Ctrl Tab, Ctrl Shift Tab, Ctrl PgDown, Ctrl PgUp through the tabs; Ctrl 1…8 a tab, Ctrl 9 the last
//   Ctrl Shift PgUp, Ctrl Shift PgDown carry the tab up and down
//   Alt 1…9 an essential, Ctrl Shift D keeps the page as one; Ctrl D keeps it as a bookmark
//   Ctrl N a new window, Ctrl Shift N a private one, Ctrl Q leaves
//   Ctrl R, F5 again; Ctrl Shift R again without the kept copy; Esc stops
//   Alt Left, Alt Right back and forward; Alt Home the start page
//   Ctrl F finds in the page; Ctrl + - 0 the size; Ctrl U the source; F12 the developer tools
//   Ctrl Alt C the strip away and back; Ctrl , the settings
import QtQuick
import QtQuick.Templates as T
import QtQml
import QtWebEngine
import Quickshell
import Strix

FloatingWindow {
    id: window

    /// What the windows share (Browser.qml), and the number of this one
    required property var browser
    required property int ident

    /// The tab that is shown, unless an essential is
    property int at: 0
    /// The page of the essential that is shown, in place of a tab
    property var held: null
    /// The addresses of the essentials whose pages are loaded in this window
    property var opened: []
    readonly property var view: window.held ? window.held : pages.count > 0 ? pages.itemAt(window.at) : null
    readonly property int count: tabs.count
    /// The start page was asked for, over the page that is open
    property bool home: false
    /// No page to show: the start page stands there
    readonly property bool starting: !window.options && (window.home || !window.view || window.view.blank)
    /// The settings stand where the page does
    property bool options: false
    /// A page fills the window (a video): the strip steps aside
    property bool full: false
    /// The strip was put away
    property bool narrow: false
    /// The address floats over the page; `fresh`: what is typed opens in a new tab
    property bool asked: false
    property bool fresh: false
    /// The addresses of the tabs that were closed, the last one last
    property var closed: []
    /// A page asks for the camera, the place, notifications…: the request, until it is answered
    property var asking: null
    /// A password was typed into a page: { url, username, password }, until it is kept or not
    property var offer: null
    /// A page says or asks something (alert, confirm, prompt): the request, until it is answered
    property var saying: null
    /// A page or a proxy wants a name and a password: the request
    property var signing: null
    /// The small note of the part of a page under the pointer: { text, x, y }
    property var note: null
    /// Where the link under the pointer leads
    property string aim: ""
    /// What the right button was pressed on in a page, for its menu
    property var spot: ({})
    property bool finding: false
    /// The page that is shown is a bookmark
    property bool marked: false
    /// A tab is carried: the gap it would drop into, or -1
    property int gap: -1

    /// The strip of essentials and tabs; the search of the shell grows to the same measure
    readonly property int side: 264
    /// The height of a tab, and of the other rows of the strip
    readonly property int row: Theme.control + Theme.space2 - Theme.lineBold
    readonly property bool bare: window.full || window.narrow
    /// The address of the page that is shown; none while the start page or the settings stand
    readonly property string here: window.view && !window.starting && !window.options ? window.view.url.toString() : ""

    /// A row of the menu of a page. One that has nothing to act on takes no room
    component Act: MenuItem {
        property bool shown: true
        visible: shown
        height: shown ? implicitHeight : 0
    }

    title: (window.options ? "Settings" : window.starting ? "New tab" : window.view.title || "Browser")
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
        for (const tab of start.tabs) window.add(tab.url, tab.title || "", false)
        if (start.address) window.open(start.address)
        else if (tabs.count > 0) window.at = tabs.count - 1
        else if (browser.settings.home) window.open(browser.settings.home)
        window.rest()
    }

    function add(address, title, fresh) {
        tabs.append({ title: title, address: address, fresh: fresh, icon: "", busy: false, sound: false, muted: false })
    }

    /// A new tab where the text leads
    function open(text) {
        window.add(browser.address(text), "", true)
        window.show(tabs.count - 1)
    }

    function show(index) {
        window.options = false
        window.home = false
        window.asked = false
        window.held = null
        window.at = index
    }

    /// An empty tab for the developer tools or for what a page opens; in the background it does
    /// not take the place of the page that is shown
    function claim(background) {
        window.add("", "", true)
        const page = pages.itemAt(tabs.count - 1)
        page.claimed = true
        page.loaded = true
        if (!background) window.show(tabs.count - 1)
        return page
    }

    /// Goes to an essential: its page loads the first time and stays until it is closed
    function essential(address) {
        window.options = false
        window.home = false
        window.asked = false
        if (window.opened.indexOf(address) < 0) window.opened = window.opened.concat([address])
        for (let i = 0; i < shelf.count; i++) {
            const slot = shelf.itemAt(i)
            if (slot && slot.url === address) window.held = slot.item
        }
    }
    /// An essential was let go of, or its page closed
    function dropped(address) {
        if (window.held && window.held.address === address) window.held = null
        window.opened = window.opened.filter(other => other !== address)
    }

    function close(index) {
        const gone = tabs.get(index).address
        if (gone) window.closed = window.closed.concat([gone])
        tabs.remove(index)
        if (window.at > index || window.at >= tabs.count) window.at = Math.max(0, window.at - 1)
    }
    function closeOthers(index) {
        for (let i = tabs.count - 1; i > index; i--) window.close(i)
        for (let i = 0; i < index; i++) window.close(0)
        window.show(0)
    }

    /// Closes what is shown: the start page over a page, the essential's page, the tab, and
    /// with nothing open the window
    function shut() {
        if (window.home && window.view) window.home = false
        else if (window.held) window.dropped(window.held.address)
        else if (tabs.count === 0) browser.leave(window.ident)
        else window.close(window.at)
    }

    function reopen() {
        if (window.closed.length === 0) return
        const last = window.closed[window.closed.length - 1]
        window.closed = window.closed.slice(0, -1)
        window.open(last)
    }

    function turn(step) {
        if (tabs.count === 0) return
        window.show(window.held || window.home ? window.at : (window.at + step + tabs.count) % tabs.count)
    }

    /// Carries a tab to another place; the tab that is shown stays the one shown
    function move(from, to) {
        to = Math.max(0, Math.min(tabs.count - 1, to))
        if (from === to) return
        tabs.move(from, to, 1)
        if (window.at === from) window.at = to
        else if (from < window.at && to >= window.at) window.at -= 1
        else if (from > window.at && to <= window.at) window.at += 1
    }

    /// The address floats: for a new tab (`fresh`) or with where the page is, to change it
    function ask(fresh) {
        window.options = false
        window.fresh = fresh || window.starting
        window.asked = true
        address.take(window.fresh ? "" : window.here)
    }

    /// Goes where the text says: in a new tab, or in the page that is shown
    function go(text) {
        if (text.trim() === "") return
        const fresh = window.fresh || window.starting || !window.view
        window.asked = false
        window.options = false
        if (fresh) {
            window.open(text)
            return
        }
        window.view.loaded = true
        window.view.url = browser.address(text)
        window.rest()
    }

    /// The keys go to the page, or to the start page while it stands
    function rest() {
        if (window.asked) return
        if (window.starting) start.forceActiveFocus()
        else if (window.view && !window.options) window.view.forceActiveFocus()
    }
    onStartingChanged: window.rest()
    onViewChanged: {
        window.rest()
        window.aim = ""
        window.note = null
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
            window.rest()
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
        if (!inspected || inspected.blank) return
        window.claim(false).inspectedView = inspected
    }

    /// Keeps the page that is shown as a bookmark, or lets go of it
    function mark() {
        if (window.here === "") return
        browser.call("bookmark", { url: window.here, title: window.view.title }, kept => window.marked = kept)
    }
    function lookMarked() {
        if (window.here === "") window.marked = false
        else browser.call("bookmarked", { url: window.here }, kept => window.marked = kept)
    }
    onHereChanged: window.lookMarked()
    // What a page asks takes the keys until it is answered
    onSayingChanged: if (window.saying) {
        reply.text = window.saying.defaultText
        if (window.saying.type === JavaScriptDialogRequest.DialogTypePrompt) reply.field.forceActiveFocus()
        else yes.forceActiveFocus()
    }
    onSigningChanged: if (window.signing) {
        user.text = ""
        pass.text = ""
        user.field.forceActiveFocus()
    }
    /// Keeps the page that is shown as an essential, or lets go of it
    function pin() {
        if (window.here !== "") browser.pin(window.here, window.view.title)
    }

    /// The right button in a page: what it was pressed on, and the menu for it
    function menu(page, request) {
        window.spot = {
            link: request.linkUrl.toString(),
            picture: request.mediaType === ContextMenuRequest.MediaTypeImage ? request.mediaUrl.toString() : "",
            text: request.selectedText,
            field: request.isContentEditable
        }
        pageMenu.popup(page, request.position.x, request.position.y)
    }
    function act(action) {
        if (window.view) window.view.triggerWebAction(action)
    }

    /// A measure moved to the next whole pixel of the screen
    function whole(measure) { return Math.ceil(measure * Screen.devicePixelRatio) / Screen.devicePixelRatio }

    /// An address as a row shows it: without its scheme
    function short(address) { return address.replace(/^[a-z]+:\/\/(www\.)?/, "").replace(/\/$/, "") }
    /// Only where it lives
    function host(address) { return window.short(address).replace(/[\/?#].*$/, "") }

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

    // ------------------------------------------------------------------ the strip
    Item {
        id: strip
        visible: !window.bare
        x: Theme.space2
        y: Theme.space2
        width: window.side
        height: parent.height - 2 * Theme.space2

        Column {
            id: above
            width: parent.width
            spacing: Theme.space2

            // Back, forward, again; at the right the start page and the strip itself
            Item {
                width: parent.width
                height: Theme.control
                Row {
                    spacing: Theme.space1
                    IconButton { iconName: "chevron-left"; enabled: window.here !== "" && window.view.canGoBack; onClicked: window.view.goBack() }
                    IconButton { iconName: "chevron-right"; enabled: window.here !== "" && window.view.canGoForward; onClicked: window.view.goForward() }
                    IconButton {
                        iconName: window.here !== "" && window.view.loading ? "x" : "rotate-cw"
                        enabled: window.here !== ""
                        onClicked: window.view.loading ? window.view.stop() : window.view.reload()
                    }
                }
                Row {
                    anchors.right: parent.right
                    spacing: Theme.space1
                    IconButton {
                        id: homer
                        iconName: "layout-grid"
                        checked: window.starting
                        onClicked: window.home = !window.starting
                        ToolTip { text: "Start page"; visible: homer.hovered }
                    }
                    IconButton {
                        id: hider
                        iconName: "app-window"
                        onClicked: window.narrow = true
                        ToolTip { text: "Put the strip away"; visible: hider.hovered }
                    }
                }
            }

            // Where the page is. A click lets the address float, to change it
            Rectangle {
                width: parent.width
                height: window.row
                radius: Theme.radiusMd
                color: Theme.alpha(Theme.text, whereArea.containsMouse ? 0.09 : 0.05)
                border.width: Theme.lineHair
                border.color: Theme.glassEdge
                Behavior on color { ColorAnimation { duration: Theme.durFast } }

                MouseArea {
                    id: whereArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.IBeamCursor
                    onClicked: window.ask(false)
                }
                Row {
                    x: Theme.space3
                    width: parent.width - x - (keepers.visible ? keepers.width : 0) - Theme.space2
                    height: parent.height
                    spacing: Theme.space2
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        // A lock in front of an address that is reached over a safe line
                        name: browser.secret ? "eye-off" : window.here === "" ? "search" : window.here.startsWith("https:") ? "lock" : "globe"
                    }
                    Label {
                        width: parent.width - Theme.icon - parent.spacing
                        anchors.verticalCenter: parent.verticalCenter
                        text: window.options ? "Settings" : window.here === "" ? (browser.secret ? "Private window" : "Search or type an address") : window.host(window.here)
                        color: window.here === "" ? Theme.textFaint : Theme.text
                        elide: Text.ElideRight
                    }
                }
                // The page as an essential and as a bookmark: lit while it is one
                Row {
                    id: keepers
                    visible: window.here !== ""
                    anchors { right: parent.right; rightMargin: Theme.lineBold; verticalCenter: parent.verticalCenter }
                    IconButton {
                        id: pinner
                        iconName: "pin"
                        checked: browser.pinned.indexOf(window.here) >= 0
                        onClicked: window.pin()
                        ToolTip { text: pinner.checked ? "Let go of the essential" : "Keep as an essential"; visible: pinner.hovered }
                    }
                    IconButton {
                        id: keeper
                        iconName: "star"
                        checked: window.marked
                        onClicked: window.mark()
                        ToolTip { text: keeper.checked ? "Let go of the bookmark" : "Keep as a bookmark"; visible: keeper.hovered }
                    }
                }
            }

            Grid {
                id: buttons
                visible: browser.essentials.count > 0
                width: parent.width
                columns: 3
                spacing: Theme.space1
                Repeater {
                    model: browser.essentials
                    Essential {
                        required property string url
                        required title
                        required icon
                        required property int index
                        width: (buttons.width - 2 * buttons.spacing) / 3
                        place: index
                        inRow: 3
                        gap: buttons.spacing
                        count: browser.essentials.count
                        onArranged: to => browser.arrange(url, to)
                        address: url
                        open: window.opened.indexOf(url) >= 0
                        selected: !window.options && !window.home && !!window.held && window.held.address === url
                        onClicked: window.essential(url)
                        onDropped: browser.pin(url, "")
                    }
                }
            }
            Rule { width: parent.width }

            ListRow {
                width: parent.width
                height: window.row
                iconName: "plus"
                text: "New tab"
                detail: "Ctrl T"
                onClicked: window.ask(true)
            }
        }

        ListView {
            id: list
            y: above.height + Theme.lineBold
            width: parent.width
            height: Math.min(contentHeight, parent.height - y - below.height - Theme.space2)
            // Only a list that runs over is cut at its edge
            clip: contentHeight > height
            spacing: Theme.lineBold
            model: tabs
            currentIndex: window.options || window.home || window.held ? -1 : window.at
            highlight: Glide {}
            highlightFollowsCurrentItem: true
            highlightMoveDuration: Theme.durBase
            highlightMoveVelocity: -1
            highlightResizeDuration: 0
            displaced: Transition { NumberAnimation { properties: "y"; duration: Theme.durBase; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
            move: Transition { NumberAnimation { properties: "y"; duration: Theme.durBase; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }

            delegate: PageRow {
                id: tab
                required property int index
                required property var model
                width: list.width
                height: window.row
                title: model.title || window.short(model.address) || "New tab"
                named: model.title || window.short(model.address)
                icon: model.icon
                busy: model.busy
                sounding: model.sound
                muted: model.muted
                selected: list.currentIndex === index
                glide: true
                closable: true
                movable: true
                onClicked: window.show(index)
                onClosed: window.close(index)
                onSound: pages.itemAt(index).audioMuted = !model.muted
                onAsked: (x, y) => {
                    tabMenu.index = index
                    tabMenu.popup(tab, x, y)
                }
                // The gap under the pointer, counted in rows from the top of the list
                onCarry: y => window.gap = Math.max(0, Math.min(tabs.count, Math.round((tab.y + y) / (window.row + list.spacing))))
                onDrop: {
                    const to = window.gap > index ? window.gap - 1 : window.gap
                    window.gap = -1
                    window.move(index, to)
                }
            }

            // Where the tab that is carried would go
            Rectangle {
                visible: window.gap >= 0
                parent: list.contentItem
                z: 3
                y: window.gap * (window.row + list.spacing) - list.spacing
                width: list.width
                height: Theme.lineBold
                radius: height / 2
                color: Theme.accent
            }
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
                detail: browser.filter.enabled && browser.filter.blocked > 0 ? browser.filter.blocked + " blocked" : "Ctrl ,"
                selected: window.options
                onClicked: window.options = !window.options
            }
        }
    }

    // The strip is away: the edge of the window brings it back
    Rectangle {
        visible: window.narrow && !window.full
        width: Theme.space2
        height: parent.height
        color: back.containsMouse ? Theme.alpha(Theme.text, 0.09) : "transparent"
        MouseArea {
            id: back
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: window.narrow = false
        }
    }

    // ------------------------------------------------------------------ the page
    Rectangle {
        id: well
        // On whole pixels of the screen, for the pages (Page.qml)
        x: window.full ? 0 : window.whole(window.narrow ? Theme.space2 : strip.x + strip.width + Theme.space2)
        y: window.full ? 0 : window.whole(Theme.space2)
        width: parent.width - x - (window.full ? 0 : Theme.space2)
        height: parent.height - y - (window.full ? 0 : Theme.space2)
        radius: window.full ? 0 : Theme.radiusMd
        // A well in the glass of the window
        color: Theme.alpha(Theme.text, 0.04)
        border.width: window.starting || window.options ? Theme.lineHair : 0
        border.color: Theme.glassEdge

        // The pages of the tabs
        Repeater {
            id: pages
            model: tabs

            Page {
                required property int index
                required address
                required fresh
                readonly property bool busy: loading
                readonly property bool sound: recentlyAudible

                host: window
                onTitleChanged: if (title !== "") tabs.setProperty(index, "title", title)
                onIconChanged: tabs.setProperty(index, "icon", icon.toString())
                onBusyChanged: tabs.setProperty(index, "busy", busy)
                onSoundChanged: tabs.setProperty(index, "sound", sound)
                onAudioMutedChanged: tabs.setProperty(index, "muted", audioMuted)
                onUrlChanged: {
                    if (url.toString() === "") return
                    tabs.setProperty(index, "address", url.toString())
                    window.browser.changed()
                }
            }
        }
        // The pages of the essentials that are open
        Repeater {
            id: shelf
            model: window.browser.essentials

            Loader {
                id: slot
                required property string url
                anchors.fill: parent
                active: window.opened.indexOf(url) >= 0
                sourceComponent: Page {
                    host: window
                    address: slot.url
                }
            }
        }

        Start {
            id: start
            anchors.fill: parent
            visible: window.starting
            browser: window.browser
            onOpen: url => window.open(url)
            onEssential: url => window.essential(url)
            onAsk: text => {
                window.ask(true)
                if (text !== "") address.begin(text)
            }
        }

        // How far the page has come
        Rectangle {
            visible: window.here !== "" && window.view.loading
            width: parent.width * (window.view ? window.view.loadProgress / 100 : 0)
            height: Theme.lineBold
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

        // Where the link under the pointer leads, in the corner of the page
        Bar {
            visible: window.aim !== "" && window.here !== ""
            anchors { left: parent.left; bottom: parent.bottom; margins: Theme.space1 }
            width: Math.min(leads.implicitWidth + 2 * Theme.space2, parent.width / 2)
            height: Theme.mark + Theme.space1
            elevation: "pop"
            Label {
                id: leads
                x: Theme.space2
                width: parent.width - 2 * Theme.space2
                height: parent.height
                textStyle: "micro"
                color: Theme.textMuted
                text: window.short(window.aim)
                elide: Text.ElideMiddle
            }
        }

        // The small note of a part of the page
        Bar {
            visible: window.note !== null && window.here !== ""
            x: window.note ? Math.min(window.note.x, parent.width - width - Theme.space1) : 0
            y: window.note ? Math.min(window.note.y + Theme.space5, parent.height - height - Theme.space1) : 0
            width: says.width + 2 * Theme.space2
            height: says.height + Theme.space2
            elevation: "pop"
            Label {
                id: says
                x: Theme.space2
                y: Theme.space1
                width: Math.min(implicitWidth, 360)
                textStyle: "caption"
                wrapMode: Text.Wrap
                text: window.note ? window.note.text : ""
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
                        text: window.asking ? window.host(window.asking.origin.toString()) + " asks for " + window.wish(window.asking.permissionType) : ""
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
                        text: window.offer ? "Keep the password" + (window.offer.username ? " of " + window.offer.username : "") + " for "
                            + window.host(window.offer.url) + "?" : ""
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

        // The page steps back while the address floats or the page waits for an answer; a
        // click beside the address puts it away
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            visible: window.asked || window.saying !== null || window.signing !== null
            color: Theme.alpha(Theme.scrim, 0.45)
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                hoverEnabled: true
                onWheel: wheel => wheel.accepted = true
                onClicked: if (window.asked) {
                    window.asked = false
                    window.rest()
                }
            }
        }

        // A page says or asks something. Enter says yes, Esc no
        Bar {
            visible: window.saying !== null
            anchors.centerIn: parent
            width: 420
            height: word.implicitHeight + 2 * Theme.space4
            Keys.onReturnPressed: yes.clicked()
            Keys.onEnterPressed: yes.clicked()
            Keys.onEscapePressed: no.visible ? no.clicked() : yes.clicked()
            Column {
                id: word
                x: Theme.space4
                y: Theme.space4
                width: parent.width - 2 * Theme.space4
                spacing: Theme.space3
                Label {
                    textStyle: "aside"
                    color: Theme.textMuted
                    text: window.saying ? window.host(window.saying.securityOrigin.toString()) + (window.saying.type === JavaScriptDialogRequest.DialogTypeAlert ? " says" : " asks") : ""
                }
                Label {
                    width: parent.width
                    wrapMode: Text.Wrap
                    maximumLineCount: 12
                    elide: Text.ElideRight
                    text: !window.saying ? "" : window.saying.type === JavaScriptDialogRequest.DialogTypeBeforeUnload
                        ? "Leave this page? What was typed into it may be lost." : window.saying.message
                }
                TextField {
                    id: reply
                    visible: !!window.saying && window.saying.type === JavaScriptDialogRequest.DialogTypePrompt
                    width: parent.width
                    onAccepted: yes.clicked()
                }
                Row {
                    anchors.right: parent.right
                    spacing: Theme.space2
                    Button {
                        id: no
                        variant: "quiet"
                        visible: !!window.saying && window.saying.type !== JavaScriptDialogRequest.DialogTypeAlert
                        text: "Cancel"
                        onClicked: {
                            window.saying.dialogReject()
                            window.saying = null
                            window.rest()
                        }
                    }
                    Button {
                        id: yes
                        text: !!window.saying && window.saying.type === JavaScriptDialogRequest.DialogTypeBeforeUnload ? "Leave" : "OK"
                        onClicked: {
                            window.saying.dialogAccept(reply.text)
                            window.saying = null
                            window.rest()
                        }
                    }
                }
            }
        }

        // A page or a proxy wants a name and a password
        Bar {
            visible: window.signing !== null
            anchors.centerIn: parent
            width: 420
            height: sign.implicitHeight + 2 * Theme.space4
            Keys.onEscapePressed: refuse.clicked()
            Column {
                id: sign
                x: Theme.space4
                y: Theme.space4
                width: parent.width - 2 * Theme.space4
                spacing: Theme.space3
                Label {
                    width: parent.width
                    wrapMode: Text.Wrap
                    textStyle: "aside"
                    color: Theme.textMuted
                    text: window.signing ? (window.signing.proxyHost || window.host(window.signing.url.toString())) + " wants a name and a password" : ""
                }
                TextField {
                    id: user
                    width: parent.width
                    placeholderText: "Name"
                    onAccepted: pass.field.forceActiveFocus()
                }
                TextField {
                    id: pass
                    width: parent.width
                    placeholderText: "Password"
                    echoMode: TextInput.Password
                    onAccepted: enter.clicked()
                }
                Row {
                    anchors.right: parent.right
                    spacing: Theme.space2
                    Button {
                        id: refuse
                        variant: "quiet"
                        text: "Cancel"
                        onClicked: {
                            window.signing.dialogReject()
                            window.signing = null
                            window.rest()
                        }
                    }
                    Button {
                        id: enter
                        text: "Sign in"
                        onClicked: {
                            window.signing.dialogAccept(user.text, pass.text)
                            window.signing = null
                            window.rest()
                        }
                    }
                }
            }
        }

        // The address floats in the upper part of the page while it is asked for
        Address {
            id: address
            visible: window.asked
            browser: window.browser
            doing: window.fresh || window.starting ? "Open in a new tab" : "Go there"
            x: Math.round((parent.width - width) / 2)
            y: Math.round(parent.height * 0.16)
            width: Math.min(640, parent.width - 2 * Theme.space5)
            onGo: text => window.go(text)
            onAway: {
                window.asked = false
                window.rest()
            }
        }
    }

    // ------------------------------------------------------------------ the menus
    Menu {
        id: tabMenu
        property int index: 0
        // Drawn in the window, on a ground nothing shows through
        popupType: T.Popup.Item
        background: Bar { implicitWidth: 220; elevation: "pop" }
        readonly property var tab: index < tabs.count ? tabs.get(index) : null
        MenuItem { text: "Load again"; iconName: "rotate-cw"; onTriggered: pages.itemAt(tabMenu.index).reload() }
        MenuItem { text: "Open again beside it"; iconName: "copy"; onTriggered: window.open(tabMenu.tab.address) }
        MenuItem {
            text: tabMenu.tab && tabMenu.tab.muted ? "Sound on" : "Sound off"
            iconName: tabMenu.tab && tabMenu.tab.muted ? "volume-2" : "volume-x"
            onTriggered: pages.itemAt(tabMenu.index).audioMuted = !tabMenu.tab.muted
        }
        MenuSeparator {}
        MenuItem { text: "Keep as an essential"; iconName: "pin"; onTriggered: window.browser.pin(tabMenu.tab.address, tabMenu.tab.title) }
        MenuItem { text: "Keep as a bookmark"; iconName: "star"; onTriggered: window.browser.call("bookmark", { url: tabMenu.tab.address, title: tabMenu.tab.title }, () => window.lookMarked()) }
        MenuSeparator {}
        MenuItem { text: "Close"; iconName: "x"; shortcut: "Ctrl W"; onTriggered: window.close(tabMenu.index) }
        MenuItem { text: "Close the others"; onTriggered: window.closeOthers(tabMenu.index) }
    }

    // The right button in a page. Its ground lets nothing through: the page under it may be white
    Menu {
        id: pageMenu
        popupType: T.Popup.Item
        implicitWidth: 260
        background: Bar { implicitWidth: 260; elevation: "pop" }
        readonly property bool onLink: !!window.spot.link
        readonly property bool onPicture: !!window.spot.picture
        readonly property bool onText: !!window.spot.text
        readonly property bool onField: !!window.spot.field
        readonly property bool plain: !onLink && !onPicture && !onText && !onField

        Act { shown: pageMenu.onLink; text: "Open in a new tab"; iconName: "plus"; onTriggered: window.act(WebEngineView.OpenLinkInNewTab) }
        Act { shown: pageMenu.onLink; text: "Open in a new window"; iconName: "app-window"; onTriggered: window.browser.window(window.spot.link, []) }
        Act { shown: pageMenu.onLink; text: "Copy the link"; iconName: "copy"; onTriggered: window.act(WebEngineView.CopyLinkToClipboard) }
        Act { shown: pageMenu.onLink; text: "Save what it leads to"; iconName: "download"; onTriggered: window.act(WebEngineView.DownloadLinkToDisk) }
        Act { shown: pageMenu.onPicture; text: "Open the picture in a new tab"; iconName: "image"; onTriggered: window.open(window.spot.picture) }
        Act { shown: pageMenu.onPicture; text: "Save the picture"; iconName: "download"; onTriggered: window.act(WebEngineView.DownloadImageToDisk) }
        Act { shown: pageMenu.onPicture; text: "Copy the picture"; iconName: "copy"; onTriggered: window.act(WebEngineView.CopyImageToClipboard) }
        Act { shown: pageMenu.onField; text: "Cut"; shortcut: "Ctrl X"; onTriggered: window.act(WebEngineView.Cut) }
        Act { shown: pageMenu.onText || pageMenu.onField; text: "Copy"; shortcut: "Ctrl C"; onTriggered: window.act(WebEngineView.Copy) }
        Act { shown: pageMenu.onField; text: "Paste"; shortcut: "Ctrl V"; onTriggered: window.act(WebEngineView.Paste) }
        Act { shown: pageMenu.onField; text: "Select all"; shortcut: "Ctrl A"; onTriggered: window.act(WebEngineView.SelectAll) }
        Act {
            shown: pageMenu.onText
            iconName: "search"
            text: "Search for “" + (window.spot.text || "").trim().slice(0, 18) + ((window.spot.text || "").trim().length > 18 ? "…" : "") + "”"
            onTriggered: window.open(window.browser.settings.search.replace("%s", encodeURIComponent(window.spot.text.trim())))
        }
        Act { shown: pageMenu.plain; text: "Back"; iconName: "chevron-left"; shortcut: "Alt ←"; enabled: !!window.view && window.view.canGoBack; onTriggered: window.view.goBack() }
        Act { shown: pageMenu.plain; text: "Forward"; iconName: "chevron-right"; shortcut: "Alt →"; enabled: !!window.view && window.view.canGoForward; onTriggered: window.view.goForward() }
        Act { shown: pageMenu.plain; text: "Load again"; iconName: "rotate-cw"; shortcut: "Ctrl R"; onTriggered: window.view.reload() }
        Act { shown: pageMenu.plain; text: window.marked ? "Let go of the bookmark" : "Keep as a bookmark"; iconName: "star"; shortcut: "Ctrl D"; onTriggered: window.mark() }
        Act { shown: pageMenu.plain; text: "Save the page"; iconName: "download"; onTriggered: window.act(WebEngineView.SavePage) }
        Act { shown: pageMenu.plain; text: "Source of the page"; shortcut: "Ctrl U"; onTriggered: window.open("view-source:" + window.here) }
        MenuSeparator {}
        Act { text: "Developer tools"; shortcut: "F12"; onTriggered: window.inspect() }
    }

    Shortcut { sequence: "Ctrl+T"; onActivated: window.ask(true) }
    Shortcut { sequences: ["Ctrl+L", "Ctrl+K", "F6"]; onActivated: window.ask(false) }
    Shortcut { sequence: "Ctrl+W"; onActivated: window.shut() }
    Shortcut { sequence: "Ctrl+Shift+T"; onActivated: window.reopen() }
    Shortcut { sequence: "Ctrl+N"; onActivated: window.browser.window("", []) }
    Shortcut { sequence: "Ctrl+Shift+N"; onActivated: Quickshell.execDetached(["strix-browser", "--private"]) }
    Shortcut { sequence: "Ctrl+Q"; onActivated: window.browser.quit() }
    Shortcut { sequences: ["Ctrl+Tab", "Ctrl+PgDown"]; onActivated: window.turn(1) }
    Shortcut { sequences: ["Ctrl+Shift+Tab", "Ctrl+PgUp"]; onActivated: window.turn(-1) }
    Shortcut { sequence: "Ctrl+Shift+PgUp"; onActivated: if (!window.held && tabs.count > 0) window.move(window.at, window.at - 1) }
    Shortcut { sequence: "Ctrl+Shift+PgDown"; onActivated: if (!window.held && tabs.count > 0) window.move(window.at, window.at + 1) }
    Instantiator {
        model: 9
        Shortcut {
            required property int index
            sequence: "Ctrl+" + (index + 1)
            onActivated: if (tabs.count > 0) window.show(index === 8 ? tabs.count - 1 : Math.min(index, tabs.count - 1))
        }
    }
    Instantiator {
        model: 9
        Shortcut {
            required property int index
            sequence: "Alt+" + (index + 1)
            onActivated: if (index < window.browser.essentials.count) window.essential(window.browser.essentials.get(index).url)
        }
    }
    Shortcut { sequences: ["Ctrl+R", "F5"]; onActivated: if (window.here !== "") window.view.reload() }
    Shortcut { sequences: ["Ctrl+Shift+R", "Ctrl+F5"]; onActivated: if (window.here !== "") window.view.reloadAndBypassCache() }
    Shortcut { sequence: "Esc"; enabled: window.here !== "" && window.view.loading && !window.finding && !window.asked; onActivated: window.view.stop() }
    Shortcut { sequence: "Alt+Left"; onActivated: if (window.here !== "") window.view.goBack() }
    Shortcut { sequence: "Alt+Right"; onActivated: if (window.here !== "") window.view.goForward() }
    Shortcut { sequence: "Alt+Home"; onActivated: window.home = true }
    Shortcut { sequence: "Ctrl+F"; onActivated: if (window.here !== "") window.find(true) }
    Shortcut { sequence: "Ctrl+D"; onActivated: window.mark() }
    Shortcut { sequence: "Ctrl+Shift+D"; onActivated: window.pin() }
    Shortcut { sequence: "Ctrl+U"; onActivated: if (window.here !== "") window.open("view-source:" + window.here) }
    Shortcut { sequence: "Ctrl+Alt+C"; onActivated: window.narrow = !window.narrow }
    Shortcut { sequence: "Ctrl+,"; onActivated: window.options = !window.options }
    Shortcut { sequences: ["Ctrl++", "Ctrl+="]; onActivated: window.size(0.1) }
    Shortcut { sequence: "Ctrl+-"; onActivated: window.size(-0.1) }
    Shortcut { sequence: "Ctrl+0"; onActivated: window.size(0) }
    Shortcut { sequence: "F12"; onActivated: window.inspect() }
}
