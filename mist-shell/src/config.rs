use serde::Deserialize;

#[derive(Deserialize, Clone, Debug)]
pub struct MistConfig {
    #[serde(default)]
    #[allow(dead_code)]
    pub bar: BarConfig,
    #[serde(default)]
    pub timezone: Option<String>,
}

#[derive(Deserialize, Clone, Debug)]
#[allow(dead_code)]
pub struct BarConfig {
    #[serde(default = "default_true")]
    pub battery: bool,
    #[serde(default = "default_true")]
    pub cpu: bool,
    #[serde(default = "default_true")]
    pub memory: bool,
    #[serde(default = "default_true")]
    pub clock: bool,
    #[serde(default = "default_true")]
    pub network: bool,
    #[serde(default = "default_true")]
    pub audio: bool,
}

impl Default for MistConfig {
    fn default() -> Self {
        Self {
            bar: BarConfig::default(),
            timezone: None,
        }
    }
}

impl Default for BarConfig {
    fn default() -> Self {
        Self {
            battery: true,
            cpu: true,
            memory: true,
            clock: true,
            network: true,
            audio: true,
        }
    }
}

fn default_true() -> bool { true }

pub fn load() -> MistConfig {
    let path = dirs_config_path().map(|p| p.join("mist/config.toml"));
    match path {
        Some(p) if p.exists() => {
            match std::fs::read_to_string(&p) {
                Ok(content) => match toml::from_str(&content) {
                    Ok(cfg) => cfg,
                    Err(e) => { eprintln!("config parse error: {}", e); MistConfig::default() }
                },
                Err(e) => { eprintln!("config read error: {}", e); MistConfig::default() }
            }
        }
        _ => MistConfig::default(),
    }
}

fn dirs_config_path() -> Option<std::path::PathBuf> {
    if let Ok(dir) = std::env::var("XDG_CONFIG_HOME") {
        Some(std::path::PathBuf::from(dir))
    } else if let Ok(home) = std::env::var("HOME") {
        Some(std::path::PathBuf::from(home).join(".config"))
    } else {
        None
    }
}
