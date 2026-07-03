use std::os::unix::process::CommandExt;
use std::path::Path;
use std::process::{Command, Stdio};

use std::collections::HashMap;
use cosmic_text::Color as CosmicColor;
use vello::peniko::{Blob, ImageAlphaType, ImageBrush, ImageData, ImageFormat};
use vello::Scene;

use crate::render::{color, fill_rect, fill_rounded_rect, stroke_rounded_rect};
use crate::state::State;
use crate::text::render_text;

macro_rules! log_debug {
    ($($arg:tt)*) => {
        if std::env::var("MIST_DEBUG").map(|v| v == "1").unwrap_or(false) {
            eprintln!("[mist] {}", format_args!($($arg)*));
        }
    }
}

pub struct App {
    pub id: String,
    pub name: String,
    pub exec: String,
    pub icon: String,
    pub comment: String,
    pub generic_name: String,
    pub categories: Vec<String>,
    pub startup_wm_class: String,
    pub working_dir: String,
    pub terminal: bool,
}

pub const FIELD_DEFAULT: u8 = 0;
pub const FIELD_ID: u8 = 1;
pub const FIELD_EXEC: u8 = 2;
pub const FIELD_COMMENT: u8 = 3;
pub const FIELD_WM_CLASS: u8 = 4;
pub const FIELD_CATEGORIES: u8 = 5;

pub struct LauncherAction {
    pub name: &'static str,
    pub icon: &'static str,
    pub description: &'static str,
    pub command: &'static [&'static str],
}

pub const ACTIONS: &[LauncherAction] = &[
    LauncherAction { name: "Calculator", icon: "calculate", description: "Do simple math equations (type >calc ...)", command: &["autocomplete", "calc"] },
    LauncherAction { name: "Search by ID", icon: "fingerprint", description: "Search .desktop file names (type >i ...)", command: &["autocomplete", "i"] },
    LauncherAction { name: "Search by Category", icon: "category", description: "Search app categories (type >c ...)", command: &["autocomplete", "c"] },
    LauncherAction { name: "Search by Description", icon: "description", description: "Search app descriptions (type >d ...)", command: &["autocomplete", "d"] },
    LauncherAction { name: "Search by Exec", icon: "terminal", description: "Search app exec commands (type >e ...)", command: &["autocomplete", "e"] },
    LauncherAction { name: "Search by WM Class", icon: "widgets", description: "Search app window classes (type >w ...)", command: &["autocomplete", "w"] },
    LauncherAction { name: "Shutdown", icon: "power_settings_new", description: "Shutdown the system", command: &["poweroff"] },
    LauncherAction { name: "Reboot", icon: "cached", description: "Reboot the system", command: &["reboot"] },
    LauncherAction { name: "Logout", icon: "exit_to_app", description: "Log out of the current session", command: &["logout"] },
    LauncherAction { name: "Lock", icon: "lock", description: "Lock the current session", command: &["loginctl", "lock-session"] },
    LauncherAction { name: "Sleep", icon: "bedtime", description: "Suspend then hibernate", command: &["systemctl", "suspend-then-hibernate"] },
    LauncherAction { name: "Settings", icon: "settings", description: "Configure the shell", command: &["caelestia", "shell", "nexus", "open"] },
    LauncherAction { name: "Dark Mode", icon: "dark_mode", description: "Change the scheme to dark mode", command: &["setMode", "dark"] },
    LauncherAction { name: "Light Mode", icon: "light_mode", description: "Change the scheme to light mode", command: &["setMode", "light"] },
];

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum LauncherView {
    AppList,
    ActionList,
    CalcResult,
}

