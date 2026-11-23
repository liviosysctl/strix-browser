//! What the browser keeps and decides outside its window. One process beside the browser:
//!
//! - the request filter: Qt WebEngine asks about every request a page makes, and the filter lists
//!   of uBlock Origin decide (`filter`),
//! - the history, the tabs of the last session and the settings (`store`),
//! - the line to the window: one JSON object per line over a Unix socket, the protocol of every
//!   Strix front end (`talk`).
//!
//! `backend` runs until it is stopped; the command that starts the browser starts and stops it.

mod filter;
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

fn run() -> Result<(), String> {
    let places = Places::find()?;
    for folder in [&places.runtime, &places.config, &places.data, &places.cache] {
        std::fs::create_dir_all(folder).map_err(|e| format!("{}: {e}", folder.display()))?;
    }
    let store = store::Store::open(&places)?;
    let filter = filter::Filter::start(&places, store.settings().blocker)?;
    filter.listen(&places.runtime.join("browser-filter.sock"))?;
    talk::serve(&places.runtime.join("browser.sock"), store, filter)
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
