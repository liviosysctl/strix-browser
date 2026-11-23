# strix-browser

The browser of [Strix](https://github.com/liviosysctl/StrixOS): Chromium for the pages, everything
around them drawn with the QML module of [StrixUI](https://github.com/liviosysctl/StrixUI), in the
colours of the session's theme. Its frame follows the Zen browser: everything but the page
stands in a strip down the left side (back and forward, where the page is, the essentials, the
tabs), and the page has the rest of the window. The address is one field that floats over the
page when it is asked for, as the search of the shell floats over the desktop; that search grows
into this window, so both use the same plate, measures and rows.

Essentials are pages kept as buttons at the top of the strip: one press opens the page or goes
to it. While no page is shown the start page stands in its place, with the hour, the
essentials, the bookmarks and what was opened lately; typing there lets the address float. Tabs
and essentials are carried to another place with the pointer; the right button has a menu on a
tab and in a page. What a page says or asks
(alert, confirm, a name and a password) is drawn by the window, not by Qt.

## How it is built

| Part | What it is |
|---|---|
| Pages | Qt WebEngine (Chromium), one view for every tab |
| Windows | QML in `qml/`, run by Quickshell: `Browser.qml` is what the windows share, `BrowserWindow.qml` one window, `Options.qml` the settings |
| Quickshell | The one of nixpkgs with `nix/quickshell-webengine.patch`: a pragma that sets up Qt WebEngine before the application starts, and a hook that asks a service about every request of a page. Only the browser runs this build; the shell of the desktop keeps the plain one |
| Back end | Rust, in `backend/`: the request filter, the history, the bookmarks, the essentials, the pictures of pages, the passwords, the tabs of the last session, the settings. One runs for the session, beside the browsers, and talks to the windows over a Unix socket, one JSON object per line |
| Passwords | A password typed into a page is offered to be kept, and filled in the next time on the same origin. They are kept in the keyring of the session (the Secret Service) and nowhere else; the back end reaches it through `secret-tool` |
| Private windows | A browser of its own (`strix-browser --private`) whose pages leave nothing behind: no cookies and no cache on the disk, no history, no session. The filter still asks |
| Streaming (DRM) | Qt WebEngine uses the Widevine module that Firefox fetches into its profile; the browser brings none of its own |
| Graphics card | `backend --flags` says how Chromium is started: with the setting on, pages are drawn and video is decoded by the graphics card also where Chromium's own list would leave it out |
| Ad blocker | Built in. The back end reads the filter lists uBlock Origin starts with (its own, EasyList, EasyPrivacy, Peter Lowe's) with Brave's engine (`adblock`), answers Qt WebEngine for every request and tells the window what a page should hide. The lists are fetched at the first start and every four days. The Chromium of Qt does not apply the blocking rules of extensions, so uBlock Origin itself cannot do this here, and there are no extensions |

A tab that has not been looked at for five minutes and plays nothing is discarded: Chromium lets go
of its page and loads it again when the tab is chosen. That is where a browser's memory goes.

## Running it

```sh
nix build            # the package: the command strix-browser and its entry for the app search
strix-browser        # a window with an empty tab
strix-browser URL    # a tab for URL, in the browser that already runs if there is one
strix-browser --private [URL]   # the same in a private browser
```

The search of the shell grows into the browser: it starts it with `STRIX_BROWSER_HIDDEN=1`, so the
page loads without a window, and calls `strix-browser --show` once its own panel stands where the
window will be.

It needs the QML module of StrixUI in `QML_IMPORT_PATH` and the theme of the session in
`$XDG_RUNTIME_DIR/strix/theme/tokens.json`, as every session of Strix has them.

## Keys

| Key | What it does |
|---|---|
| Ctrl T | The address, for a page in a new tab |
| Ctrl L, Ctrl K, F6 | The address, to change the page that is shown |
| Ctrl W | Closes what is shown; with nothing open, the window |
| Ctrl Shift T | Brings the last closed tab back |
| Ctrl Tab, Ctrl Shift Tab, Ctrl PgDown, Ctrl PgUp | The next tab, the one before |
| Ctrl 1 to 8, Ctrl 9 | A tab by its place, the last tab |
| Ctrl Shift PgUp, Ctrl Shift PgDown | Carries the tab up, down |
| Alt 1 to 9 | An essential by its place |
| Ctrl Shift D | Keeps the page as an essential, or lets go of it |
| Ctrl D | Keeps the page as a bookmark, or lets go of it |
| Alt Home | The start page |
| Ctrl N | A new window |
| Ctrl Shift N | A private window |
| Ctrl Q | Leaves the browser |
| Ctrl R, F5 | Loads the page again |
| Ctrl Shift R, Ctrl F5 | Loads it again without the kept copy |
| Esc | Stops a page that is loading |
| Alt Left, Alt Right | Back, forward |
| Ctrl F | Finds in the page |
| Ctrl +, Ctrl -, Ctrl 0 | Larger, smaller, the size of the settings |
| Ctrl U | The source of the page |
| Ctrl Alt C | Puts the strip away, and brings it back |
| Ctrl , | The settings, which also list these keys |
| F12 | The developer tools, in a tab |

## What is not there

Sync between machines and extensions. Security fixes of Chromium arrive with the next version of
Qt, later than in Chromium itself.

Commits and releases follow [CONTRIBUTING.md](CONTRIBUTING.md).