pub fn parse_search_prefix(query: &str) -> (u8, &str) {
    if let Some(stripped) = query.strip_prefix('>') {
        if stripped.starts_with("i ") { return (FIELD_ID, &stripped[2..].trim()) }
        if stripped.starts_with("c ") { return (FIELD_CATEGORIES, &stripped[2..].trim()) }
        if stripped.starts_with("d ") { return (FIELD_COMMENT, &stripped[2..].trim()) }
        if stripped.starts_with("e ") { return (FIELD_EXEC, &stripped[2..].trim()) }
        if stripped.starts_with("w ") { return (FIELD_WM_CLASS, &stripped[2..].trim()) }
    }
    (FIELD_DEFAULT, query)
}

fn normalize(c: char) -> char {
    match c {
        'à'|'á'|'â'|'ã'|'ä'|'å'|'ā'|'ă'|'ą'|'ǎ'|'ȁ'|'ȃ'|'ȧ'|'ạ'|'ả'|'ǻ' => 'a',
        'À'|'Á'|'Â'|'Ã'|'Ä'|'Å'|'Ā'|'Ă'|'Ą'|'Ǎ'|'Ȁ'|'Ȃ'|'Ȧ'|'Ạ'|'Ả'|'Ǻ' => 'A',
        'è'|'é'|'ê'|'ë'|'ē'|'ĕ'|'ė'|'ę'|'ě'|'ȅ'|'ȇ'|'ȩ'|'ẹ'|'ẻ'|'ẽ' => 'e',
        'È'|'É'|'Ê'|'Ë'|'Ē'|'Ĕ'|'Ė'|'Ę'|'Ě'|'Ȅ'|'Ȇ'|'Ȩ'|'Ẹ'|'Ẻ'|'Ẽ' => 'E',
        'ì'|'í'|'î'|'ï'|'ĩ'|'ī'|'ĭ'|'į'|'ǐ'|'ȉ'|'ȋ'|'ỉ'|'ị'|'ı' => 'i',
        'Ì'|'Í'|'Î'|'Ï'|'Ĩ'|'Ī'|'Ĭ'|'Į'|'Ǐ'|'Ȉ'|'Ȋ'|'Ỉ'|'Ị'|'İ' => 'I',
        'ò'|'ó'|'ô'|'õ'|'ö'|'ō'|'ŏ'|'ő'|'ơ'|'ǒ'|'ȍ'|'ȏ'|'ȫ'|'ȭ'|'ȯ'|'ȱ'|'ọ'|'ỏ' => 'o',
        'Ò'|'Ó'|'Ô'|'Õ'|'Ö'|'Ō'|'Ŏ'|'Ő'|'Ơ'|'Ǒ'|'Ȍ'|'Ȏ'|'Ȫ'|'Ȭ'|'Ȯ'|'Ȱ'|'Ọ'|'Ỏ' => 'O',
        'ù'|'ú'|'û'|'ü'|'ũ'|'ū'|'ŭ'|'ů'|'ű'|'ų'|'ư'|'ǔ'|'ȕ'|'ȗ'|'ụ'|'ủ' => 'u',
        'Ù'|'Ú'|'Û'|'Ü'|'Ũ'|'Ū'|'Ŭ'|'Ů'|'Ű'|'Ų'|'Ư'|'Ǔ'|'Ȕ'|'Ȗ'|'Ụ'|'Ủ' => 'U',
        'ñ'|'ń'|'ņ'|'ň'|'ŋ'|'ǹ'|'ṅ'|'ṇ'|'ṉ' => 'n',
        'Ñ'|'Ń'|'Ņ'|'Ň'|'Ŋ'|'Ǹ'|'Ṅ'|'Ṇ'|'Ṉ' => 'N',
        'ç'|'ć'|'ĉ'|'ċ'|'č'|'ḉ' => 'c',
        'Ç'|'Ć'|'Ĉ'|'Ċ'|'Č'|'Ḉ' => 'C',
        'ğ'|'ģ'|'ĝ'|'ǧ'|'ǵ' => 'g',
        'Ğ'|'Ģ'|'Ĝ'|'Ǧ'|'Ǵ' => 'G',
        'ş'|'ś'|'ŝ'|'š'|'ṡ'|'ṣ' => 's',
        'Ş'|'Ś'|'Ŝ'|'Š'|'Ṡ'|'Ṣ' => 'S',
        'ţ'|'ť'|'ŧ'|'ṭ'|'ṫ'|'ṱ'|'ṯ' => 't',
        'Ţ'|'Ť'|'Ŧ'|'Ṭ'|'Ṫ'|'Ṱ'|'Ṯ' => 'T',
        'ð' => 'd', 'Ð' => 'D',
        'þ' => 't', 'Þ' => 'T',
        'ß' => 's',
        'ł' => 'l', 'Ł' => 'L',
        'ÿ'|'ŷ'|'ý'|'ȳ'|'ỳ'|'ỵ'|'ỷ'|'ỹ' => 'y',
        'Ÿ'|'Ŷ'|'Ý'|'Ȳ'|'Ỳ'|'Ỵ'|'Ỷ'|'Ỹ' => 'Y',
        'ž'|'ź'|'ż' => 'z',
        'Ž'|'Ź'|'Ż' => 'Z',
        'æ' => 'a', 'Æ' => 'A',
        'œ' => 'o', 'Œ' => 'O',
        'đ' => 'd', 'Đ' => 'D',
        'ħ' => 'h', 'Ħ' => 'H',
        'ĳ' => 'i', 'Ĳ' => 'I',
        'ĸ' => 'k',
        _ => c,
    }
}

