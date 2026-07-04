mod bar;
mod calc;
mod config;
mod compositor;
mod ease;
mod launcher;
mod render;
mod shell_ipc;
mod state;
mod status;
mod text;
mod tokens;
mod wl;

use std::os::fd::{AsFd, AsRawFd, FromRawFd, OwnedFd};
use std::time::Duration;

use calloop::channel::{self, Channel};
use calloop::generic::Generic;
use calloop::timer::{TimeoutAction, Timer};
use calloop::{EventLoop, Interest, Mode};
use std::ptr::NonNull;
use raw_window_handle::{RawDisplayHandle, RawWindowHandle, WaylandDisplayHandle, WaylandWindowHandle};
use wayland_client::globals::registry_queue_init;
use wayland_client::Proxy;
use wayland_client::protocol::wl_compositor::WlCompositor;
use wayland_client::protocol::wl_seat::WlSeat;
use wayland_client::Connection;
use wayland_protocols_wlr::layer_shell::v1::client::zwlr_layer_shell_v1::{Layer, ZwlrLayerShellV1};
use wayland_protocols_wlr::layer_shell::v1::client::zwlr_layer_surface_v1::Anchor;

use crate::bar::render_bar;
use crate::state::{BarSurface, LauncherSurface, State, Tag};

type CmdTx = channel::Sender<(u64, serde_json::Value)>;
type CmdRx = Channel<(u64, serde_json::Value)>;

fn auto_detect_vulkan_icd() {
    if std::env::var_os("VK_ICD_FILENAMES").is_some() {
        return;
    }
    let icd_dir = std::path::Path::new("/usr/share/vulkan/icd.d");
    let dir = match std::fs::read_dir(icd_dir) {
        Ok(d) => d,
        Err(_) => return,
    };
    let mut candidates: Vec<(u8, std::path::PathBuf)> = Vec::new();
    for entry in dir.flatten() {
        let path = entry.path();
        if path.extension().and_then(|e| e.to_str()) != Some("json") {
            continue;
        }
        let name = path.file_stem().and_then(|n| n.to_str()).unwrap_or("");
        let priority: u8 = if name.contains("radeon") || name.contains("radv") {
            30  // RADV is preferred
        } else if name.contains("amd") || name.contains("pro") {
            20
        } else if name.contains("intel") || name.contains("anv") {
            25
        } else if name.contains("virtio") || name.contains("lvp") {
            10
        } else {
            5
        };
        candidates.push((priority, path));
    }
    candidates.sort_by(|a, b| b.0.cmp(&a.0));
    if let Some((_, path)) = candidates.into_iter().next() {
        let p = path.to_string_lossy().to_string();
        eprintln!("[mist] auto-detected vulkan icd: {p}");
        unsafe { std::env::set_var("VK_ICD_FILENAMES", &p); }
    }
}

