//! What the browser keeps between two sessions: the settings, the history, the bookmarks, the
//! essentials and the tabs that were open. Plain files: settings.json in the config folder,
//! history.json, bookmarks.json, essentials.json and session.json in the data folder. Every
//! change is written at once, to a new file that then takes the old one's place.

use std::fs;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Serialize};

use crate::{Places, icons};

/// The pages kept in the history, newest first
const HISTORY: usize = 5000;

#[derive(Clone, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct Settings {
    /// The address a search is sent to, with %s for the words
    pub search: String,
    /// What a new tab shows: empty for nothing, else an address
    pub home: String,
    /// The request filter is on
    pub blocker: bool,
    /// Open the tabs of the last session when the browser starts
    pub restore: bool,
    /// Minutes until a tab in the background lets go of its page; 0 for never
    pub discard: u32,
    /// Where downloads go; empty for the Downloads folder
    pub downloads: String,
    /// How large pages are shown, 1 for as they are
    pub zoom: f64,
    /// Keep the history
    pub history: bool,
    /// Draw pages and decode video with the graphics card; read when the browser starts
    pub gpu: bool,
    /// Offer to keep the passwords typed into pages, and fill them in
    pub passwords: bool,
}

impl Default for Settings {
    fn default() -> Settings {
        Settings {
            search: "https://duckduckgo.com/?q=%s".into(),
            home: String::new(),
            blocker: true,
            restore: true,
            discard: 5,
            downloads: String::new(),
            zoom: 1.0,
            history: true,
            gpu: true,
            passwords: true,
        }
    }
}

#[derive(Clone, Serialize, Deserialize, PartialEq, Debug)]
pub struct Page {
    pub url: String,
    #[serde(default)]
    pub title: String,
    /// When it was last opened, in seconds since 1970
    #[serde(default)]
    pub at: u64,
    /// How often it was opened
    #[serde(default)]
    pub visits: u32,
    /// Its small picture, as a file in the cache: said to the window, never kept
    #[serde(default, skip_deserializing, skip_serializing_if = "String::is_empty")]
    pub icon: String,
}

pub struct Store {
    settings_file: PathBuf,
    history_file: PathBuf,
    session_file: PathBuf,
    bookmarks_file: PathBuf,
    essentials_file: PathBuf,
    /// Where the small pictures of pages are kept (icons.rs)
    pub icons: PathBuf,
    settings: Settings,
    history: Vec<Page>,
    bookmarks: Vec<Page>,
    essentials: Vec<Page>,
}

impl Store {
    pub fn open(places: &Places) -> Result<Store, String> {
        let settings_file = places.config.join("settings.json");
        let history_file = places.data.join("history.json");
        let bookmarks_file = places.data.join("bookmarks.json");
        let essentials_file = places.data.join("essentials.json");
        Ok(Store {
            icons: places.cache.join("icons"),
            essentials: read(&essentials_file).unwrap_or_default(),
            essentials_file,
            bookmarks: read(&bookmarks_file).unwrap_or_default(),
            bookmarks_file,
            settings: read(&settings_file).unwrap_or_default(),
            history: read(&history_file).unwrap_or_default(),
            session_file: places.data.join("session.json"),
            settings_file,
            history_file,
        })
    }

    /// The pages with the pictures the cache has for them
    pub fn pictured(&self, mut pages: Vec<Page>) -> Vec<Page> {
        for page in &mut pages {
            if let Some(file) = icons::file(&self.icons, &page.url).filter(|file| file.exists()) {
                page.icon = format!("file://{}", file.display());
            }
        }
        pages
    }

    pub fn settings(&self) -> &Settings {
        &self.settings
    }

    /// Lays the given values over the settings and keeps them; what is not a setting or has the
    /// wrong type is an error and changes nothing
    pub fn change(&mut self, values: &serde_json::Value) -> Result<(), String> {
        let mut all = serde_json::to_value(&self.settings).map_err(|e| e.to_string())?;
        let (Some(all_map), Some(values)) = (all.as_object_mut(), values.as_object()) else {
            return Err("settings are an object".into());
        };
        for (name, value) in values {
            if !all_map.contains_key(name) {
                return Err(format!("no setting {name}"));
            }
            all_map.insert(name.clone(), value.clone());
        }
        self.settings = serde_json::from_value(all).map_err(|e| e.to_string())?;
        write(&self.settings_file, &self.settings)
    }

