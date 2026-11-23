// The browser of Strix: Chromium (Qt WebEngine) for the pages, everything around them drawn with
// the QML module of StrixUI, in the colours of the session's theme. It runs in a Quickshell of its
// own (nix/quickshell-webengine.patch adds the pragma below), apart from the shell of the desktop:
//   qs -p <this folder>
// A second start hands its address to the one that runs (ipc: browser open <address>).
//@ pragma EnableQtWebEngineQuick
//@ pragma AppId strix-browser
import QtQuick
import Quickshell
import Strix
import Strix.Shell

ShellRoot {
    ThemeFile { path: Quickshell.env("XDG_RUNTIME_DIR") + "/strix/theme/tokens.json" }

    Browser {}
}
