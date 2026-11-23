//! The small pictures of pages. The window tells which picture a page brought along; it is
//! fetched once and kept in the cache, one file for each host, so the start page, the
//! essentials and the lists show it without the page being loaded.

use std::fs;
use std::io::Read;
use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime};

use crate::secrets::origin;

/// A kept picture is fetched again after this long
const FRESH: Duration = Duration::from_secs(30 * 24 * 60 * 60);
/// No picture of a page is larger
const LARGEST: u64 = 512 * 1024;

/// The file that holds the picture of the host of `url`
pub fn file(folder: &Path, url: &str) -> Option<PathBuf> {
    let origin = origin(url)?;
    let host = origin.split_once("://")?.1;
    let name: String = host
        .chars()
        .map(|c| {
            if c.is_ascii_alphanumeric() || c == '.' || c == '-' {
                c
            } else {
                '_'
            }
        })
        .collect();
    Some(folder.join(name))
}

/// Fetches the picture at `address` for the page `url`, unless a fresh one is kept
pub fn keep(folder: &Path, url: &str, address: &str) -> Result<(), String> {
    let Some(file) = file(folder, url) else {
        return Ok(());
    };
    if origin(address).is_none() {
        return Ok(());
    }
    let age = fs::metadata(&file)
        .and_then(|data| data.modified())
        .ok()
        .and_then(|time| SystemTime::now().duration_since(time).ok());
    if age.is_some_and(|age| age < FRESH) {
        return Ok(());
    }
    let config = ureq::Agent::config_builder()
        .timeout_global(Some(Duration::from_secs(20)))
        .build();
    let agent: ureq::Agent = config.into();
    let mut picture = Vec::new();
    agent
        .get(address)
        .call()
        .map_err(|e| e.to_string())?
        .body_mut()
        .as_reader()
        .take(LARGEST)
        .read_to_end(&mut picture)
        .map_err(|e| e.to_string())?;
    if picture.is_empty() {
        return Ok(());
    }
    fs::create_dir_all(folder).map_err(|e| format!("{}: {e}", folder.display()))?;
    let new = file.with_extension("new");
    fs::write(&new, picture).map_err(|e| format!("{}: {e}", new.display()))?;
    fs::rename(&new, &file).map_err(|e| format!("{}: {e}", file.display()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_host_has_one_file_and_other_addresses_none() {
        let folder = Path::new("/cache");
        assert_eq!(
            file(folder, "https://Example.org:8080/a?b"),
            Some(PathBuf::from("/cache/example.org_8080"))
        );
        assert_eq!(file(folder, "about:blank"), None);
    }
}
