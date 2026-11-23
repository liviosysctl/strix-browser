//! The request filter. The lists are the ones uBlock Origin starts with; the engine that reads
//! them is Brave's (the crate `adblock`). The lists are fetched when there are none or they are
//! older than four days, and kept in the cache; the browser never waits for that.
//!
//! Qt WebEngine asks over a socket of its own, one line per request,
//! `<type>\t<url>\t<page>\n`, and gets `1\n` (block) or `0\n`. The engine is not made to be
//! shared between threads, so one thread owns it and the others ask it.

use std::fs;
use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::UnixListener;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::mpsc::{Sender, channel};
use std::thread;
use std::time::{Duration, SystemTime};

use adblock::Engine;
use adblock::lists::{FilterFormat, FilterSet, ParseOptions};
use adblock::request::Request;

use crate::Places;

/// The lists uBlock Origin has switched on when it is installed: its own, EasyList, EasyPrivacy
/// and Peter Lowe's servers (in the format of a hosts file)
const LISTS: [(&str, &str, bool); 8] = [
    (
        "ublock-filters",
        "https://ublockorigin.github.io/uAssets/filters/filters.min.txt",
        false,
    ),
    (
        "ublock-badware",
        "https://ublockorigin.github.io/uAssets/filters/badware.min.txt",
        false,
    ),
    (
        "ublock-privacy",
        "https://ublockorigin.github.io/uAssets/filters/privacy.min.txt",
        false,
    ),
    (
        "ublock-unbreak",
        "https://ublockorigin.github.io/uAssets/filters/unbreak.min.txt",
        false,
    ),
    (
        "ublock-quick-fixes",
        "https://ublockorigin.github.io/uAssets/filters/quick-fixes.min.txt",
        false,
    ),
    (
        "easylist",
        "https://ublockorigin.github.io/uAssets/thirdparties/easylist.txt",
        false,
    ),
    (
        "easyprivacy",
        "https://ublockorigin.github.io/uAssets/thirdparties/easyprivacy.txt",
        false,
    ),
    (
        "peter-lowe",
        "https://pgl.yoyo.org/adservers/serverlist.php?hostformat=hosts&showintro=1&mimetype=plaintext",
        true,
    ),
];
const FRESH: Duration = Duration::from_secs(4 * 24 * 60 * 60);

enum Ask {
    Check {
        kind: String,
        url: String,
        page: String,
        answer: Sender<bool>,
    },
    Cosmetic {
        url: String,
        answer: Sender<Vec<String>>,
    },
    /// The lists in the cache changed: read them again
    Reload,
}

/// The filter as the rest of the program sees it
#[derive(Clone)]
pub struct Filter {
    asks: Sender<Ask>,
    lists: PathBuf,
    enabled: Arc<AtomicBool>,
    blocked: Arc<AtomicU64>,
    rules: Arc<AtomicU64>,
    fetching: Arc<AtomicBool>,
}

impl Filter {
    /// Starts the thread that owns the engine, with the lists that are in the cache, and fetches
    /// newer ones beside it when they are due
    pub fn start(places: &Places, enabled: bool) -> Result<Filter, String> {
        let lists = places.cache.join("lists");
        fs::create_dir_all(&lists).map_err(|e| format!("{}: {e}", lists.display()))?;
        let (asks, asked) = channel::<Ask>();
        let filter = Filter {
            asks,
            lists: lists.clone(),
            enabled: Arc::new(AtomicBool::new(enabled)),
            blocked: Arc::new(AtomicU64::new(0)),
            rules: Arc::new(AtomicU64::new(0)),
            fetching: Arc::new(AtomicBool::new(false)),
        };
        let rules = filter.rules.clone();
        thread::spawn(move || {
            let mut engine = build(&lists, &rules);
            for ask in asked {
                match ask {
                    Ask::Check {
                        kind,
                        url,
                        page,
                        answer,
                    } => {
                        let _ = answer.send(blocks(&engine, &kind, &url, &page));
                    }
                    Ask::Cosmetic { url, answer } => {
                        let mut hide: Vec<String> = engine
                            .url_cosmetic_resources(&url)
                            .hide_selectors
                            .into_iter()
                            .collect();
                        hide.sort();
                        let _ = answer.send(hide);
                    }
                    Ask::Reload => engine = build(&lists, &rules),
                }
            }
        });
        if filter.stale() {
            filter.update();
        }
        Ok(filter)
    }

