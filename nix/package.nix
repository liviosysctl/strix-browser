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
  libsecret,
  runCommand,
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

  # The same window under a path of its own: Quickshell tells its instances apart by the path,
  # so a private browser is not the one a link from outside opens in
  qmlPrivate = runCommand "strix-browser-qml-private" { } "cp -r ${qml} $out";

  command = writeShellApplication {
    name = "strix-browser";
    runtimeInputs = [
      quickshell-webengine
      coreutils
      # secret-tool, through which the back end keeps passwords in the keyring
      libsecret
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
      # --private: a browser of its own that keeps nothing of what is opened in it
      qml=${qml}
      if [ "''${1:-}" = --private ]; then
        shift
        qml=${qmlPrivate}
        export STRIX_BROWSER_PRIVATE=1
      fi

      # One browser of each kind for the session: a second start opens its address as a tab in
      # the first
      if qs -p "$qml" ipc call browser tabs >/dev/null 2>&1; then
        exec qs -p "$qml" ipc call browser open "''${1:-}"
      fi

      # The back end beside the browser: it serves every browser of the session, leaves when
      # another one already runs, and ends by itself after the last window. Qt WebEngine asks it
      # about every request over the socket named here (quickshell-webengine.patch), and it says
      # how Chromium is started (the graphics card, by the settings).
      ${lib.getExe backend} &
      flags=$(${lib.getExe backend} --flags) || flags=""
      export QTWEBENGINE_CHROMIUM_FLAGS="$flags ''${QTWEBENGINE_CHROMIUM_FLAGS:-}"
      export QS_WEBENGINE_REQUEST_FILTER="''${XDG_RUNTIME_DIR:?}/strix/browser-filter.sock"
      export STRIX_BROWSER_OPEN="''${1:-}"
      exec qs -p "$qml"
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
    actions.private = {
      name = "New private window";
      exec = "strix-browser --private";
    };
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
