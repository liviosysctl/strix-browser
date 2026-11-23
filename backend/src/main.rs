//! What the browser keeps and decides outside its window. One process beside the browser:
//!
//! - the request filter: Qt WebEngine asks about every request a page makes, and the filter lists
//!   of uBlock Origin decide (`filter`),
//! - the history, the bookmarks, the essentials, the tabs of the last session and the settings
//!   (`store`), the small pictures of pages (`icons`),
//! - the line to the window: one JSON object per line over a Unix socket, the protocol of every
//!   Strix front end (`talk`).
//!
//! `backend` serves every browser of the session, the usual one and private windows: a second
//! one that is started finds the first and leaves. It ends by itself a while after the last
//! browser has gone. `backend --flags` only prints what Chromium is started with, by the settings.

mod filter;
mod icons;
mod secrets;
mod store;
mod talk;

use std::path::PathBuf;
use std::process::ExitCode;

/// The folders of the browser, by the rules of XDG
pub struct Places {
    /// The sockets: `$XDG_RUNTIME_DIR/strix`, where every Strix front end looks for its back end
    pub runtime: PathBuf,
    /// The settings
    pub config: PathBuf,
    /// The history and the last session
    pub data: PathBuf,
    /// The filter lists and the filter built from them
    pub cache: PathBuf,
}

impl Places {
    fn find() -> Result<Places, String> {
        let home = PathBuf::from(std::env::var_os("HOME").ok_or("HOME is not set")?);
        let dir = |variable: &str, fallback: &str| {
            std::env::var_os(variable)
                .filter(|value| !value.is_empty())
                .map(PathBuf::from)
                .unwrap_or_else(|| home.join(fallback))
        };
        let runtime = std::env::var_os("XDG_RUNTIME_DIR")
            .filter(|value| !value.is_empty())
            .map(PathBuf::from)
            .ok_or("XDG_RUNTIME_DIR is not set")?;
        Ok(Places {
            runtime: runtime.join("strix"),
            config: dir("XDG_CONFIG_HOME", ".config").join("strix-browser"),
            data: dir("XDG_DATA_HOME", ".local/share").join("strix-browser"),
            cache: dir("XDG_CACHE_HOME", ".cache").join("strix-browser"),
        })
    }
}

/// What Chromium is told when the browser starts: with the graphics card switched on in the
/// settings, to use it for drawing pages and for video also where its own list of known
/// trouble would leave it out
fn flags(settings: &store::Settings) -> String {
    if !settings.gpu {
        return "--disable-gpu".into();
    }
    [
        "--ignore-gpu-blocklist",
        "--enable-gpu-rasterization",
        "--enable-zero-copy",
        "--enable-features=AcceleratedVideoDecodeLinuxGL,AcceleratedVideoDecodeLinuxZeroCopyGL,VaapiIgnoreDriverChecks",
    ]
    .join(" ")
}

fn run() -> Result<(), String> {
    let places = Places::find()?;
    if std::env::args().nth(1).as_deref() == Some("--flags") {
        let settings = store::Store::open(&places).map(|store| store.settings().clone())?;
        println!("{}", flags(&settings));
        return Ok(());
    }
    // One back end for the session: another one that answers is the one
    let socket = places.runtime.join("browser.sock");
    if std::os::unix::net::UnixStream::connect(&socket).is_ok() {
        return Ok(());
    }
    for folder in [&places.runtime, &places.config, &places.data, &places.cache] {
        std::fs::create_dir_all(folder).map_err(|e| format!("{}: {e}", folder.display()))?;
    }
    let store = store::Store::open(&places)?;
    let filter = filter::Filter::start(&places, store.settings().blocker)?;
    filter.listen(&places.runtime.join("browser-filter.sock"))?;
    talk::serve(&socket, store, filter)
}

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(message) => {
            eprintln!("backend: {message}");
            ExitCode::FAILURE
        }
    }
}
