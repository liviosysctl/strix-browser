//! The passwords typed into pages, kept in the keyring of the session (the Secret Service, on
//! Strix the GNOME keyring, which opens with the login) and nowhere else. The tool of libsecret
//! talks to it: a password goes to it on its input, never as an argument that other programs
//! could read.
//!
//! An entry belongs to an origin (scheme, host and port) and a user name. Only that origin gets
//! it back.

use std::io::Write;
use std::process::{Command, Stdio};

use serde::Serialize;

const SERVICE: &str = "strix-browser";

#[derive(Serialize, PartialEq, Debug)]
pub struct Login {
    pub username: String,
    pub password: String,
}

/// The origin of an address: `https://example.org` for `https://example.org/login?next=1`. Only
/// pages loaded over http or https have one here.
pub fn origin(url: &str) -> Option<String> {
    let (scheme, rest) = url.split_once("://")?;
    if scheme != "https" && scheme != "http" {
        return None;
    }
    let host = rest.split(['/', '?', '#']).next()?;
    // user:password@host is not a host
    let host = host.rsplit('@').next()?;
    if host.is_empty() {
        return None;
    }
    Some(format!("{scheme}://{}", host.to_lowercase()))
}

/// The logins kept for the origin of `url`
pub fn logins(url: &str) -> Vec<Login> {
    let Some(origin) = origin(url) else {
        return Vec::new();
    };
    let found = Command::new("secret-tool")
        .args([
            "search", "--all", "--unlock", "service", SERVICE, "origin", &origin,
        ])
        .output();
    match found {
        Ok(output) => parse(
            &String::from_utf8_lossy(&output.stdout),
            &String::from_utf8_lossy(&output.stderr),
        ),
        Err(_) => Vec::new(),
    }
}

/// Keeps a login for the origin of `url`; one with the same user name is replaced
pub fn keep(url: &str, username: &str, password: &str) -> Result<(), String> {
    let origin = origin(url).ok_or("this page has no origin to keep a password for")?;
    if password.is_empty() {
        return Err("no password".into());
    }
    let host = origin
        .split_once("://")
        .map_or(origin.as_str(), |(_, host)| host);
    let label = if username.is_empty() {
        host.to_string()
    } else {
        format!("{host} ({username})")
    };
    let mut tool = Command::new("secret-tool")
        .args([
            "store", "--label", &label, "service", SERVICE, "origin", &origin, "username", username,
        ])
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .spawn()
        .map_err(|e| format!("secret-tool: {e}"))?;
    if let Some(mut stdin) = tool.stdin.take() {
        stdin
            .write_all(password.as_bytes())
            .map_err(|e| e.to_string())?;
    }
    if tool.wait().map_err(|e| e.to_string())?.success() {
        Ok(())
    } else {
        Err("the keyring did not take the password".into())
    }
}

/// What `secret-tool search` prints: for every entry its secret on the output and its
/// attributes on the error stream (older versions print both on the output), the entries in the
/// same order on both. The n-th secret and the n-th user name belong together.
fn parse(output: &str, errors: &str) -> Vec<Login> {
    let lines = || output.lines().chain(errors.lines());
    let passwords = lines().filter_map(|line| line.strip_prefix("secret = "));
    let mut usernames = lines().filter_map(|line| line.strip_prefix("attribute.username = "));
    let mut logins: Vec<Login> = Vec::new();
    for password in passwords {
        let username = usernames.next().unwrap_or("").to_string();
        if !logins.iter().any(|login| login.username == username) {
            logins.push(Login {
                username,
                password: password.to_string(),
            });
        }
    }
    logins
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_origin_is_scheme_and_host() {
        assert_eq!(
            origin("https://Example.org/login?next=/a").as_deref(),
            Some("https://example.org")
        );
        assert_eq!(
            origin("http://localhost:8080/").as_deref(),
            Some("http://localhost:8080")
        );
        assert_eq!(
            origin("https://user:pw@example.org/").as_deref(),
            Some("https://example.org")
        );
        assert_eq!(origin("file:///home/a.html"), None);
        assert_eq!(origin("about:blank"), None);
        assert_eq!(origin("https:///nothing"), None);
    }

    #[test]
    fn the_tool_s_answer_becomes_logins() {
        let output = "[/1]\nlabel = example.org (ada)\nsecret = first pass = word\n\
                      created = 2026-11-23 17:00:00\nschema = org.freedesktop.Secret.Generic\n\
                      [/2]\nlabel = example.org\nsecret = second\n";
        let errors = "attribute.origin = https://example.org\nattribute.service = strix-browser\n\
                      attribute.username = ada\nattribute.origin = https://example.org\n\
                      attribute.service = strix-browser\nattribute.username = \n";
        let logins = vec![
            Login {
                username: "ada".into(),
                password: "first pass = word".into(),
            },
            Login {
                username: String::new(),
                password: "second".into(),
            },
        ];
        assert_eq!(parse(output, errors), logins);
        // an older tool prints everything on the output
        assert_eq!(parse(&format!("{output}{errors}"), ""), logins);
        assert!(parse("", "").is_empty());
        // an entry without a secret (the keyring stayed locked) is no login
        assert!(parse("[/1]\nlabel = a\n", "attribute.username = ada\n").is_empty());
    }
}