fn char_class(c: char) -> u8 {
    if c.is_ascii_lowercase() { 1 }
    else if c.is_ascii_uppercase() { 2 }
    else if c.is_ascii_digit() { 4 }
    else if c.is_alphabetic() { 3 }
    else { 0 }
}

fn bonus(prev_class: u8, curr_class: u8) -> i32 {
    if prev_class == 0 && curr_class != 0 { return 8 }
    if (prev_class == 1 && curr_class == 2) || (prev_class != 4 && curr_class == 4) { return 7 }
    if curr_class == 0 { return 8 }
    0
}

pub fn fuzzy_match(query: &str, target: &str) -> Option<u32> {
    let q: Vec<char> = query.chars().collect();
    if q.is_empty() { return Some(0) }

    let mut qi = 0;
    let mut score: i32 = 0;
    let mut gap = 0u32;
    let mut prev_class: u8 = char_class(target.chars().next().unwrap_or('\0'));
    let mut in_first_match = true;

    for (_ti, tc) in target.chars().enumerate() {
        if qi < q.len() {
            let qc = q[qi];
            let nc = normalize(tc).to_ascii_lowercase();
            let nq = normalize(qc).to_ascii_lowercase();
            if nc == nq || tc.eq_ignore_ascii_case(&qc) {
                qi += 1;
                let curr_class = char_class(tc);
                let b = bonus(prev_class, curr_class);

                if in_first_match {
                    score += 16 + b * 2;
                    in_first_match = false;
                } else if gap == 0 {
                    score += 16 + 4;
                } else {
                    score += -3 - ((gap - 1) as i32).max(0);
                    score += 16 + b;
                }
                gap = 0;
                prev_class = curr_class;
                continue;
            }
        }
        if !in_first_match {
            gap = gap.saturating_add(1);
        }
        prev_class = char_class(tc);
    }

    if qi < q.len() {
        log_debug!("fuzzy_match: query=\"{}\" target=\"{}\" NO_MATCH", query, target);
        None
    } else {
        log_debug!("fuzzy_match: query=\"{}\" target=\"{}\" score={}", query, target, score.max(0));
        Some(score.max(0) as u32)
    }
}

pub fn fuzzy_match_on(query: &str, target: &str) -> Option<u32> {
    if target.is_empty() { return None }
    fuzzy_match(query, target)
}

