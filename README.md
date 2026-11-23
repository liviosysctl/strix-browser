# strix-browser

The browser of [Strix](https://github.com/liviosysctl/StrixOS): Chromium for the pages, everything
around them drawn with the QML module of [StrixUI](https://github.com/liviosysctl/StrixUI), in the
colours of the session's theme. Tabs stand down the left side, the address over the page. The
search of the shell grows into this window, so both use the same plate, measures and rows.

## How it is built

| Part | What it is |
|---|---|
| Pages | Qt WebEngine (Chromium), one view for every tab |
| Window | QML in `qml/`, run by Quickshell: `shell.qml`, `Browser.qml` and the settings in `Options.qml` |
| Quickshell | The one of nixpkgs with `nix/quickshell-webengine.patch`: a pragma that sets up Qt WebEngine before the application starts, and a hook that asks a service about every request of a page. Only the browser runs this build; the shell of the desktop keeps the plain one |
| Back end | Rust, in `backend/`: the request filter, the history, the tabs of the last session, the settings. It runs beside the browser and talks to the window over a Unix socket, one JSON object per line |
| Ad blocker | Built in. The back end reads the filter lists uBlock Origin starts with (its own, EasyList, EasyPrivacy, Peter Lowe's) with Brave's engine (`adblock`), answers Qt WebEngine for every request and tells the window what a page should hide. The lists are fetched at the first start and every four days. The Chromium of Qt does not apply the blocking rules of extensions, so uBlock Origin itself cannot do this here, and there are no extensions |

A tab that has not been looked at for five minutes and plays nothing is discarded: Chromium lets go
of its page and loads it again when the tab is chosen. That is where a browser's memory goes.

## Running it

```sh
nix build            # the package: the command strix-browser and its entry for the app search
strix-browser        # a window with an empty tab
strix-browser URL    # a tab for URL, in the browser that already runs if there is one
```

The search of the shell grows into the browser: it starts it with `STRIX_BROWSER_HIDDEN=1`, so the
page loads without a window, and calls `strix-browser --show` once its own panel stands where the
window will be.

It needs the QML module of StrixUI in `QML_IMPORT_PATH` and the theme of the session in
`$XDG_RUNTIME_DIR/strix/theme/tokens.json`, as every session of Strix has them.

## Keys

| Key | What it does |
|---|---|
| Ctrl T | A new tab |
| Ctrl W | Closes the tab |
| Ctrl Shift T | Brings the last closed tab back |
| Ctrl Tab, Ctrl Shift Tab | The next tab, the one before |
| Ctrl L | The address |
| Ctrl R, F5 | Loads the page again |
| Alt Left, Alt Right | Back, forward |
| Ctrl F | Finds in the page |
| Ctrl +, Ctrl -, Ctrl 0 | Larger, smaller, the size of the settings |
| Ctrl , | The settings |
| F12 | The developer tools, in a tab |

## What is not there

Bookmarks, sync, a password manager, DRM for streaming services, more than one window, private
tabs, extensions. Security fixes of Chromium arrive with the next version of Qt, later than in
Chromium itself.

Commits and releases follow [CONTRIBUTING.md](CONTRIBUTING.md).