    /// A page was opened: it goes to the front of the history, once
    pub fn visit(&mut self, url: &str, title: &str) -> Result<(), String> {
        if !self.settings.history || !(url.starts_with("http://") || url.starts_with("https://")) {
            return Ok(());
        }
        let visits = match self.history.iter().position(|page| page.url == url) {
            Some(index) => self.history.remove(index).visits,
            None => 0,
        };
        self.history.insert(
            0,
            Page {
                url: url.into(),
                title: title.into(),
                at: now(),
                visits: visits + 1,
                icon: String::new(),
            },
        );
        self.history.truncate(HISTORY);
        write(&self.history_file, &self.history)
    }

    /// The pages whose address or title holds every word, the ones opened most often first when
    /// something is typed, else the newest first
    pub fn search(&self, text: &str, limit: usize) -> Vec<Page> {
        let words = words(text);
        let mut hits: Vec<&Page> = self
            .history
            .iter()
            .filter(|page| holds(page, &words))
            .collect();
        if !words.is_empty() {
            hits.sort_by(|a, b| b.visits.cmp(&a.visits).then(b.at.cmp(&a.at)));
        }
        hits.into_iter().take(limit).cloned().collect()
    }

    /// The bookmarks that hold every word, in the order they were made
    pub fn bookmarks(&self, text: &str, limit: usize) -> Vec<Page> {
        let words = words(text);
        self.bookmarks
            .iter()
            .filter(|page| holds(page, &words))
            .take(limit)
            .cloned()
            .collect()
    }

    pub fn bookmarked(&self, url: &str) -> bool {
        self.bookmarks.iter().any(|page| page.url == url)
    }

    /// Keeps a page as a bookmark, or lets go of it when it is one; says which it is now
    pub fn toggle_bookmark(&mut self, url: &str, title: &str) -> Result<bool, String> {
        let kept = match self.bookmarks.iter().position(|page| page.url == url) {
            Some(index) => {
                self.bookmarks.remove(index);
                false
            }
            None => {
                self.bookmarks.push(Page {
                    url: url.into(),
                    title: title.into(),
                    at: now(),
                    visits: 0,
                    icon: String::new(),
                });
                true
            }
        };
        write(&self.bookmarks_file, &self.bookmarks)?;
        Ok(kept)
    }

    /// The pages that stand as buttons over the tabs and on the start page, in the order they
    /// were kept
    pub fn essentials(&self) -> &[Page] {
        &self.essentials
    }

    /// Keeps a page as an essential, or lets go of it when it is one
    pub fn toggle_essential(&mut self, url: &str, title: &str) -> Result<(), String> {
        match self.essentials.iter().position(|page| page.url == url) {
            Some(index) => {
                self.essentials.remove(index);
            }
            None => self.essentials.push(Page {
                url: url.into(),
                title: title.into(),
                at: now(),
                visits: 0,
                icon: String::new(),
            }),
        }
        write(&self.essentials_file, &self.essentials)
    }

    pub fn forget(&mut self) -> Result<(), String> {
        self.history.clear();
        write(&self.history_file, &self.history)
    }

    /// The tabs that are open, kept for the next start
    pub fn keep_session(&self, tabs: &serde_json::Value) -> Result<(), String> {
        write(&self.session_file, tabs)
    }

    /// The tabs of the last session, when they are wanted back
    pub fn session(&self) -> serde_json::Value {
        if !self.settings.restore {
            return serde_json::Value::Array(Vec::new());
        }
        read(&self.session_file).unwrap_or_else(|| serde_json::Value::Array(Vec::new()))
    }
}

fn words(text: &str) -> Vec<String> {
    text.split_whitespace().map(str::to_lowercase).collect()
}

/// The address or the title of the page holds every word
fn holds(page: &Page, words: &[String]) -> bool {
    let url = page.url.to_lowercase();
    let title = page.title.to_lowercase();
    words
        .iter()
        .all(|word| url.contains(word) || title.contains(word))
}

fn now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |since| since.as_secs())
}

fn read<T: for<'a> Deserialize<'a>>(file: &Path) -> Option<T> {
    serde_json::from_str(&fs::read_to_string(file).ok()?).ok()
}

