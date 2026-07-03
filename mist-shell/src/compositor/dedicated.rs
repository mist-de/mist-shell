use calloop::channel;

use crate::state::WsList;

pub fn spawn_poller(_sender: channel::Sender<WsList>) {
}

pub fn focus_workspace(_name: &str) {
}
