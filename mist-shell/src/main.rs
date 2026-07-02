use std::sync::mpsc;
use std::thread;
use std::time::Duration;

use guido::prelude::*;
use wayland_client::{
    protocol::{wl_display::WlDisplay, wl_registry},
    Connection, Dispatch, Proxy, QueueHandle,
};
use wayland_protocols::ext::workspace::v1::client::{
    ext_workspace_group_handle_v1::{self, ExtWorkspaceGroupHandleV1},
    ext_workspace_handle_v1::{self, ExtWorkspaceHandleV1, State},
    ext_workspace_manager_v1::{self, ExtWorkspaceManagerV1},
};

const BG: Color = Color::rgb(0.06, 0.06, 0.10);
const SURFACE: Color = Color::rgb(0.10, 0.10, 0.16);
const ACCENT: Color = Color::rgb(0.48, 0.55, 0.78);
const ACCENT_DIM: Color = Color::rgb(0.35, 0.42, 0.62);
const TEXT: Color = Color::rgb(0.88, 0.88, 0.92);
const TEXT_DIM: Color = Color::rgb(0.50, 0.50, 0.62);
const OUTLINE: Color = Color::rgb(0.18, 0.18, 0.26);

fn main() {
    App::new().run(|app| {
        let time = create_signal(String::new());
        let date = create_signal(String::new());
        let t_w = time.writer();
        let d_w = date.writer();
        thread::spawn(move || loop {
            thread::sleep(Duration::from_secs(1));
            let now = chrono::Local::now();
            t_w.set(now.format("%H:%M").to_string());
            d_w.set(now.format("%a %b %-d").to_string());
        });

        let workspaces = create_signal(Vec::new());
        let ws_writer = workspaces.writer();
        let (ws_tx, ws_rx) = mpsc::channel();
        thread::spawn(move || spawn_workspace_thread(ws_writer, ws_rx));

        app.add_surface(
            SurfaceConfig::new()
                .height(36)
                .anchor(Anchor::TOP | Anchor::LEFT | Anchor::RIGHT)
                .background_color(BG),
            move || bar(time, date, workspaces, ws_tx.clone()),
        );
    });
}

type WsList = Vec<(String, bool)>;

struct WsState {
    workspaces: Vec<(ExtWorkspaceHandleV1, String, bool)>,
    manager: Option<ExtWorkspaceManagerV1>,
    writer: guido::reactive::WriteSignal<WsList>,
    rx: mpsc::Receiver<usize>,
}

impl Dispatch<WlDisplay, ()> for WsState {
    fn event(
        _: &mut Self,
        _: &WlDisplay,
        _: <WlDisplay as Proxy>::Event,
        _: &(),
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
    }
}

impl Dispatch<wl_registry::WlRegistry, ()> for WsState {
    fn event(
        state: &mut Self,
        registry: &wl_registry::WlRegistry,
        event: wl_registry::Event,
        _: &(),
        _: &Connection,
        qh: &QueueHandle<Self>,
    ) {
        if let wl_registry::Event::Global { name, interface, .. } = event {
            if interface == "ext_workspace_manager_v1" {
                state.manager = Some(registry.bind::<ExtWorkspaceManagerV1, _, _>(name, 1, qh, ()));
            }
        }
    }
}

impl Dispatch<ExtWorkspaceManagerV1, ()> for WsState {
    fn event(
        state: &mut Self,
        _: &ExtWorkspaceManagerV1,
        event: ext_workspace_manager_v1::Event,
        _: &(),
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
        match event {
            ext_workspace_manager_v1::Event::Workspace { workspace } => {
                state.workspaces.push((workspace, String::new(), false));
            }
            ext_workspace_manager_v1::Event::Done => {
                let list: WsList = state
                    .workspaces
                    .iter()
                    .map(|(_, name, active)| (name.clone(), *active))
                    .collect();
                state.writer.set(list);
            }
            _ => {}
        }
    }
}

impl Dispatch<ExtWorkspaceHandleV1, ()> for WsState {
    fn event(
        state: &mut Self,
        proxy: &ExtWorkspaceHandleV1,
        event: ext_workspace_handle_v1::Event,
        _: &(),
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
        let id = proxy.id();
        match event {
            ext_workspace_handle_v1::Event::Name { name } => {
                if let Some(ws) = state
                    .workspaces
                    .iter_mut()
                    .find(|(p, _, _)| p.id() == id)
                {
                    ws.1 = name;
                }
            }
            ext_workspace_handle_v1::Event::State { state: s } => {
                if let Ok(s) = s.into_result() {
                    let active = s.contains(State::Active);
                    if let Some(ws) = state
                        .workspaces
                        .iter_mut()
                        .find(|(p, _, _)| p.id() == id)
                    {
                        ws.2 = active;
                    }
                }
            }
            ext_workspace_handle_v1::Event::Removed => {
                state.workspaces.retain(|(p, _, _)| p.id() != id);
            }
            _ => {}
        }
    }
}

impl Dispatch<ExtWorkspaceGroupHandleV1, ()> for WsState {
    fn event(
        _: &mut Self,
        _: &ExtWorkspaceGroupHandleV1,
        _: ext_workspace_group_handle_v1::Event,
        _: &(),
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
    }
}

