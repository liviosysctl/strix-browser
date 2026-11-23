// One page of the browser: Chromium draws it. A tab holds one, and so does an essential that is
// open. It loads when it is first shown, tells the back end what was opened, hides what the
// filter lists hide, and lets go of itself after a while in the background (Settings): Chromium
// discards it and loads it again when it is chosen. That is where the memory goes in a browser.
import QtQuick
import QtWebEngine
import Strix

WebEngineView {
    id: page

    required property var host
    /// Where it starts; empty for a new tab, which shows the start page until it goes somewhere
    property string address: ""
    /// Loads at once; a tab of the last session waits until it is chosen
    property bool fresh: true
    property bool loaded: false
    /// The developer tools or a page that another one opened took it
    property bool claimed: false
    /// Nothing to show yet: the start page stands in its place
    readonly property bool blank: !claimed && address === "" && url.toString() === ""

    // Chromium draws whole pixels: on a screen with a scale like 1.25 the page takes the whole
    // pixels of its place and no part of one, so nothing of it is stretched or cut at an edge
    readonly property real grain: Screen.devicePixelRatio
    width: Math.floor(parent.width * grain) / grain
    height: Math.floor(parent.height * grain) / grain
    visible: !host.options && !host.starting && host.view === page
    // A page that names no colour of its own counts on white
    backgroundColor: "white"
    zoomFactor: host.browser.settings.zoom

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
    onUrlChanged: if (visible) host.lookMarked()
    // The back end keeps the picture of the page for its host: the start page and the lists show it
    onIconChanged: {
        const picture = icon.toString().replace("image://favicon/", "")
        if (picture !== "" && !host.browser.secret) host.browser.call("icon", { url: url.toString(), icon: picture }, () => host.browser.look())
    }

    onLoadingChanged: info => {
        if (info.status !== WebEngineView.LoadSucceededStatus) return
        const browser = host.browser
        const here = url.toString()
        if (!browser.secret) browser.call("visit", { url: here, title: title })
        // How many requests the filter has blocked by now, for the strip
        browser.call("state", {}, state => browser.take(state))
        // What the lists hide on this page
        browser.call("cosmetic", { url: here }, hide => {
            if (!hide || hide.length === 0) return
            const rule = JSON.stringify(hide.join(",") + "{display:none!important}")
            page.runJavaScript("(function(){const s=document.createElement('style');s.textContent=" + rule + ";document.documentElement.appendChild(s)})()", WebEngineScript.ApplicationWorld)
        })
        if (!browser.settings.passwords) return
        page.watch()
        browser.call("logins", { url: here }, list => {
            // Still the page the logins were asked for
            if (list && list.length > 0 && page.url.toString() === here) page.fillIn(list[0])
        })
    }

    // ---------------------------------------------------------------- passwords
    // A script apart from the page's own (its world) finds the field for the password and the
    // one for the name before it. Filling in writes the kept login into them; watching tells
    // the browser what was typed when a form is sent, on the console of that world, which the
    // page cannot read. The login goes to the keyring only when the person says so.
    readonly property string fields: "const pw=[...document.querySelectorAll('input[type=password]')].find(e=>e.offsetParent!==null)||document.querySelector('input[type=password]');"
        + "let user=null;if(pw){const all=[...(pw.form?pw.form.elements:document.querySelectorAll('input'))];"
        + "for(const e of all){if(e===pw)break;if(e.tagName==='INPUT'&&['text','email','tel'].includes((e.type||'text').toLowerCase()))user=e}}"
    function fillIn(login) {
        const write = "const put=(el,v)=>{Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value').set.call(el,v);"
            + "el.dispatchEvent(new Event('input',{bubbles:true}));el.dispatchEvent(new Event('change',{bubbles:true}))};"
        page.runJavaScript("(function(u,p){" + page.fields + "if(!pw||pw.value)return;" + write + "if(user&&u&&!user.value)put(user,u);put(pw,p)})("
            + JSON.stringify(login.username) + "," + JSON.stringify(login.password) + ")", WebEngineScript.ApplicationWorld)
    }
    function watch() {
        page.runJavaScript("(function(){if(window.strixWatches)return;window.strixWatches=true;"
            + "const tell=()=>{" + page.fields + "if(pw&&pw.value)console.log('\\u0001strix-login'+JSON.stringify({u:user?user.value:'',p:pw.value}))};"
            + "document.addEventListener('submit',tell,true);"
            + "document.addEventListener('keydown',e=>{if(e.key==='Enter'&&e.target&&e.target.tagName==='INPUT')tell()},true);"
            + "document.addEventListener('click',e=>{if(e.target&&e.target.closest&&e.target.closest('button,input[type=submit],[role=button]'))tell()},true)})()",
            WebEngineScript.ApplicationWorld)
    }
    onJavaScriptConsoleMessage: (level, message, line, source) => {
        if (message.startsWith("\u0001strix-login")) host.typed(url.toString(), message.slice(12))
    }

    // What a page opens goes into a tab beside it; a link opened with the middle button or with
    // Ctrl stays in the background
    onNewWindowRequested: request => request.openIn(host.claim(request.destination === WebEngineNewWindowRequest.InNewBackgroundTab))
    // The menu under the right button, what a page says or asks, and the small notes over its
    // parts are drawn by the window, in the look of the system, not by Qt
    onContextMenuRequested: request => {
        request.accepted = true
        host.menu(page, request)
    }
    onJavaScriptDialogRequested: request => {
        request.accepted = true
        host.saying = request
    }
    onAuthenticationDialogRequested: request => {
        request.accepted = true
        host.signing = request
    }
    onTooltipRequested: request => {
        request.accepted = true
        host.note = request.type === TooltipRequest.Show ? { text: request.text, x: request.x, y: request.y } : null
    }
    onLinkHovered: hoveredUrl => host.aim = hoveredUrl.toString()
    onFullScreenRequested: request => {
        request.accept()
        host.full = request.toggleOn
    }
    onPermissionRequested: permission => host.asking = permission

    Timer {
        interval: Math.max(1, page.host.browser.settings.discard) * 60 * 1000
        running: page.host.browser.settings.discard > 0 && page.loaded && !page.visible && !page.recentlyAudible
            && page.lifecycleState !== WebEngineView.LifecycleState.Discarded
        onTriggered: page.lifecycleState = WebEngineView.LifecycleState.Discarded
    }
}