    /// The socket Qt WebEngine asks over; every connection gets a thread
    pub fn listen(&self, socket: &Path) -> Result<(), String> {
        let _ = fs::remove_file(socket);
        let listener =
            UnixListener::bind(socket).map_err(|e| format!("{}: {e}", socket.display()))?;
        let filter = self.clone();
        thread::spawn(move || {
            for stream in listener.incoming().flatten() {
                let filter = filter.clone();
                thread::spawn(move || {
                    let Ok(mut out) = stream.try_clone() else {
                        return;
                    };
                    for line in BufReader::new(stream).lines() {
                        let Ok(line) = line else { return };
                        let mut parts = line.splitn(3, '\t');
                        let (kind, url, page) = (
                            parts.next().unwrap_or(""),
                            parts.next().unwrap_or(""),
                            parts.next().unwrap_or(""),
                        );
                        let answer: &[u8] = if filter.check(kind, url, page) {
                            b"1\n"
                        } else {
                            b"0\n"
                        };
                        if out.write_all(answer).is_err() {
                            return;
                        }
                    }
                });
            }
        });
        Ok(())
    }

    /// Whether a request is blocked. The page itself never is: a blocked address would leave the
    /// tab empty without a word.
    pub fn check(&self, kind: &str, url: &str, page: &str) -> bool {
        if !self.enabled.load(Ordering::Relaxed) || kind == "main_frame" {
            return false;
        }
        let (answer, answered) = channel();
        let ask = Ask::Check {
            kind: kind.into(),
            url: url.into(),
            page: page.into(),
            answer,
        };
        if self.asks.send(ask).is_err() {
            return false;
        }
        let blocked = answered.recv().unwrap_or(false);
        if blocked {
            self.blocked.fetch_add(1, Ordering::Relaxed);
        }
        blocked
    }

    /// What a page should not show: the selectors of the lists for its address
    pub fn cosmetic(&self, url: &str) -> Vec<String> {
        if !self.enabled.load(Ordering::Relaxed) {
            return Vec::new();
        }
        let (answer, answered) = channel();
        if self
            .asks
            .send(Ask::Cosmetic {
                url: url.into(),
                answer,
            })
            .is_err()
        {
            return Vec::new();
        }
        answered.recv().unwrap_or_default()
    }

    pub fn set_enabled(&self, enabled: bool) {
        self.enabled.store(enabled, Ordering::Relaxed);
    }

    pub fn enabled(&self) -> bool {
        self.enabled.load(Ordering::Relaxed)
    }

    /// Requests blocked since the browser started
    pub fn blocked(&self) -> u64 {
        self.blocked.load(Ordering::Relaxed)
    }

    /// Rules read from the lists; 0 until the first lists are there
    pub fn rules(&self) -> u64 {
        self.rules.load(Ordering::Relaxed)
    }

    pub fn fetching(&self) -> bool {
        self.fetching.load(Ordering::Relaxed)
    }

    /// When the lists were fetched last, in seconds since 1970; 0 when there are none
    pub fn fetched(&self) -> u64 {
        fs::metadata(self.lists.join("fetched"))
            .and_then(|meta| meta.modified())
            .ok()
            .and_then(|time| time.duration_since(SystemTime::UNIX_EPOCH).ok())
            .map_or(0, |since| since.as_secs())
    }

    fn stale(&self) -> bool {
        fs::metadata(self.lists.join("fetched"))
            .and_then(|meta| meta.modified())
            .ok()
            .and_then(|time| time.elapsed().ok())
            .is_none_or(|age| age > FRESH)
    }

    /// Fetches every list beside the browser's work and reads them when they are there. A list
    /// that cannot be fetched keeps the one in the cache.
    pub fn update(&self) {
        if self.fetching.swap(true, Ordering::Relaxed) {
            return;
        }
        let filter = self.clone();
        thread::spawn(move || {
            let mut fetched = 0;
            for (name, address, _) in LISTS {
                match fetch(address) {
                    Ok(text) => {
                        let file = filter.lists.join(format!("{name}.txt"));
                        let new = file.with_extension("new");
                        if fs::write(&new, text)
                            .and_then(|()| fs::rename(&new, &file))
                            .is_ok()
                        {
                            fetched += 1;
                        }
                    }
                    Err(message) => eprintln!("backend: {name}: {message}"),
                }
            }
            if fetched > 0 {
                let _ = fs::write(filter.lists.join("fetched"), "");
                let _ = filter.asks.send(Ask::Reload);
            }
            filter.fetching.store(false, Ordering::Relaxed);
        });
    }
}