fn spawn_workspace_thread(
    writer: guido::reactive::WriteSignal<WsList>,
    rx: mpsc::Receiver<usize>,
) {
    let conn = match Connection::connect_to_env() {
        Ok(c) => c,
        Err(e) => {
            eprintln!("[mist] ws: connection failed: {e}");
            writer.set(vec![("1".into(), true)]);
            return;
        }
    };

    let mut event_queue = conn.new_event_queue();
    let qh = event_queue.handle();

    let mut state = WsState {
        workspaces: Vec::new(),
        manager: None,
        writer,
        rx,
    };

    let display = conn.display();
    let _registry = display.get_registry(&qh, ());
    if let Err(e) = event_queue.roundtrip(&mut state) {
        eprintln!("[mist] ws: roundtrip failed: {e}");
        return;
    }

    if let Some(ref mgr) = state.manager {
        mgr.commit();
        let _ = conn.flush();
    }

    // Give the compositor a moment to send workspace events
    let deadline = std::time::Instant::now() + Duration::from_secs(2);
    loop {
        let _ = event_queue.dispatch_pending(&mut state);
        if state.workspaces.len() > 0 {
            break;
        }
        if std::time::Instant::now() >= deadline {
            break;
        }
        thread::sleep(Duration::from_millis(50));
    }

    if state.workspaces.is_empty() {
        state.writer.set(vec![
            ("1".into(), true),
            ("2".into(), false),
            ("3".into(), false),
            ("4".into(), false),
        ]);
    }

    loop {
        if let Err(e) = event_queue.dispatch_pending(&mut state) {
            eprintln!("[mist] ws: dispatch error: {e}");
            thread::sleep(Duration::from_secs(1));
            continue;
        }
        if let Err(e) = conn.flush() {
            eprintln!("[mist] ws: flush error: {e}");
        }

        while let Ok(idx) = state.rx.try_recv() {
            if let Some((handle, _, _)) = state.workspaces.get(idx) {
                handle.activate();
                if let Some(ref mgr) = state.manager {
                    mgr.commit();
                }
                let _ = conn.flush();
            }
        }

        thread::sleep(Duration::from_millis(50));
    }
}

fn bar(
    time: guido::reactive::RwSignal<String>,
    date: guido::reactive::RwSignal<String>,
    workspaces: guido::reactive::RwSignal<WsList>,
    ws_tx: mpsc::Sender<usize>,
) -> Container {
    container()
        .padding([4, 8])
        .layout(
            Flex::row()
                .main_alignment(MainAlignment::SpaceBetween)
                .cross_alignment(CrossAlignment::Center),
        )
        .child(left_block(workspaces, ws_tx))
        .child(right_block(time, date))
}

fn left_block(
    workspaces: guido::reactive::RwSignal<WsList>,
    ws_tx: mpsc::Sender<usize>,
) -> Container {
    container()
        .layout(Flex::row().spacing(6.0))
        .child(mist_badge())
        .child(sep())
        .children(move || {
            let list: Vec<(String, bool)> = workspaces.get();
            let tx = ws_tx.clone();
            list.into_iter().enumerate().map(move |(i, (name, active))| {
                (i as u64, {
                    let tx = tx.clone();
                    move || ws_dot(name, active, {
                        let tx = tx.clone();
                        move || {
                            let _ = tx.send(i);
                        }
                    })
                })
            })
        })
}

fn right_block(
    time: guido::reactive::RwSignal<String>,
    date: guido::reactive::RwSignal<String>,
) -> Container {
    container()
        .layout(Flex::row().spacing(8.0))
        .child(clock_pill(time, date))
}

fn clock_pill(
    time: guido::reactive::RwSignal<String>,
    date: guido::reactive::RwSignal<String>,
) -> Container {
    container()
        .padding([4, 8])
        .background(SURFACE)
        .corner_radius(6.0)
        .layout(Flex::row().spacing(4.0))
        .child(text(move || date.get()).font_size(12.0).color(TEXT_DIM))
        .child(
            text(move || time.get())
                .font_size(15.0)
                .font_weight(FontWeight::MEDIUM)
                .mono()
                .color(TEXT),
        )
}

fn mist_badge() -> Container {
    container()
        .padding([4, 8])
        .gradient_horizontal(ACCENT, ACCENT_DIM)
        .corner_radius(5.0)
        .squircle()
        .child(
            text("Mist")
                .font_size(12.0)
                .font_weight(FontWeight::SEMI_BOLD)
                .color(Color::WHITE),
        )
}

fn sep() -> Container {
    container().width(1).height(16).background(OUTLINE)
}

fn ws_dot(name: String, active: bool, on_click: impl Fn() + 'static) -> Container {
    if active {
        container()
            .width(28)
            .height(20)
            .background(ACCENT)
            .corner_radius(10.0)
            .hover_state(|s| s.lighter(0.1))
            .pressed_state(|s| s.ripple())
            .on_click(on_click)
            .layout(
                Flex::row()
                    .main_alignment(MainAlignment::Center)
                    .cross_alignment(CrossAlignment::Center),
            )
            .child(
                text(name)
                    .font_size(11.0)
                    .font_weight(FontWeight::SEMI_BOLD)
                    .color(Color::WHITE),
            )
    } else {
        container()
            .width(20)
            .height(20)
            .background(SURFACE)
            .corner_radius(10.0)
            .hover_state(|s| s.lighter(0.15))
            .pressed_state(|s| s.ripple())
            .on_click(on_click)
            .layout(
                Flex::row()
                    .main_alignment(MainAlignment::Center)
                    .cross_alignment(CrossAlignment::Center),
            )
            .child(text(name).font_size(11.0).color(TEXT_DIM))
    }
}