pub fn fuzzy_match_app(query: &str, app: &App, field: u8) -> Option<u32> {
    match field {
        FIELD_DEFAULT => {
            let mut best = fuzzy_match_on(query, &app.name);
            if !app.generic_name.is_empty() {
                best = take_better(best, fuzzy_match_on(query, &app.generic_name));
            }
            best = take_better(best, fuzzy_match_on(query, &app.exec));
            best = take_better(best, fuzzy_match_on(query, &app.comment));
            if !app.id.is_empty() {
                best = take_better(best, fuzzy_match_on(query, &app.id));
            }
            best
        }
        FIELD_ID => fuzzy_match_on(query, &app.id),
        FIELD_EXEC => fuzzy_match_on(query, &app.exec),
        FIELD_COMMENT => fuzzy_match_on(query, &app.comment),
        FIELD_WM_CLASS => fuzzy_match_on(query, &app.startup_wm_class),
        FIELD_CATEGORIES => {
            for cat in &app.categories {
                if let Some(s) = fuzzy_match_on(query, cat) {
                    return Some(s);
                }
            }
            None
        }
        _ => fuzzy_match_on(query, &app.name),
    }
}

fn take_better(a: Option<u32>, b: Option<u32>) -> Option<u32> {
    match (a, b) {
        (Some(a), Some(b)) => Some(a.max(b)),
        (Some(a), None) => Some(a),
        (None, Some(b)) => Some(b),
        (None, None) => None,
    }
}

pub fn find_icon_path(name: &str, size: u32) -> Option<String> {
    if name.is_empty() { return None }
    let mut dirs: Vec<String> = Vec::new();
    if let Ok(home) = std::env::var("HOME") {
        dirs.push(format!("{}/.local/share/icons", home));
    }
    if let Ok(dirs_env) = std::env::var("XDG_DATA_DIRS") {
        for d in dirs_env.split(':') {
            dirs.push(format!("{}/icons", d));
        }
    }
    dirs.push("/usr/share/icons".into());
    dirs.push("/usr/local/share/icons".into());

    for base in &dirs {
        let exact = format!("{}/hicolor/{x}x{x}/apps/{name}.png", base, x = size, name = name);
        if std::path::Path::new(&exact).exists() { return Some(exact) }
        let scalable = format!("{}/hicolor/scalable/apps/{name}.svg", base);
        if std::path::Path::new(&scalable).exists() { return Some(scalable) }
        for theme in &["Adwaita", "breeze", "Papirus", "gnome"] {
            let tp = format!("{}/{theme}/{x}x{x}/apps/{name}.png", base, x = size);
            if std::path::Path::new(&tp).exists() { return Some(tp) }
            let ts = format!("{}/{theme}/scalable/apps/{name}.svg", base);
            if std::path::Path::new(&ts).exists() { return Some(ts) }
        }
    }
    None
}

pub fn load_app_icon<'a>(cache: &'a mut HashMap<String, ImageData>, icon_name: &str) -> Option<&'a ImageData> {
    if icon_name.is_empty() { return None }
    // Check cache first
    if cache.contains_key(icon_name) {
        return cache.get(icon_name);
    }
    // Find and load the icon
    let path = find_icon_path(icon_name, 28)?;
    if let Ok(img) = image::ImageReader::open(&path) {
        if let Ok(rgba) = img.decode().map(|i| i.into_rgba8()) {
            let (w, h) = rgba.dimensions();
            let data: Vec<u8> = rgba.into_raw();
            let image_data = ImageData {
                data: Blob::from(data),
                format: ImageFormat::Rgba8,
                alpha_type: ImageAlphaType::Alpha,
                width: w,
                height: h,
            };
            cache.insert(icon_name.to_string(), image_data);
            return cache.get(icon_name);
        }
    }
    None
}

fn draw_icon(scene: &mut Scene, x: f32, y: f32, size: f32, image_data: &ImageData) {
    let scale = size as f64 / image_data.width.max(image_data.height).max(1) as f64;
    let brush = ImageBrush::new(image_data.clone());
    let transform = vello::kurbo::Affine::translate((x as f64, y as f64))
        * vello::kurbo::Affine::scale(scale);
    scene.draw_image(&brush, transform);
}

