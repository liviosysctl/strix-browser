# The browser as a package: its QML, the Quickshell that can show web pages, the command that
# starts it and its entry for the app search and for links (http, https).
#
# The QML module of StrixUI (import Strix) is not part of it: on Strix it is in QML_IMPORT_PATH
# for every session.
{
  lib,
  stdenvNoCC,
  writeShellApplication,
  makeDesktopItem,
  quickshell,
  qt6,
  coreutils,
  rustPlatform,
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

  # The back end (backend/): the request filter, the history, the session, the settings. Its
  # unit tests run while building.
  backend = rustPlatform.buildRustPackage {
    pname = "strix-browser-backend";
    inherit ((lib.importTOML ../backend/Cargo.toml).package) version;
    src = lib.fileset.toSource {
      root = ../backend;
      fileset = lib.fileset.unions [
        ../backend/Cargo.toml
        ../backend/Cargo.lock
        ../backend/src
      ];
    };
    cargoLock.lockFile = ../backend/Cargo.lock;
    meta.mainProgram = "backend";
  };

  qml = stdenvNoCC.mkDerivation {
    name = "strix-browser-qml";
    src = ../qml;
    dontBuild = true;
    installPhase = "cp -r . $out";
  };

  command = writeShellApplication {
    name = "strix-browser";
    runtimeInputs = [
      quickshell-webengine
      coreutils
    ];
    text = ''
      # --show: the window of a browser that was started hidden (STRIX_BROWSER_HIDDEN), as soon
      # as that browser answers
      if [ "''${1:-}" = --show ]; then
        for _ in $(seq 50); do
          if qs -p ${qml} ipc call browser reveal >/dev/null 2>&1; then exit 0; fi
          sleep 0.1
        done
        exit 1
      fi
      # One browser for the session: a second start opens its address as a tab in the first
      if qs -p ${qml} ipc call browser tabs >/dev/null 2>&1; then
        exec qs -p ${qml} ipc call browser open "''${1:-}"
      fi

      # The back end beside the browser, for as long as the browser runs. Qt WebEngine asks it
      # about every request over the socket named here (quickshell-webengine.patch).
      runtime="''${XDG_RUNTIME_DIR:?}/strix"
      ${lib.getExe backend} &
      backend=$!
      trap 'kill "$backend" 2>/dev/null || true' EXIT
      export QS_WEBENGINE_REQUEST_FILTER="$runtime/browser-filter.sock"
      export STRIX_BROWSER_OPEN="''${1:-}"
      qs -p ${qml}
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
      "application/xhtml+xml"
      "application/pdf"
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
  passthru = { inherit quickshell-webengine qml backend; };
  meta = {
    description = "The browser of Strix: Chromium pages in a window drawn with StrixUI";
    homepage = "https://github.com/liviosysctl/strix-browser";
    mainProgram = "strix-browser";
    platforms = lib.platforms.linux;
  };
}