fn write<T: Serialize>(file: &Path, value: &T) -> Result<(), String> {
    let text = serde_json::to_string_pretty(value).map_err(|e| e.to_string())?;
    let new = file.with_extension("new");
    fs::write(&new, text + "\n")
        .and_then(|()| fs::rename(&new, file))
        .map_err(|e| format!("{}: {e}", file.display()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn store(name: &str) -> Store {
        let dir = std::env::temp_dir().join(format!("backend-store-{name}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        Store::open(&Places {
            runtime: dir.clone(),
            config: dir.clone(),
            data: dir.clone(),
            cache: dir,
        })
        .unwrap()
    }

    #[test]
    fn settings_change_one_by_one_and_stay() {
        let mut store = store("settings");
        assert!(store.settings().blocker);
        store
            .change(&json!({ "blocker": false, "discard": 15 }))
            .unwrap();
        assert!(!store.settings().blocker);
        assert_eq!(store.settings().discard, 15);
        assert_eq!(store.settings().search, "https://duckduckgo.com/?q=%s");
        // not a setting, or not its type: nothing changes
        assert!(store.change(&json!({ "nope": 1 })).is_err());
        assert!(store.change(&json!({ "discard": "soon" })).is_err());
        assert_eq!(store.settings().discard, 15);
        let again: Settings = read(&store.settings_file).unwrap();
        assert_eq!(again.discard, 15);
    }

    #[test]
    fn the_history_keeps_a_page_once_and_finds_it_by_its_words() {
        let mut store = store("history");
        store
            .visit("https://nixos.org/manual", "NixOS Manual")
            .unwrap();
        store
            .visit("https://example.org/", "Example Domain")
            .unwrap();
        store
            .visit("https://nixos.org/manual", "NixOS Manual")
            .unwrap();
        store.visit("about:blank", "").unwrap();
        assert_eq!(store.history.len(), 2);
        assert_eq!(store.history[0].visits, 2);
        assert_eq!(store.search("", 10)[0].url, "https://nixos.org/manual");
        assert_eq!(store.search("example dom", 10).len(), 1);
        assert_eq!(store.search("NIX manual", 10)[0].title, "NixOS Manual");
        assert!(store.search("nothing", 10).is_empty());
        store.change(&json!({ "history": false })).unwrap();
        store.visit("https://private.example/", "Private").unwrap();
        assert_eq!(store.history.len(), 2);
        store.forget().unwrap();
        assert!(store.search("", 10).is_empty());
    }

    #[test]
    fn a_bookmark_is_kept_once_and_let_go_by_the_same_step() {
        let mut store = store("bookmarks");
        assert!(
            store
                .toggle_bookmark("https://nixos.org/", "NixOS")
                .unwrap()
        );
        assert!(
            store
                .toggle_bookmark("https://example.org/", "Example Domain")
                .unwrap()
        );
        assert!(store.bookmarked("https://nixos.org/"));
        assert_eq!(store.bookmarks("", 10).len(), 2);
        assert_eq!(store.bookmarks("exam", 10)[0].url, "https://example.org/");
        assert!(
            !store
                .toggle_bookmark("https://nixos.org/", "NixOS")
                .unwrap()
        );
        assert!(!store.bookmarked("https://nixos.org/"));
        let again: Vec<Page> = read(&store.bookmarks_file).unwrap();
        assert_eq!(again.len(), 1);
    }

    #[test]
    fn an_essential_is_kept_in_its_order_and_let_go_by_the_same_step() {
        let mut store = store("essentials");
        store
            .toggle_essential("https://nixos.org/", "NixOS")
            .unwrap();
        store
            .toggle_essential("https://example.org/", "Example Domain")
            .unwrap();
        assert_eq!(store.essentials()[1].url, "https://example.org/");
        store
            .toggle_essential("https://nixos.org/", "NixOS")
            .unwrap();
        assert_eq!(store.essentials().len(), 1);
        let again: Vec<Page> = read(&store.essentials_file).unwrap();
        assert_eq!(again[0].title, "Example Domain");
    }

    #[test]
    fn the_session_comes_back_when_it_is_wanted() {
        let mut store = store("session");
        assert_eq!(store.session(), json!([]));
        store
            .keep_session(&json!([{ "url": "https://example.org/" }]))
            .unwrap();
        assert_eq!(store.session()[0]["url"], "https://example.org/");
        store.change(&json!({ "restore": false })).unwrap();
        assert_eq!(store.session(), json!([]));
    }
}