pub fn scan_apps() -> Vec<App> {
    let mut apps = Vec::new();
    let home = std::env::var("HOME").unwrap_or_default();
    let local = format!("{}/.local/share/applications", home);
    let dirs = [
        Path::new("/usr/share/applications"),
        Path::new("/usr/local/share/applications"),
        Path::new(&local),
    ];
    for dir in dirs {
        if !dir.exists() {
            log_debug!("scan_apps: dir missing {}", dir.display());
            continue;
        }
        if let Ok(entries) = std::fs::read_dir(dir) {
            for entry in entries.flatten() {
                let path = entry.path();
                if path.extension().and_then(|e| e.to_str()) == Some("desktop")
                    && let Some(app) = parse_desktop(&path) {
                    apps.push(app);
                }
            }
        }
    }
    apps.sort_by_key(|a| a.name.to_lowercase());
    log_debug!("scan_apps: found {} desktop entries", apps.len());
    eprintln!("[mist] scanned {} desktop entries", apps.len());
    apps
}

fn strip_field_codes(exec: &str) -> String {
    let mut result = String::with_capacity(exec.len());
    let bytes = exec.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%' && i + 1 < bytes.len() {
            match bytes[i + 1] {
                b'f' | b'F' | b'u' | b'U' | b'd' | b'D' | b'n' | b'N' | b'i' | b'c' | b'k' => {
                    i += 1; // skip the letter
                    if i + 1 < bytes.len() && bytes[i + 1] == b' ' {
                        i += 1; // skip trailing space
                    }
                    i += 1;
                    continue;
                }
                b'%' => {
                    result.push('%');
                    i += 2;
                    continue;
                }
                _ => {}
            }
        }
        result.push(bytes[i] as char);
        i += 1;
    }
    result.trim().to_string()
}

fn tokenize(cmd: &str) -> Vec<String> {
    let mut args = Vec::new();
    let mut current = String::new();
    let mut in_single = false;
    let mut in_double = false;
    for c in cmd.chars() {
        match c {
            '\'' if !in_double => {
                in_single = !in_single;
            }
            '"' if !in_single => {
                in_double = !in_double;
            }
            ' ' if !in_single && !in_double => {
                if !current.is_empty() {
                    args.push(std::mem::take(&mut current));
                }
            }
            _ => current.push(c),
        }
    }
    if !current.is_empty() {
        args.push(current);
    }
    args
}

fn parse_desktop(path: &Path) -> Option<App> {
    let content = std::fs::read_to_string(path).ok()?;
    let id = path.file_stem().and_then(|s| s.to_str()).unwrap_or("").to_string();
    let mut name: Option<String> = None;
    let mut exec: Option<String> = None;
    let mut icon = String::new();
    let mut comment = String::new();
    let mut generic = String::new();
    let mut categories = Vec::new();
    let mut startup_wm_class = String::new();
    let mut working_dir = String::new();
    let mut hide = false;
    let mut terminal = false;
    let mut in_desktop = false;
    for line in content.lines() {
        let line = line.trim();
        if line == "[Desktop Entry]" { in_desktop = true; continue }
        if line.starts_with('[') { in_desktop = false; continue }
        if !in_desktop { continue }
        let Some((key, val)) = line.split_once('=') else { continue };
        match key {
            _ if key.starts_with("Name[") || key == "Name" => { name = name.or(Some(val.to_string())); }
            _ if key.starts_with("GenericName[") || key == "GenericName" => { if generic.is_empty() { generic = val.to_string(); } }
            _ if key.starts_with("Comment[") || key == "Comment" => { if comment.is_empty() { comment = val.to_string(); } }
            "Exec" => { exec = Some(val.to_string()); }
            "Icon" => { icon = val.to_string(); }
            "Categories" => { categories = val.split(';').map(|s| s.trim().to_string()).filter(|s| !s.is_empty()).collect(); }
            "StartupWMClass" => { startup_wm_class = val.to_string(); }
            "Path" => { working_dir = val.to_string(); }
            "Terminal" => { terminal = val == "true"; }
            "NoDisplay" | "Hidden" => { hide = val == "true"; }
            _ => {}
        }
    }
    if hide { log_debug!("parse_desktop: {} skipped (NoDisplay/Hidden)", id); return None }
    let exec = exec?;
    let exec = strip_field_codes(&exec);
    let app = App {
        id,
        name: name?,
        exec: exec.trim().to_string(),
        icon,
        comment,
        generic_name: generic,
        categories,
        startup_wm_class,
        working_dir,
        terminal,
    };
    log_debug!("parse_desktop: name=\"{}\" exec=\"{}\" categories={:?} wm=\"{}\" terminal={}", app.name, app.exec, app.categories, app.startup_wm_class, app.terminal);
    Some(app)
}

