use std::collections::HashMap;
use std::io::{BufRead, Write};
use std::os::unix::net::{UnixListener, UnixStream};
use std::sync::mpsc::{Receiver, Sender};
use std::sync::{Arc, Mutex};

use calloop::channel;
use serde_json::Value;

pub fn spawn_shell_ipc(cmd_tx: channel::Sender<(u64, Value)>, resp: Option<(Sender<(u64, Value)>, Receiver<(u64, Value)>)>) {
    let runtime_dir = std::env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| "/tmp".into());
    let path = format!("{}/mist-shell-ipc.sock", runtime_dir);
    let _ = std::fs::remove_file(&path);
    let listener = match UnixListener::bind(&path) {
        Ok(l) => l,
        Err(e) => { eprintln!("shell ipc bind: {}", e); return; }
    };

    let streams: Arc<Mutex<HashMap<u64, UnixStream>>> = Arc::new(Mutex::new(HashMap::new()));
    let next_id: Arc<Mutex<u64>> = Arc::new(Mutex::new(1));

    let listener = std::sync::Mutex::new(listener);
    let streams2 = streams.clone();
    let next_id2 = next_id.clone();
    let cmd_tx2 = cmd_tx.clone();
    if let Some((_resp_tx, resp_rx)) = resp {
        std::thread::spawn(move || {
            loop {
                if let Ok((id, resp)) = resp_rx.recv() {
                    let map = streams.lock().unwrap();
                    if let Some(stream) = map.get(&id) {
                        let mut s = stream.try_clone().unwrap();
                        let _ = writeln!(s, "{}", serde_json::to_string(&resp).unwrap());
                        let _ = s.flush();
                    }
                }
            }
        });
    }

    std::thread::spawn(move || {
        for stream in listener.lock().unwrap().incoming().filter_map(|r| { if let Err(e) = &r { eprintln!("shell ipc accept: {}", e); } r.ok() }) {
            let id = {
                let mut n = next_id2.lock().unwrap();
                let id = *n;
                *n += 1;
                id
            };
            streams2.lock().unwrap().insert(id, stream.try_clone().unwrap());

            let cmd_tx = cmd_tx2.clone();
            let streams_clone = streams2.clone();
            std::thread::spawn(move || {
                let mut reader = std::io::BufReader::new(stream);
                let mut line = String::new();
                loop {
                    line.clear();
                    match reader.read_line(&mut line) {
                        Ok(0) => break,
                        Ok(_) => {
                            if let Ok(val) = serde_json::from_str::<Value>(line.trim())
                                && cmd_tx.send((id, val)).is_err() { break; }
                        }
                        Err(_) => break,
                    }
                }
                streams_clone.lock().unwrap().remove(&id);
            });
        }
    });
}
