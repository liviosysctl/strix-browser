# The browser as a package: its QML, the Quickshell that can show web pages, the command that
# starts it and its entry for the app search and for links (http, https).
#
# The QML module of StrixUI (import Strix) is not part of it: on Strix it is in QML_IMPORT_PATH
# for every session. `blocker` is the folder of an unpacked Manifest V3 extension that blocks ads
# (uBlock Origin Lite); without it the browser runs with none.
{
  lib,
  stdenvNoCC,
  writeShellApplication,
  makeDesktopItem,
  quickshell,
  qt6,
  blocker ? null,
}:

let
  # Quickshell sets up Qt WebEngine when a configuration asks for it (pragma
  # EnableQtWebEngineQuick). Only the browser runs this build; the shell of the desktop keeps the
  # plain one and never loads Chromium.
  quickshell-webengine = quickshell.overrideAttrs (old: {
    pname = "quickshell-webengine";
    patches = (old.patches or [ ]) ++ [ ./quickshell-webengine.patch ];
    buildInputs = old.buildInputs ++ [ qt6.qtwebengine ];
  });

  qml = stdenvNoCC.mkDerivation {
    name = "strix-browser-qml";
    src = ../qml;
    dontBuild = true;
    installPhase = "cp -r . $out";
  };

  command = writeShellApplication {
    name = "strix-browser";
    runtimeInputs = [ quickshell-webengine ];
    text = ''
      # One browser for the session: a second start opens its address as a tab in the first
      if qs -p ${qml} ipc call browser tabs >/dev/null 2>&1; then
        exec qs -p ${qml} ipc call browser open "''${1:-}"
      fi
      export STRIX_BROWSER_OPEN="''${1:-}"
      ${lib.optionalString (blocker != null) ''export STRIX_BROWSER_BLOCKER=${blocker}''}
      exec qs -p ${qml}
    '';
  };

  entry = makeDesktopItem {
    name = "strix-browser";
    desktopName = "Browser";
    genericName = "Web Browser";
    exec = "strix-browser %u";
    icon = "web-browser";
    categories = [
      "Network"
      "WebBrowser"
    ];
    mimeTypes = [
      "text/html"
      "x-scheme-handler/http"
      "x-scheme-handler/https"
    ];
    startupWMClass = "strix-browser";
  };
in
stdenvNoCC.mkDerivation {
  pname = "strix-browser";
  version = "0.1.0";
  dontUnpack = true;
  installPhase = ''
    mkdir -p $out/bin $out/share
    ln -s ${lib.getExe command} $out/bin/strix-browser
    ln -s ${entry}/share/applications $out/share/applications
  '';
  passthru = { inherit quickshell-webengine qml; };
  meta = {
    description = "The browser of Strix: Chromium pages in a window drawn with StrixUI";
    homepage = "https://github.com/liviosysctl/strix-browser";
    mainProgram = "strix-browser";
    platforms = lib.platforms.linux;
  };
}