fn launch_exec(exec: &str, activation_token: Option<&str>, working_dir: Option<&str>) {
    let args = tokenize(exec);
    if args.is_empty() {
        eprintln!("[mist] launch failed: empty exec string");
        return;
    }
    log_debug!("launch_exec: {:?}", args);
    let mut cmd = Command::new(&args[0]);
    cmd.args(&args[1..])
        .process_group(0)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .env("XDG_SESSION_TYPE", "wayland");
    if let Some(dir) = working_dir {
        if !dir.is_empty() {
            cmd.current_dir(dir);
        }
    }
    if let Some(token) = activation_token {
        cmd.env("XDG_ACTIVATION_TOKEN", token);
    }
    match cmd.spawn() {
        Ok(child) => eprintln!("[mist] launched: pid={} cmd=\"{}\"", child.id(), exec),
        Err(e) => eprintln!("[mist] launch failed: {} cmd=\"{}\"", e, exec),
    }
}

pub fn launch_app(exec: &str) {
    launch_exec(exec, None, None);
}

pub fn launch_desktop_app(app: &App, activation_token: Option<&str>) {
    if app.terminal {
        let term = std::env::var("TERMINAL").unwrap_or_else(|_| "foot".to_string());
        let terminal_exec = format!("{} -e {}", term, app.exec);
        launch_exec(&terminal_exec, None, None);
    } else {
        launch_exec(&app.exec, activation_token, Some(&app.working_dir));
    }
}