fn fetch(address: &str) -> Result<String, String> {
    let config = ureq::Agent::config_builder()
        .timeout_global(Some(Duration::from_secs(60)))
        .build();
    let agent: ureq::Agent = config.into();
    let text = agent
        .get(address)
        .call()
        .map_err(|e| e.to_string())?
        .body_mut()
        .with_config()
        .limit(64 * 1024 * 1024)
        .read_to_string()
        .map_err(|e| e.to_string())?;
    // An error page is not a list
    if text.len() < 1000 {
        return Err("too short to be a filter list".into());
    }
    Ok(text)
}

/// The engine from the lists in the cache; an empty one blocks nothing
fn build(lists: &Path, rules: &AtomicU64) -> Engine {
    let mut set = FilterSet::new(false);
    let mut count = 0;
    for (name, _, hosts) in LISTS {
        let Ok(text) = fs::read_to_string(lists.join(format!("{name}.txt"))) else {
            continue;
        };
        count += text.lines().filter(|line| is_rule(line)).count();
        let format = if hosts {
            FilterFormat::Hosts
        } else {
            FilterFormat::Standard
        };
        set.add_filter_list(
            text,
            ParseOptions {
                format,
                ..ParseOptions::default()
            },
        );
    }
    rules.store(count as u64, Ordering::Relaxed);
    Engine::new_with_filter_set(set)
}

/// A line of a list that is a rule: not empty, not a comment, not the header
fn is_rule(line: &str) -> bool {
    let line = line.trim();
    !(line.is_empty()
        || line.starts_with('!')
        || line.starts_with('#') && !line.starts_with("##")
        || line.starts_with('['))
}

fn blocks(engine: &Engine, kind: &str, url: &str, page: &str) -> bool {
    // A request without a page (a download, the address bar) is asked as its own page
    let page = if page.is_empty() { url } else { page };
    match Request::new(url, page, kind, "GET") {
        Ok(request) => engine.check_network_request(&request).should_block(),
        Err(_) => false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn engine(rules: &str) -> Engine {
        let mut set = FilterSet::new(false);
        set.add_filter_list(rules.to_string(), ParseOptions::default());
        Engine::new_with_filter_set(set)
    }

    #[test]
    fn a_rule_blocks_what_it_names_and_an_exception_lets_it_through() {
        let engine =
            engine("||ads.example^\n@@||ads.example/allowed.js\n||tracker.example^$third-party\n");
        let page = "https://news.example/story";
        assert!(blocks(
            &engine,
            "script",
            "https://ads.example/banner.js",
            page
        ));
        assert!(!blocks(
            &engine,
            "script",
            "https://ads.example/allowed.js",
            page
        ));
        assert!(!blocks(
            &engine,
            "script",
            "https://cdn.example/lib.js",
            page
        ));
        // third-party only: the tracker's own pages may load it
        assert!(blocks(
            &engine,
            "image",
            "https://tracker.example/p.gif",
            page
        ));
        assert!(!blocks(
            &engine,
            "image",
            "https://tracker.example/p.gif",
            "https://tracker.example/"
        ));
        // nothing to parse is nothing to block
        assert!(!blocks(&engine, "script", "not an address", page));
    }

    #[test]
    fn the_lists_in_the_cache_become_the_engine() {
        let dir = std::env::temp_dir().join(format!("backend-filter-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        let rules = AtomicU64::new(0);
        let empty = build(&dir, &rules);
        assert_eq!(rules.load(Ordering::Relaxed), 0);
        assert!(!blocks(
            &empty,
            "script",
            "https://ads.example/a.js",
            "https://a.example/"
        ));

        fs::write(
            dir.join("easylist.txt"),
            "||ads.example^\nnews.example##.sponsored\n",
        )
        .unwrap();
        fs::write(dir.join("peter-lowe.txt"), "127.0.0.1 served.example\n").unwrap();
        let engine = build(&dir, &rules);
        assert_eq!(rules.load(Ordering::Relaxed), 3);
        assert!(blocks(
            &engine,
            "script",
            "https://ads.example/a.js",
            "https://a.example/"
        ));
        assert!(blocks(
            &engine,
            "image",
            "https://served.example/x.png",
            "https://a.example/"
        ));
        let hide = engine
            .url_cosmetic_resources("https://news.example/story")
            .hide_selectors;
        assert!(hide.contains(".sponsored"));
    }
}
