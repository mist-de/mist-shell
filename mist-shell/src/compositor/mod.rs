mod mangowm;
mod niri;
mod dedicated;

use calloop::channel::{self, Channel};
use crate::state::WsList;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum CompositorType {
    MangoWM,
    Niri,
    Dedicated,
}

pub fn detect() -> CompositorType {
    if std::env::var("MANGO_INSTANCE_SIGNATURE").is_ok() {
        CompositorType::MangoWM
    } else if std::env::var("NIRI_SOCKET").is_ok() {
        CompositorType::Niri
    } else {
        CompositorType::Dedicated
    }
}

pub fn spawn_workspace_poller(ct: CompositorType) -> Channel<WsList> {
    let (tx, rx) = channel::channel();
    match ct {
        CompositorType::MangoWM => mangowm::spawn_poller(tx),
        CompositorType::Niri => niri::spawn_poller(tx),
        CompositorType::Dedicated => dedicated::spawn_poller(tx),
    }
    rx
}

pub fn focus_workspace(ct: CompositorType, name: &str) {
    match ct {
        CompositorType::MangoWM => mangowm::focus_workspace(name),
        CompositorType::Niri => niri::focus_workspace(name),
        CompositorType::Dedicated => dedicated::focus_workspace(name),
    }
}
