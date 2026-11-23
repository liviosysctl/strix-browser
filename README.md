# strix-browser

The browser of [Strix](https://github.com/liviosysctl/StrixOS): Chromium for the pages, everything
around them drawn with the QML module of [StrixUI](https://github.com/liviosysctl/StrixUI), in the
colours of the session's theme. Tabs stand down the left side, the address over the page. The
search of the shell grows into this window, so both use the same plate, measures and rows.

## How it is built

| Part | What it is |
|---|---|
| Pages | Qt WebEngine (Chromium), one view for every tab |
| Window | QML in `qml/`, run by Quickshell: `shell.qml` and `Browser.qml` |
| Quickshell | The one of nixpkgs with `nix/quickshell-webengine.patch`: a pragma that sets up Qt WebEngine before the application starts. Only the browser runs this build; the shell of the desktop keeps the plain one |
| Backend | Rust, not there yet: history, the session that comes back, suggestions for the address |
| Ad blocker | One extension, loaded and switched on by the browser itself (uBlock Origin Lite, Manifest V3). There are no other extensions and no way to add one |

A tab that has not been looked at for five minutes and plays nothing is discarded: Chromium lets go
of its page and loads it again when the tab is chosen. That is where a browser's memory goes.

## Running it

```sh
nix build            # the package: the command strix-browser and its entry for the app search
strix-browser        # a window with an empty tab
strix-browser URL    # a tab for URL, in the browser that already runs if there is one
```

It needs the QML module of StrixUI in `QML_IMPORT_PATH` and the theme of the session in
`$XDG_RUNTIME_DIR/strix/theme/tokens.json`, as every session of Strix has them.

## Keys

| Key | What it does |
|---|---|
| Ctrl T | A new tab |
| Ctrl W | Closes the tab |
| Ctrl Tab, Ctrl Shift Tab | The next tab, the one before |
| Ctrl L | The address |
| Ctrl R | Loads the page again |
| Alt Left, Alt Right | Back, forward |

## What is not there

Sync, a password manager, DRM for streaming services, more than one window, private tabs. Security
fixes of Chromium arrive with the next version of Qt, later than in Chromium itself.

Commits and releases follow [CONTRIBUTING.md](CONTRIBUTING.md).
