use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::UnixStream;
use std::time::Duration;

use calloop::channel;

use crate::state::{Tag, WsList};

fn parse_event(line: &str) -> Option<WsList> {
    let v: serde_json::Value = serde_json::from_str(line).ok()?;
    let workspaces = v.get("WorkspacesChanged")?.get("workspaces")?.as_array()?;

    let mut list = WsList::new();
    for ws in workspaces {
        let name = ws["name"].as_str()
            .filter(|s| !s.is_empty())
            .map(|s| s.to_string())
            .or_else(|| ws["idx"].as_u64().map(|n| n.to_string()))
            .unwrap_or_else(|| "?".to_string());
        let tag = Tag {
            active: ws["is_active"].as_bool().unwrap_or(false),
            urgent: ws["is_urgent"].as_bool().unwrap_or(false),
            occupied: ws["active_window_id"].as_u64().is_some() || ws["is_active"].as_bool().unwrap_or(false),
        };
        list.push((name, tag));
    }
    if list.is_empty() { return None }
    Some(list)
}

pub fn spawn_poller(sender: channel::Sender<WsList>) {
    std::thread::spawn(move || {
        let mut delay = Duration::from_millis(100);
        loop {
            let path = match std::env::var("NIRI_SOCKET") {
                Ok(p) => p,
                Err(_) => { std::thread::sleep(delay); delay = (delay * 2).min(Duration::from_secs(30)); continue; }
            };
            let stream = match UnixStream::connect(&path) {
                Ok(s) => { delay = Duration::from_millis(100); s }
                Err(_) => { std::thread::sleep(delay); delay = (delay * 2).min(Duration::from_secs(30)); continue; }
            };
            let _ = (&stream).write_all(b"\"EventStream\"\n");
            for line in BufReader::new(&stream).lines() {
                let Ok(line) = line else { break };
                if let Some(list) = parse_event(&line) && sender.send(list).is_err() { return }
            }
            std::thread::sleep(Duration::from_millis(200));
        }
    });
}

pub fn focus_workspace(name: &str) {
    let _ = std::process::Command::new("niri")
        .args(["msg", "action", "focus-workspace", name])
        .spawn();
}
