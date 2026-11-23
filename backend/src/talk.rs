//! The line to the window: a Unix socket, one JSON object per line.
//! `{"id": 1, "method": "state", "params": {}}` is answered by `{"id": 1, "result": …}` or
//! `{"id": 1, "error": "…"}`.
//!
//!   state                    the settings and how the filter stands
//!   set {name: value, …}     change settings; the filter follows `blocker` at once
//!   visit {url, title}       a page was opened (history)
//!   history {text, limit}    the pages that match what is typed
//!   forget                   empty the history
//!   session                  the tabs of the last session
//!   keep {tabs: […]}         the tabs that are open now
//!   cosmetic {url}           what the page should not show (CSS selectors)
//!   lists                    fetch the filter lists again
//!   bookmarks {text, limit}  the bookmarks that match what is typed
//!   bookmark {url, title}    keep the page as a bookmark, or let go of it; answers which it is
//!   bookmarked {url}         whether the page is a bookmark
//!   logins {url}             the logins the keyring has for the page's origin
//!   login {url, username, password}  keep a login in the keyring

use std::fs;
use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::UnixListener;
use std::path::Path;
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

use serde_json::{Value, json};

use crate::filter::Filter;
use crate::store::Store;

pub fn serve(socket: &Path, store: Store, filter: Filter) -> Result<(), String> {
    let _ = fs::remove_file(socket);
    let listener = UnixListener::bind(socket).map_err(|e| format!("{}: {e}", socket.display()))?;
    let store = Arc::new(Mutex::new(store));

    // The windows that are connected. Once there has been one and the last has gone for a
    // while, the back end has nobody left to serve and ends.
    let windows = Arc::new(AtomicUsize::new(0));
    let served = Arc::new(AtomicBool::new(false));
    {
        let (windows, served, socket) = (windows.clone(), served.clone(), socket.to_path_buf());
        thread::spawn(move || {
            let mut alone = 0;
            loop {
                thread::sleep(Duration::from_secs(5));
                if served.load(Ordering::Relaxed) && windows.load(Ordering::Relaxed) == 0 {
                    alone += 5;
                } else {
                    alone = 0;
                }
                if alone >= 20 {
                    let _ = fs::remove_file(&socket);
                    let _ = fs::remove_file(socket.with_file_name("browser-filter.sock"));
                    std::process::exit(0);
                }
            }
        });
    }

    for stream in listener.incoming().flatten() {
        let store = store.clone();
        let filter = filter.clone();
        let windows = windows.clone();
        let served = served.clone();
        thread::spawn(move || {
            let Ok(mut out) = stream.try_clone() else {
                return;
            };
            // A connection that only looks whether somebody answers (a second back end that
            // was started) says nothing and is no window
            let mut counted = false;
            for line in BufReader::new(stream).lines() {
                let Ok(line) = line else { break };
                let Ok(message) = serde_json::from_str::<Value>(&line) else {
                    continue;
                };
                if !counted {
                    counted = true;
                    windows.fetch_add(1, Ordering::Relaxed);
                    served.store(true, Ordering::Relaxed);
                }
                let method = message["method"].as_str().unwrap_or("");
                let reply = match answer(method, &message["params"], &store, &filter) {
                    Ok(result) => json!({ "id": message["id"], "result": result }),
                    Err(error) => json!({ "id": message["id"], "error": error }),
                };
                if writeln!(out, "{reply}").is_err() {
                    break;
                }
            }
            if counted {
                windows.fetch_sub(1, Ordering::Relaxed);
            }
        });
    }
    Ok(())
}

fn answer(
    method: &str,
    params: &Value,
    store: &Mutex<Store>,
    filter: &Filter,
) -> Result<Value, String> {
    let mut store = store.lock().map_err(|_| "the store is broken")?;
    let text = |name: &str| params[name].as_str().unwrap_or("");
    match method {
        "state" => Ok(state(&store, filter)),
        "set" => {
            store.change(params)?;
            filter.set_enabled(store.settings().blocker);
            Ok(state(&store, filter))
        }
        "visit" => {
            store.visit(text("url"), text("title"))?;
            Ok(Value::Null)
        }
        "history" => {
            let limit = params["limit"].as_u64().unwrap_or(50) as usize;
            Ok(json!(store.search(text("text"), limit)))
        }
        "forget" => {
            store.forget()?;
            Ok(Value::Null)
        }
        "session" => Ok(store.session()),
        "keep" => {
            store.keep_session(&params["tabs"])?;
            Ok(Value::Null)
        }
        "cosmetic" => Ok(json!(filter.cosmetic(text("url")))),
        "lists" => {
            filter.update();
            Ok(state(&store, filter))
        }
        "bookmarks" => {
            let limit = params["limit"].as_u64().unwrap_or(50) as usize;
            Ok(json!(store.bookmarks(text("text"), limit)))
        }
        "bookmark" => Ok(json!(store.toggle_bookmark(text("url"), text("title"))?)),
        "bookmarked" => Ok(json!(store.bookmarked(text("url")))),
        "logins" => {
            if !store.settings().passwords {
                return Ok(json!([]));
            }
            // The keyring may ask for its password: nothing else waits for that
            drop(store);
            Ok(json!(crate::secrets::logins(text("url"))))
        }
        "login" => {
            drop(store);
            crate::secrets::keep(text("url"), text("username"), text("password"))?;
            Ok(Value::Null)
        }
        _ => Err(format!("no method {method}")),
    }
}

fn state(store: &Store, filter: &Filter) -> Value {
    json!({
        "settings": store.settings(),
        "filter": {
            "enabled": filter.enabled(),
            "rules": filter.rules(),
            "blocked": filter.blocked(),
            "fetched": filter.fetched(),
            "fetching": filter.fetching(),
        },
    })
}