pub fn render_launcher(state: &mut State) -> (Scene, (f32, f32, f32, f32)) {
    let w = state.launcher.w.max(1) as u32;
    let h = state.launcher.h.max(1) as u32;

    let anim_value = if state.launcher.anim_show.running {
        state.launcher.anim_show.value()
    } else if state.launcher.anim_hide.running {
        state.launcher.anim_hide.value()
    } else {
        1.0
    };
    let anim_scale = 0.85 + 0.15 * anim_value;

    let panel_w = ((w as f32 * 0.5).clamp(300.0, 600.0)) * anim_scale;
    let panel_h = ((h as f32 * 0.65).clamp(240.0, 560.0)) * anim_scale;
    let px = (w as f32 - panel_w) / 2.0;
    let py = (h as f32 - panel_h) / 2.0;
    let pad = 12.0;
    let search_h = 42.0;
    let search_y = py + panel_h - pad - search_h;
    let div_y = search_y - 10.0;
    let start_y = py + pad;
    let item_h = 38.0;
    let max_visible = ((div_y - 10.0 - start_y) / item_h).max(1.0) as usize;

    let mut scene = Scene::new();

    let bg_alpha = (0xC8 as f32 * anim_value) as u8;
    let border_alpha = (0x12 as f32 * anim_value) as u8;
    fill_rounded_rect(&mut scene, px, py, panel_w, panel_h, 18.0, color((0x1E, 0x1E, 0x2E, bg_alpha)));
    stroke_rounded_rect(&mut scene, px, py, panel_w, panel_h, 18.0, 1.0, color((0xCD, 0xD6, 0xF4, border_alpha)));

    let search_x = px + pad;
    let search_w = panel_w - pad * 2.0;

    fill_rounded_rect(&mut scene, search_x, search_y, search_w, search_h, 21.0, color((0x31, 0x32, 0x44, 0xE6)));

    render_text(&mut scene, &mut state.font, &mut state.swash, ">", search_x + 14.0, search_y + 12.0, 14.0, CosmicColor::rgba(0x6C, 0x70, 0x86, 0xFF));

    let text_x = search_x + 14.0 + 10.0;
    if state.launcher.query.is_empty() {
        render_text(&mut scene, &mut state.font, &mut state.swash, "  Search apps or type \">\" for commands...", text_x, search_y + 12.0, 14.0, CosmicColor::rgba(0x6C, 0x70, 0x86, 0xFF));
    } else {
        let cursor_visible = (state.launcher.start_time.elapsed().as_millis() / 500).is_multiple_of(2);
        let display = if cursor_visible {
            let mut s = state.launcher.query.clone();
            s.push('|');
            s
        } else {
            state.launcher.query.clone()
        };
        render_text(&mut scene, &mut state.font, &mut state.swash, &display, text_x, search_y + 12.0, 14.0, CosmicColor::rgba(0xCD, 0xD6, 0xF4, 0xFF));
    }

    fill_rect(&mut scene, px + pad, div_y, panel_w - pad * 2.0, 1.0, color((0x36, 0x3A, 0x4F, 0xFF)));

    state.launcher.dirty = false;

    match state.launcher.view {
        LauncherView::CalcResult => {
            if let Some(ref calc_res) = state.launcher.calc_result {
                let iy = start_y;
                if state.launcher.selection == 0 {
                    fill_rounded_rect(&mut scene, px + 6.0, iy, panel_w - 12.0, item_h - 4.0, 8.0, color((0x7A, 0xA2, 0xF7, 0x33)));
                }
                render_text(&mut scene, &mut state.font, &mut state.swash, "\u{f8c9}", px + 16.0, iy + 10.0, 14.0, CosmicColor::rgba(0x7A, 0xA2, 0xF7, 0xFF));
                render_text(&mut scene, &mut state.font, &mut state.swash, " = ", px + 36.0, iy + 10.0, 13.0, CosmicColor::rgba(0xCD, 0xD6, 0xF4, 0xFF));
                render_text(&mut scene, &mut state.font, &mut state.swash, &state.launcher.query, px + 56.0, iy + 10.0, 13.0, CosmicColor::rgba(0x6C, 0x70, 0x86, 0xFF));
                render_text(&mut scene, &mut state.font, &mut state.swash, calc_res, px + 56.0, iy + 26.0, 11.0, CosmicColor::rgba(0xA6, 0xDA, 0x95, 0xFF));
                let start = state.launcher.scroll_offset.min(state.launcher.matching_actions.len().saturating_sub(1));
                let end = (start + max_visible.saturating_sub(1)).min(state.launcher.matching_actions.len());
                for (rel_i, &act_idx) in state.launcher.matching_actions[start..end].iter().enumerate() {
                    let iy = start_y + (rel_i + 1) as f32 * item_h;
                    if start + rel_i + 1 == state.launcher.selection {
                        fill_rounded_rect(&mut scene, px + 6.0, iy, panel_w - 12.0, item_h - 4.0, 8.0, color((0xCD, 0xD6, 0xF4, 0x12)));
                    }
                    if let Some(act) = state.launcher.actions.get(act_idx) {
                        render_text(&mut scene, &mut state.font, &mut state.swash, ">", px + 16.0, iy + 10.0, 14.0, CosmicColor::rgba(0x6C, 0x70, 0x86, 0xFF));
                        render_text(&mut scene, &mut state.font, &mut state.swash, act.name, px + 36.0, iy + 10.0, 13.0, CosmicColor::rgba(0xCD, 0xD6, 0xF4, 0xFF));
                        render_text(&mut scene, &mut state.font, &mut state.swash, act.description, px + 36.0, iy + 26.0, 11.0, CosmicColor::rgba(0x6C, 0x70, 0x86, 0xFF));
                    }
                }
            }
        }
        LauncherView::ActionList => {
            let start = state.launcher.scroll_offset.min(state.launcher.matching_actions.len().saturating_sub(1));
            let end = (start + max_visible).min(state.launcher.matching_actions.len());
            for (rel_i, &act_idx) in state.launcher.matching_actions[start..end].iter().enumerate() {
                let iy = start_y + rel_i as f32 * item_h;
                if start + rel_i == state.launcher.selection {
                    fill_rounded_rect(&mut scene, px + 6.0, iy, panel_w - 12.0, item_h - 4.0, 8.0, color((0xCD, 0xD6, 0xF4, 0x12)));
                }
                if let Some(act) = state.launcher.actions.get(act_idx) {
                    render_text(&mut scene, &mut state.font, &mut state.swash, ">", px + 16.0, iy + 10.0, 14.0, CosmicColor::rgba(0x6C, 0x70, 0x86, 0xFF));
                    render_text(&mut scene, &mut state.font, &mut state.swash, act.name, px + 36.0, iy + 10.0, 13.0, CosmicColor::rgba(0xCD, 0xD6, 0xF4, 0xFF));
                    render_text(&mut scene, &mut state.font, &mut state.swash, act.description, px + 36.0, iy + 26.0, 11.0, CosmicColor::rgba(0x6C, 0x70, 0x86, 0xFF));
                }
            }
        }
        LauncherView::AppList => {
            let start = state.launcher.scroll_offset.min(state.launcher.matching.len().saturating_sub(1));
            let end = (start + max_visible).min(state.launcher.matching.len());
            for (rel_i, &app_idx) in state.launcher.matching[start..end].iter().enumerate() {
                let app = &state.launcher.apps[app_idx];
                let iy = start_y + rel_i as f32 * item_h;
                if start + rel_i == state.launcher.selection {
                    fill_rounded_rect(&mut scene, px + 6.0, iy, panel_w - 12.0, item_h - 4.0, 8.0, color((0xCD, 0xD6, 0xF4, 0x12)));
                }

                let icon_size = 28.0;
                let icon_x = px + 12.0;
                let icon_y = iy + (item_h - icon_size) / 2.0;
                let icon_data = load_app_icon(&mut state.icon_cache, &app.icon);
                if let Some(img) = icon_data {
                    draw_icon(&mut scene, icon_x, icon_y, icon_size, img);
                } else {
                    fill_rounded_rect(&mut scene, icon_x, icon_y, icon_size, icon_size, 7.0, color((0x45, 0x47, 0x5A, 0xFF)));
                    let mut buf = [0u8; 4];
                    let first = app.name.chars().next().unwrap_or('?').encode_utf8(&mut buf);
                    render_text(&mut scene, &mut state.font, &mut state.swash, first, icon_x + 9.0, icon_y + 7.0, 13.0, CosmicColor::rgba(0xA6, 0xAD, 0xC8, 0xFF));
                }

                let label_x = icon_x + icon_size + 10.0;
                render_text(&mut scene, &mut state.font, &mut state.swash, &app.name, label_x, iy + 10.0, 13.0, CosmicColor::rgba(0xCD, 0xD6, 0xF4, 0xFF));
                let comment = if !app.comment.is_empty() { &app.comment } else { &app.generic_name };
                if !comment.is_empty() {
                    render_text(&mut scene, &mut state.font, &mut state.swash, comment, label_x, iy + 26.0, 11.0, CosmicColor::rgba(0x6C, 0x70, 0x86, 0xFF));
                }
            }
        }
    }

    (scene, (px, py, panel_w, panel_h))
}
