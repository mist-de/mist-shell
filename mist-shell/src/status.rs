use std::fs;
use std::io::{BufRead, BufReader};

#[derive(Clone, Debug, Default)]
pub struct SystemStatus {
    pub battery: Option<u8>,
    pub battery_charging: bool,
    pub network_connected: bool,
    pub volume_muted: bool,
}

pub fn poll_status() -> SystemStatus {
    SystemStatus {
        battery: poll_battery_percent(),
        battery_charging: poll_battery_charging(),
        network_connected: poll_network(),
        volume_muted: poll_volume_muted(),
    }
}

fn poll_battery_percent() -> Option<u8> {
    let base = "/sys/class/power_supply";
    let dir = fs::read_dir(base).ok()?;
    for entry in dir.flatten() {
        let name = entry.file_name();
        let n = name.to_string_lossy();
        if !n.starts_with("BAT") && !n.starts_with("bat") { continue }
        let cap = entry.path().join("capacity");
        let val = fs::read_to_string(&cap).ok()?;
        return val.trim().parse::<u8>().ok();
    }
    None
}

fn poll_battery_charging() -> bool {
    let base = "/sys/class/power_supply";
    let dir = fs::read_dir(base).ok();
    let dir = match dir { Some(d) => d, None => return false };
    for entry in dir.flatten() {
        let name = entry.file_name();
        let n = name.to_string_lossy();
        if !n.starts_with("BAT") && !n.starts_with("bat") { continue }
        let status_path = entry.path().join("status");
        let val = match fs::read_to_string(&status_path) { Ok(s) => s, Err(_) => continue };
        return val.trim() == "Charging";
    }
    false
}

#[allow(dead_code)]
fn poll_cpu() -> u8 {
    let Ok(content) = fs::read_to_string("/proc/stat") else { return 0 };
    let Some(line) = content.lines().next() else { return 0 };
    let parts: Vec<u64> = line.split_whitespace().skip(1).filter_map(|s| s.parse().ok()).collect();
    if parts.len() < 4 { return 0 }
    let total: u64 = parts.iter().sum();
    let idle = parts[3];
    use std::sync::atomic::{AtomicU64, Ordering};
    static PREV_TOTAL: AtomicU64 = AtomicU64::new(0);
    static PREV_IDLE: AtomicU64 = AtomicU64::new(0);
    let prev_total = PREV_TOTAL.swap(total, Ordering::Relaxed);
    let prev_idle = PREV_IDLE.swap(idle, Ordering::Relaxed);
    if prev_total == 0 || prev_idle == 0 { return 0 }
    let dtotal = total.saturating_sub(prev_total);
    let didle = idle.saturating_sub(prev_idle);
    if dtotal == 0 { return 0 }
    ((dtotal - didle) * 100 / dtotal) as u8
}

#[allow(dead_code)]
fn poll_mem_percent() -> u8 {
    let Ok(file) = fs::File::open("/proc/meminfo") else { return 0 };
    let reader = BufReader::new(file);
    let mut total = 0u64;
    let mut available = 0u64;
    for line in reader.lines().flatten() {
        if line.starts_with("MemTotal:") {
            if let Some(val) = line.split_whitespace().nth(1).and_then(|s| s.parse::<u64>().ok()) {
                total = val;
            }
        } else if line.starts_with("MemAvailable:") {
            if let Some(val) = line.split_whitespace().nth(1).and_then(|s| s.parse::<u64>().ok()) {
                available = val;
            }
        }
    }
    if total == 0 { return 0 }
    let used = total.saturating_sub(available);
    (used * 100 / total) as u8
}

#[allow(dead_code)]
fn poll_mem_total_gb() -> f32 {
    let Ok(file) = fs::File::open("/proc/meminfo") else { return 0.0 };
    let reader = BufReader::new(file);
    for line in reader.lines().flatten() {
        if line.starts_with("MemTotal:") {
            if let Some(val) = line.split_whitespace().nth(1).and_then(|s| s.parse::<f32>().ok()) {
                return val / (1024.0 * 1024.0);
            }
        }
    }
    0.0
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

#[allow(dead_code)]
fn poll_volume() -> u8 {
    let out = std::process::Command::new("wpctl")
        .args(["get-volume", "@DEFAULT_AUDIO_SINK@"])
        .output();
    match out {
        Ok(o) if o.status.success() => {
            let s = String::from_utf8_lossy(&o.stdout);
            let s = s.trim().strip_prefix("Volume: ").unwrap_or(&s);
            let s = s.split_whitespace().next().unwrap_or("0");
            let vol: f32 = s.parse().unwrap_or(0.0);
            (vol * 100.0) as u8
        }
        _ => 0,
    }
}

fn poll_volume_muted() -> bool {
    let out = std::process::Command::new("wpctl")
        .args(["get-volume", "@DEFAULT_AUDIO_SINK@"])
        .output();
    match out {
        Ok(o) if o.status.success() => {
            let s = String::from_utf8_lossy(&o.stdout);
            s.contains("[MUTED]")
        }
        _ => false,
    }
}
