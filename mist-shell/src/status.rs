use std::fs;
use std::sync::Mutex;

#[derive(Clone, Debug, Default, PartialEq)]
pub struct SystemStatus {
    pub battery: Option<u8>,
    pub battery_charging: bool,
    pub network_connected: bool,
    pub volume_muted: bool,
}

pub fn poll_status() -> SystemStatus {
    let (battery, charging) = poll_battery();
    SystemStatus {
        battery,
        battery_charging: charging,
        network_connected: poll_network(),
        volume_muted: poll_volume_zbus().unwrap_or(false),
    }
}

fn poll_battery() -> (Option<u8>, bool) {
    let base = "/sys/class/power_supply";
    let Ok(dir) = fs::read_dir(base) else { return (None, false) };
    for entry in dir.flatten() {
        let name = entry.file_name();
        let n = name.to_string_lossy();
        if !n.starts_with("BAT") && !n.starts_with("bat") { continue }
        let path = entry.path();
        let cap = fs::read_to_string(path.join("capacity")).ok()
            .and_then(|s| s.trim().parse::<u8>().ok());
        let charging = fs::read_to_string(path.join("status")).ok()
            .map(|s| s.trim() == "Charging")
            .unwrap_or(false);
        return (cap, charging);
    }
    (None, false)
}

fn poll_network() -> bool {
    let Ok(dir) = fs::read_dir("/sys/class/net") else { return false };
    for entry in dir.flatten() {
        let path = entry.path();
        let name = entry.file_name();
        let n = name.to_string_lossy();
        if n == "lo" { continue }
        let carrier = path.join("carrier");
        if let Ok(c) = fs::read_to_string(&carrier) {
            if c.trim() == "1" { return true }
        }
    }
    false
}

struct PulseState {
    conn: zbus::blocking::Connection,
    sink_path: String,
}

static PULSE: Mutex<Option<PulseState>> = Mutex::new(None);

/// Query PulseAudio default sink mute state via D-Bus.
/// Returns `None` if PulseAudio D-Bus is unavailable (not running, no session bus).
/// Connection + sink path are cached after first successful query.
fn poll_volume_zbus() -> Option<bool> {
    let mut guard = PULSE.lock().ok()?;
    let state = match guard.as_ref() {
        Some(s) => s,
        None => {
            let conn = zbus::blocking::Connection::session().ok()?;
            let server_info = conn.call_method(
                Some("org.PulseAudio1"),
                "/org/pulseaudio/core1",
                Some("org.PulseAudio1.Core"),
                "GetSinks",
                &(),
            ).ok()?;
            let sinks: Vec<zbus::zvariant::OwnedObjectPath> = server_info.body().deserialize().ok()?;
            let path_str = sinks.first()?.to_string();
            *guard = Some(PulseState { conn, sink_path: path_str });
            guard.as_ref().unwrap()
        }
    };
    let msg = state.conn.call_method(
        Some("org.PulseAudio1"),
        state.sink_path.as_str(),
        Some("org.freedesktop.DBus.Properties"),
        "Get",
        &("org.PulseAudio1.Sink", "Mute"),
    ).ok()?;
    let body = msg.body();
    let prop: zbus::zvariant::Value = body.deserialize().ok()?;
    let muted: bool = prop.downcast().ok()?;
    Some(muted)
}