fn main() {
    if std::env::args().any(|a| a == "--help" || a == "-h") {
        eprintln!("Mist Shell v{}", env!("CARGO_PKG_VERSION"));
        eprintln!("Usage: mist-shell [--debug] [--help]");
        eprintln!("  --debug   Enable verbose debug logging");
        eprintln!("  --help    Show this help and exit");
        eprintln!();
        eprintln!("Environment:");
        eprintln!("  MIST_DEBUG=1          Enable debug logging (same as --debug)");
        eprintln!("  XDG_CONFIG_HOME/mist/config.toml  Configuration file");
        eprintln!("  WAYLAND_DISPLAY       Wayland compositor socket");
        std::process::exit(0);
    }
    if std::env::args().any(|a| a == "--debug") {
        unsafe { std::env::set_var("MIST_DEBUG", "1"); }
    }

    eprintln!("[mist] starting up...");
    eprintln!("[mist] version {}", env!("CARGO_PKG_VERSION"));
    eprintln!("[mist] debug={}", std::env::var("MIST_DEBUG").unwrap_or_default());

    auto_detect_vulkan_icd();

    use std::panic;
    let prev = panic::take_hook();
    panic::set_hook(Box::new(move |info| {
        eprintln!("[mist] PANIC: {}", info);
        prev(info);
    }));

    let conn = match Connection::connect_to_env() {
        Ok(c) => c,
        Err(e) => { eprintln!("[mist] FATAL: Wayland connect: {:?}", e); std::process::exit(1); }
    };
    eprintln!("[mist] wayland connected (display={:?})", conn.backend().display_id());
    let (globals, mut eq) = match registry_queue_init::<State>(&conn) {
        Ok(g) => g,
        Err(e) => { eprintln!("REGISTRY INIT: {:?}", e); std::process::exit(1); }
    };
    let qh = eq.handle();

    let compositor: WlCompositor = globals.bind(&qh, 4..=6, ()).expect("wl_compositor");
    let layer_shell: ZwlrLayerShellV1 = globals.bind(&qh, 1..=4, ()).expect("wlr-layer-shell");
    let _seat: WlSeat = globals.bind(&qh, 1..=9, ()).expect("wl_seat");
    let cursor_shape_manager = globals.bind(&qh, 1..=1, ()).ok();

    let bar_w = crate::tokens::BAR_TOTAL_W as i32;
    let surface = compositor.create_surface(&qh, ());
    let layer = layer_shell.get_layer_surface(&surface, None, Layer::Top, "mist-shell".into(), &qh, ());
    layer.set_anchor(Anchor::Left | Anchor::Top | Anchor::Bottom);
    layer.set_exclusive_zone(bar_w);
    layer.set_size(bar_w as u32, 0);
    surface.commit();
    let _ = conn.flush();

    let init_w = bar_w;
    let init_h = 1080i32;

    // Initialize wgpu
    let gpu_instance = wgpu::Instance::new(wgpu::InstanceDescriptor {
        backends: wgpu::Backends::all(),
        flags: wgpu::InstanceFlags::default(),
        memory_budget_thresholds: wgpu::MemoryBudgetThresholds::default(),
        backend_options: wgpu::BackendOptions::from_env_or_default(),
        display: None,
    });

    let raw_display = {
        let ptr = conn.backend().display_id().as_ptr() as *mut std::ffi::c_void;
        RawDisplayHandle::Wayland(WaylandDisplayHandle::new(NonNull::new(ptr).unwrap()))
    };
    let raw_window = {
        let ptr = surface.id().as_ptr() as *mut std::ffi::c_void;
        RawWindowHandle::Wayland(WaylandWindowHandle::new(NonNull::new(ptr).unwrap()))
    };
    let bar_wgpu_surface = unsafe {
        gpu_instance.create_surface_unsafe(wgpu::SurfaceTargetUnsafe::RawHandle {
            raw_display_handle: Some(raw_display),
            raw_window_handle: raw_window,
        })
    }.expect("create wgpu surface");

    let adapter = pollster::block_on(gpu_instance.request_adapter(&wgpu::RequestAdapterOptions {
        power_preference: wgpu::PowerPreference::HighPerformance,
        compatible_surface: Some(&bar_wgpu_surface),
        force_fallback_adapter: false,
    })).expect("Failed to find a suitable GPU adapter");

    let bar_surface_format = bar_wgpu_surface.get_capabilities(&adapter).formats.into_iter()
        .find(|f| *f == wgpu::TextureFormat::Rgba8Unorm)
        .unwrap_or(wgpu::TextureFormat::Bgra8Unorm);

    let (gpu_device, gpu_queue) = pollster::block_on(adapter.request_device(
        &wgpu::DeviceDescriptor {
            label: Some("Mist GPU Device"),
            required_features: wgpu::Features::empty(),
            required_limits: wgpu::Limits::default(),
            memory_hints: wgpu::MemoryHints::MemoryUsage,
            experimental_features: wgpu::ExperimentalFeatures::disabled(),
            trace: wgpu::Trace::Off,
        },
    )).expect("Failed to create GPU device");

    bar_wgpu_surface.configure(&gpu_device, &wgpu::SurfaceConfiguration {
        usage: wgpu::TextureUsages::RENDER_ATTACHMENT,
        format: bar_surface_format,
        width: init_w as u32,
        height: init_h as u32,
        present_mode: wgpu::PresentMode::Fifo,
        alpha_mode: wgpu::CompositeAlphaMode::PreMultiplied,
        view_formats: vec![],
        desired_maximum_frame_latency: 1,
    });

    let vello_renderer = vello::Renderer::new(
        &gpu_device,
        vello::RendererOptions {
            use_cpu: false,
            antialiasing_support: vello::AaSupport::all(),
            num_init_threads: None,
            pipeline_cache: None,
        },
    ).expect("Failed to create Vello renderer");

    let _ = conn.flush();

    let ct = compositor::detect();
    eprintln!("[mist] compositor: {:?}", ct);
    let ws_rx = compositor::spawn_workspace_poller(ct);

    let (cmd_tx, cmd_rx): (CmdTx, CmdRx) = channel::channel();
    let (resp_tx, resp_rx) = std::sync::mpsc::channel::<(u64, serde_json::Value)>();
    shell_ipc::spawn_shell_ipc(cmd_tx, Some((resp_tx, resp_rx)));

    let config = crate::config::load();
    let mut state = State {
        conn: conn.clone(), qh,
        compositor, layer_shell,
        bar: BarSurface {
            surface, layer,
            wgpu_surface: Some(bar_wgpu_surface),
            w: init_w, h: init_h,
            configured: false, frame_pending: false, dirty: true,
            surface_format: bar_surface_format,
            intermediate_texture: None, intermediate_view: None, blitter: None,
        },
        launcher: LauncherSurface {
            surface: None, layer: None,
            wgpu_surface: None,
            w: 0, h: 0,
            configured: false, frame_pending: false, dirty: false,
            surface_format: wgpu::TextureFormat::Rgba8Unorm,
            intermediate_texture: None, intermediate_view: None, blitter: None,
            visible: false, apps: Vec::new(),
            view: crate::launcher::LauncherView::AppList, matching: Vec::new(), matching_actions: Vec::new(),
            selection: 0, query: String::new(), scroll_offset: 0, panel: None,
            actions: Vec::new(), start_time: std::time::Instant::now(),
            calc_result: None,
            anim_show: crate::ease::AnimState::new(),
            anim_hide: crate::ease::AnimState::new(),
        },
        pointer: None, keyboard: None,
        pointer_x: 0.0, pointer_y: 0.0, pointer_serial: 0,
        cursor_shape_manager, cursor_shape_device: None, current_cursor: None,
        compositor_type: ct,
        clock: String::new(), date: String::new(),
        workspaces: (1..=9).map(|i| (i.to_string(), Tag::default())).collect(),
        font: crate::text::init_font_system(), font_cache: crate::text::FontCache::new(),
        xkb_ctx: None, xkb_state: None,
        config,
        status: crate::status::SystemStatus::default(),
        hovered_ws: None,
        gpu_instance,
        gpu_device,
        gpu_queue,
        vello_renderer,
        icon_cache: std::collections::HashMap::new(),
    };

    // Roundtrip: force compositor to process pending requests and
    // send events (including layer-surface configure).
    let _ = eq.roundtrip(&mut state);

    // If configure still hasn't arrived, pre-configure bar with initial size.
    if !state.bar.configured {
        state.bar.configured = true;
        let scene = render_bar(&mut state);
        state.commit_bar(scene);
    }

    let mut loop_ = EventLoop::<State>::try_new().expect("event loop");
    let handle = loop_.handle();

    let wl_fd = conn.as_fd().as_raw_fd();
    let dup_fd = unsafe { libc::dup(wl_fd) };
    if dup_fd < 0 { eprintln!("dup(wl_fd) failed"); std::process::exit(1); }
    let owned_fd = unsafe { OwnedFd::from_raw_fd(dup_fd) };
    let conn_ = Some(conn);
    let mut eq_ = Some(eq);
    handle.insert_source(Generic::new(owned_fd, Interest::READ, Mode::Level), move |_, _, state: &mut State| -> Result<_, std::io::Error> {
        let eq = eq_.as_mut().unwrap();
        let conn = conn_.as_ref().unwrap();
        if let Some(guard) = conn.prepare_read() && let Err(e) = guard.read() { eprintln!("read err: {:?}", e); std::process::exit(1) }
        if let Err(e) = eq.dispatch_pending(state) { eprintln!("dispatch err: {:?}", e); std::process::exit(1) }
        if let Err(e) = conn.flush() { eprintln!("flush err: {:?}", e); std::process::exit(1) }
        Ok(calloop::PostAction::Continue)
    }).expect("wl source");

    handle.insert_source(Timer::from_duration(Duration::from_millis(16)), move |_, _, state: &mut State| {
        state.status = crate::status::poll_status();
        let tz = state.config.timezone.as_deref().and_then(|s| s.parse::<chrono_tz::Tz>().ok());
        let (d, c) = match tz {
            Some(tz) => {
                let now = chrono::Utc::now().with_timezone(&tz);
                (now.format("%a %b %-d").to_string(), now.format("%H:%M").to_string())
            }
            None => {
                let now = chrono::Local::now();
                (now.format("%a %b %-d").to_string(), now.format("%H:%M").to_string())
            }
        };
        let clock_changed = d != state.date || c != state.clock;
        state.date = d;
        state.clock = c;

        if clock_changed || state.bar.dirty {
            state.bar.dirty = true;
            if state.bar.configured && !state.bar.frame_pending {
                let scene = render_bar(state);
                state.commit_bar(scene);
            }
        }
        if state.launcher.dirty {
            state.flush_launcher_render();
        }
        TimeoutAction::ToDuration(Duration::from_millis(16))
    }).expect("timer");

    handle.insert_source(ws_rx, |event, _, state: &mut State| {
        if let calloop::channel::Event::Msg(list) = event && state.workspaces != list {
            state.workspaces = list;
            state.bar.dirty = true;
            if state.bar.configured {
                let scene = render_bar(state);
                state.commit_bar(scene);
            }
        }
    }).expect("ws channel");

    handle.insert_source(cmd_rx, |event, _, state: &mut State| {
        if let calloop::channel::Event::Msg((_conn_id, val)) = event {
            match val.get("cmd").and_then(|c| c.as_str()) {
                Some("show") if val.get("target").and_then(|t| t.as_str()) == Some("launcher") => state.show_launcher(),
                Some("hide") if val.get("target").and_then(|t| t.as_str()) == Some("launcher") => state.hide_launcher(),
                Some("toggle") if val.get("target").and_then(|t| t.as_str()) == Some("launcher") => {
                    if state.launcher.visible { state.hide_launcher() } else { state.show_launcher() }
                }
                _ => {}
            }
        }
    }).expect("shell ipc rx");

    loop_.run(None, &mut state, |_| {}).expect("run");
}
