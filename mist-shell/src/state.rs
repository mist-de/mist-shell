use std::collections::HashMap;
use std::time::Instant;

use crate::ease::AnimState;
use crate::text::FontCache;

use vello::Scene;
use wayland_client::protocol::wl_compositor::WlCompositor;
use wayland_client::protocol::wl_keyboard::WlKeyboard;
use wayland_client::protocol::wl_pointer::WlPointer;
use wayland_protocols::wp::cursor_shape::v1::client::wp_cursor_shape_device_v1::{Shape, WpCursorShapeDeviceV1};
use wayland_protocols::wp::cursor_shape::v1::client::wp_cursor_shape_manager_v1::WpCursorShapeManagerV1;

use wayland_client::protocol::wl_surface::WlSurface;
use wayland_client::{Connection, QueueHandle};
use wayland_protocols_wlr::layer_shell::v1::client::zwlr_layer_shell_v1::{Layer, ZwlrLayerShellV1};
use wayland_protocols_wlr::layer_shell::v1::client::zwlr_layer_surface_v1::{Anchor, KeyboardInteractivity, ZwlrLayerSurfaceV1};
use xkbcommon::xkb;

use crate::launcher;

pub type WsList = Vec<(String, Tag)>;

#[derive(Clone, Debug, Default, PartialEq)]
pub struct Tag {
    pub active: bool,
    pub urgent: bool,
    pub occupied: bool,
}

#[allow(dead_code)]
pub struct BarCb;
#[allow(dead_code)]
pub struct LauncherCb;

pub struct BarSurface {
    #[allow(dead_code)]
    pub surface: WlSurface,
    pub layer: ZwlrLayerSurfaceV1,
    pub wgpu_surface: Option<wgpu::Surface<'static>>,
    pub w: i32,
    pub h: i32,
    pub configured: bool,
    pub frame_pending: bool,
    pub dirty: bool,
    pub surface_format: wgpu::TextureFormat,
    pub intermediate_texture: Option<wgpu::Texture>,
    pub intermediate_view: Option<wgpu::TextureView>,
    pub blitter: Option<wgpu::util::TextureBlitter>,
}

pub struct LauncherSurface {
    #[allow(dead_code)]
    pub surface: Option<WlSurface>,
    pub layer: Option<ZwlrLayerSurfaceV1>,
    pub wgpu_surface: Option<wgpu::Surface<'static>>,
    pub w: i32,
    pub h: i32,
    pub configured: bool,
    pub frame_pending: bool,
    pub dirty: bool,
    pub surface_format: wgpu::TextureFormat,
    pub intermediate_texture: Option<wgpu::Texture>,
    pub intermediate_view: Option<wgpu::TextureView>,
    pub blitter: Option<wgpu::util::TextureBlitter>,
    pub visible: bool,
    pub apps: Vec<launcher::App>,
    pub matching: Vec<usize>,
    pub view: launcher::LauncherView,
    pub matching_actions: Vec<usize>,
    pub selection: usize,
    pub query: String,
    pub scroll_offset: usize,
    pub panel: Option<(f32, f32, f32, f32)>,
    pub actions: Vec<launcher::LauncherAction>,
    pub start_time: Instant,
    pub calc_result: Option<String>,
    pub anim_show: AnimState,
    pub anim_hide: AnimState,
}

pub struct State {
    pub conn: Connection,
    pub qh: QueueHandle<State>,
    pub compositor: WlCompositor,
    pub layer_shell: ZwlrLayerShellV1,
    pub bar: BarSurface,
    pub launcher: LauncherSurface,
    pub pointer: Option<WlPointer>,
    pub keyboard: Option<WlKeyboard>,
    pub pointer_x: f64,
    pub pointer_y: f64,
    pub pointer_serial: u32,
    pub cursor_shape_manager: Option<WpCursorShapeManagerV1>,
    pub cursor_shape_device: Option<WpCursorShapeDeviceV1>,
    pub current_cursor: Option<Shape>,
    pub compositor_type: crate::compositor::CompositorType,
    pub clock: String,
    pub date: String,
    pub workspaces: WsList,
    pub font: cosmic_text::FontSystem,
    pub font_cache: FontCache,
    pub xkb_ctx: Option<xkb::Context>,
    pub xkb_state: Option<xkb::State>,
    pub config: crate::config::MistConfig,
    pub status: crate::status::SystemStatus,
    pub hovered_ws: Option<usize>,

    pub gpu_instance: wgpu::Instance,
    pub gpu_device: wgpu::Device,
    pub gpu_queue: wgpu::Queue,
    pub vello_renderer: vello::Renderer,
    pub icon_cache: HashMap<String, vello::peniko::ImageData>,
}

fn ensure_bar_intermediate(surface: &mut BarSurface, device: &wgpu::Device) {
    if surface.intermediate_texture.is_some()
        && surface.intermediate_texture.as_ref().unwrap().width() == surface.w as u32
        && surface.intermediate_texture.as_ref().unwrap().height() == surface.h as u32
    {
        return;
    }
    let intermediate = device.create_texture(&wgpu::TextureDescriptor {
        label: Some("mist-bar-intermediate"),
        size: wgpu::Extent3d { width: surface.w as u32, height: surface.h as u32, depth_or_array_layers: 1 },
        mip_level_count: 1,
        sample_count: 1,
        dimension: wgpu::TextureDimension::D2,
        usage: wgpu::TextureUsages::STORAGE_BINDING | wgpu::TextureUsages::TEXTURE_BINDING,
        format: wgpu::TextureFormat::Rgba8Unorm,
        view_formats: &[],
    });
    let view = intermediate.create_view(&wgpu::TextureViewDescriptor::default());
    surface.intermediate_texture = Some(intermediate);
    surface.intermediate_view = Some(view);
    surface.blitter = Some(wgpu::util::TextureBlitter::new(device, surface.surface_format));
}

fn ensure_launcher_intermediate(surface: &mut LauncherSurface, device: &wgpu::Device) {
    if surface.intermediate_texture.is_some()
        && surface.intermediate_texture.as_ref().unwrap().width() == surface.w as u32
        && surface.intermediate_texture.as_ref().unwrap().height() == surface.h as u32
    {
        return;
    }
    let intermediate = device.create_texture(&wgpu::TextureDescriptor {
        label: Some("mist-launcher-intermediate"),
        size: wgpu::Extent3d { width: surface.w as u32, height: surface.h as u32, depth_or_array_layers: 1 },
        mip_level_count: 1,
        sample_count: 1,
        dimension: wgpu::TextureDimension::D2,
        usage: wgpu::TextureUsages::STORAGE_BINDING | wgpu::TextureUsages::TEXTURE_BINDING,
        format: wgpu::TextureFormat::Rgba8Unorm,
        view_formats: &[],
    });
    let view = intermediate.create_view(&wgpu::TextureViewDescriptor::default());
    surface.intermediate_texture = Some(intermediate);
    surface.intermediate_view = Some(view);
    surface.blitter = Some(wgpu::util::TextureBlitter::new(device, surface.surface_format));
}

impl State {
    pub fn commit_bar(&mut self, scene: Scene) {
        let Some(ref wgpu_surface) = self.bar.wgpu_surface else { return };
        let output = match wgpu_surface.get_current_texture() {
            wgpu::CurrentSurfaceTexture::Success(t) => t,
            wgpu::CurrentSurfaceTexture::Suboptimal(t) => t,
            wgpu::CurrentSurfaceTexture::Timeout => { eprintln!("[mist] bar get_current_texture: Timeout"); return; }
            wgpu::CurrentSurfaceTexture::Occluded => { eprintln!("[mist] bar get_current_texture: Occluded"); return; }
            wgpu::CurrentSurfaceTexture::Outdated => { eprintln!("[mist] bar get_current_texture: Outdated"); return; }
            wgpu::CurrentSurfaceTexture::Lost => { eprintln!("[mist] bar get_current_texture: Lost"); return; }
            wgpu::CurrentSurfaceTexture::Validation => { eprintln!("[mist] bar get_current_texture: Validation"); return; }
        };
        ensure_bar_intermediate(&mut self.bar, &self.gpu_device);
        let Some(ref intermediate_view) = self.bar.intermediate_view else { return };
        let Some(ref blitter) = self.bar.blitter else { return };
        let params = vello::RenderParams {
            base_color: vello::peniko::Color::TRANSPARENT,
            width: self.bar.w as u32,
            height: self.bar.h as u32,
            antialiasing_method: vello::AaConfig::Msaa16,
        };
        if let Err(e) = self.vello_renderer.render_to_texture(&self.gpu_device, &self.gpu_queue, &scene, intermediate_view, &params) {
            eprintln!("[mist] bar render_to_texture: {e:?}");
            return;
        }
        let output_view = output.texture.create_view(&wgpu::TextureViewDescriptor::default());
        let mut encoder = self.gpu_device.create_command_encoder(&wgpu::CommandEncoderDescriptor { label: Some("mist-bar-blit") });
        blitter.copy(&self.gpu_device, &mut encoder, intermediate_view, &output_view);
        self.gpu_queue.submit(std::iter::once(encoder.finish()));
        self.bar.surface.frame(&self.qh, BarCb);
        output.present();
        self.bar.frame_pending = true;
        let _ = self.conn.flush();
    }

    /// Render the launcher if it is dirty, configured, and no frame is in flight.
    /// Coalesces all dirty-flag-based render requests into a single dispatch per
    /// frame cycle, preventing redundant GPU submissions on high-frequency
    /// events (scroll, key repeat, pointer motion).
    pub fn flush_launcher_render(&mut self) {
        if self.launcher.dirty && self.launcher.configured && !self.launcher.frame_pending {
            if self.launcher.visible {
                let (scene, panel) = crate::launcher::render_launcher(self);
                self.launcher.panel = Some(panel);
                self.commit_launcher(scene);
            } else {
                self.launcher.dirty = false;
            }
        }
    }

    pub fn commit_launcher(&mut self, scene: Scene) {
        let Some(ref wgpu_surface) = self.launcher.wgpu_surface else { return };
        let output = match wgpu_surface.get_current_texture() {
            wgpu::CurrentSurfaceTexture::Success(t) => t,
            wgpu::CurrentSurfaceTexture::Suboptimal(t) => t,
            wgpu::CurrentSurfaceTexture::Timeout => { eprintln!("[mist] launcher get_current_texture: Timeout"); return; }
            wgpu::CurrentSurfaceTexture::Occluded => { eprintln!("[mist] launcher get_current_texture: Occluded"); return; }
            wgpu::CurrentSurfaceTexture::Outdated => { eprintln!("[mist] launcher get_current_texture: Outdated"); return; }
            wgpu::CurrentSurfaceTexture::Lost => { eprintln!("[mist] launcher get_current_texture: Lost"); return; }
            wgpu::CurrentSurfaceTexture::Validation => { eprintln!("[mist] launcher get_current_texture: Validation"); return; }
        };
        ensure_launcher_intermediate(&mut self.launcher, &self.gpu_device);
        let Some(ref intermediate_view) = self.launcher.intermediate_view else { return };
        let Some(ref blitter) = self.launcher.blitter else { return };
        let params = vello::RenderParams {
            base_color: vello::peniko::Color::TRANSPARENT,
            width: self.launcher.w as u32,
            height: self.launcher.h as u32,
            antialiasing_method: vello::AaConfig::Msaa16,
        };
        if let Err(e) = self.vello_renderer.render_to_texture(&self.gpu_device, &self.gpu_queue, &scene, intermediate_view, &params) {
            eprintln!("[mist] launcher render_to_texture: {e:?}");
            return;
        }
        let output_view = output.texture.create_view(&wgpu::TextureViewDescriptor::default());
        let mut encoder = self.gpu_device.create_command_encoder(&wgpu::CommandEncoderDescriptor { label: Some("mist-launcher-blit") });
        blitter.copy(&self.gpu_device, &mut encoder, intermediate_view, &output_view);
        self.gpu_queue.submit(std::iter::once(encoder.finish()));
        if let Some(ref surface) = self.launcher.surface {
            surface.frame(&self.qh, LauncherCb);
        }
        output.present();
        self.launcher.frame_pending = true;
        let _ = self.conn.flush();
    }

    pub fn show_launcher(&mut self) {
        if self.launcher.visible { return }
        let surface = self.compositor.create_surface(&self.qh, ());
        let layer = self.layer_shell.get_layer_surface(
            &surface, None, Layer::Overlay, "mist-launcher".into(), &self.qh, (),
        );
        layer.set_anchor(Anchor::Top | Anchor::Bottom | Anchor::Left | Anchor::Right);
        layer.set_exclusive_zone(-1);
        layer.set_keyboard_interactivity(KeyboardInteractivity::Exclusive);
        surface.commit();
        self.launcher.surface = Some(surface);
        self.launcher.layer = Some(layer);
        self.launcher.visible = true;
        self.launcher.anim_show.start_forward(0.2);
        self.launcher.anim_hide = crate::ease::AnimState::new();
        self.launcher.configured = false;
        self.launcher.frame_pending = false;
        self.launcher.dirty = true;
        self.launcher.start_time = Instant::now();
        self.launcher.query.clear();
        self.launcher.scroll_offset = 0;
        self.launcher.view = launcher::LauncherView::AppList;

        if self.launcher.apps.is_empty() {
            self.launcher.apps = launcher::scan_apps();
        }
        if self.launcher.actions.is_empty() {
            self.launcher.actions = launcher::ACTIONS.iter().map(|a| launcher::LauncherAction {
                name: a.name, icon: a.icon, description: a.description, command: a.command,
            }).collect();
        }

        self.launcher.matching = (0..self.launcher.apps.len()).collect();
        self.launcher.matching_actions.clear();
        self.launcher.selection = 0;

        let _ = self.conn.flush();
    }

    pub fn update_launcher_filter(&mut self) {
        let q = &self.launcher.query;
        if q.is_empty() {
            self.launcher.calc_result = None;
            self.launcher.view = launcher::LauncherView::AppList;
            self.launcher.matching = (0..self.launcher.apps.len()).collect();
            self.launcher.matching_actions.clear();
            self.launcher.scroll_offset = 0;
            self.launcher.selection = 0;
            self.launcher.dirty = true;
            self.flush_launcher_render();
            return;
        }
        if let Some(stripped) = q.strip_prefix('>') {
            if stripped.trim_start().starts_with("calc ") {
                self.launcher.view = launcher::LauncherView::CalcResult;
                let expr = stripped.trim_start().strip_prefix("calc ").unwrap_or("").trim();
                self.launcher.calc_result = if expr.is_empty() {
                    None
                } else {
                    crate::calc::eval(expr).or_else(|| Some("Error".into()))
                };
                self.launcher.matching_actions = (0..self.launcher.actions.len()).collect();
                self.launcher.scroll_offset = 0;
                self.launcher.selection = 0;
                self.launcher.dirty = true;
                self.flush_launcher_render();
                return;
            }
            let (field, actual_query) = launcher::parse_search_prefix(q);
            if field != launcher::FIELD_DEFAULT {
                self.launcher.calc_result = None;
                self.launcher.view = launcher::LauncherView::AppList;
                let qq = if actual_query.is_empty() { "" } else { actual_query };
                let mut scored: Vec<(u32, usize)> = self.launcher.apps.iter().enumerate()
                    .filter_map(|(i, a)| Some((launcher::fuzzy_match_app(qq, a, field)?, i)))
                    .collect();
                scored.sort_by_key(|b| std::cmp::Reverse(b.0));
                self.launcher.matching = scored.into_iter().map(|(_, i)| i).collect();
                self.launcher.matching_actions.clear();
                self.launcher.scroll_offset = 0;
                if !self.launcher.matching.is_empty() {
                    self.launcher.selection = self.launcher.selection.min(self.launcher.matching.len() - 1);
                } else {
                    self.launcher.selection = 0;
                }
                eprintln!("[mist] filter: prefix mode, field={} query=\"{}\" matches={}", field, qq, self.launcher.matching.len());
            } else {
                self.launcher.calc_result = None;
                self.launcher.view = launcher::LauncherView::ActionList;
                let action_q = stripped.trim();
                let mut scored: Vec<(u32, usize)> = self.launcher.actions.iter().enumerate()
                    .filter_map(|(i, a)| Some((launcher::fuzzy_match(action_q, a.name)?, i)))
                    .collect();
                scored.sort_by_key(|b| std::cmp::Reverse(b.0));
                self.launcher.matching_actions = scored.into_iter().map(|(_, i)| i).collect();
                self.launcher.scroll_offset = 0;
                self.launcher.selection = 0;
                eprintln!("[mist] filter: action mode query=\"{}\" matches={}", action_q, self.launcher.matching_actions.len());
            }
        } else {
            self.launcher.calc_result = None;
            self.launcher.view = launcher::LauncherView::AppList;
            let mut scored: Vec<(u32, usize)> = self.launcher.apps.iter().enumerate()
                .filter_map(|(i, a)| Some((launcher::fuzzy_match_app(q, a, launcher::FIELD_DEFAULT)?, i)))
                .collect();
            scored.sort_by_key(|b| std::cmp::Reverse(b.0));
            self.launcher.matching = scored.into_iter().map(|(_, i)| i).collect();
            self.launcher.scroll_offset = 0;
            if !self.launcher.matching.is_empty() {
                self.launcher.selection = self.launcher.selection.min(self.launcher.matching.len() - 1);
            } else {
                self.launcher.selection = 0;
            }
            eprintln!("[mist] filter: app mode query=\"{}\" matches={}", q, self.launcher.matching.len());
        }
        self.launcher.dirty = true;
        self.flush_launcher_render();
    }

    pub fn ensure_selection_visible(&mut self) {
        let lay = launcher::compute_panel(self.launcher.w as f32, self.launcher.h as f32, 1.0);
        if lay.max_visible == 0 { return }
        let sel = self.launcher.selection;
        let scroll = &mut self.launcher.scroll_offset;
        if sel < *scroll {
            *scroll = sel;
        } else if sel >= *scroll + lay.max_visible {
            *scroll = sel.saturating_sub(lay.max_visible - 1);
        }
    }

    pub fn scroll_launcher(&mut self, delta: i32) {
        if delta == 0 { return }
        let old_offset = self.launcher.scroll_offset;
        let lay = launcher::compute_panel(self.launcher.w as f32, self.launcher.h as f32, 1.0);
        let len = match self.launcher.view {
            launcher::LauncherView::ActionList | launcher::LauncherView::CalcResult => self.launcher.matching_actions.len(),
            launcher::LauncherView::AppList => self.launcher.matching.len(),
        };
        let max_scroll = len.saturating_sub(lay.max_visible);
        if delta > 0 {
            self.launcher.scroll_offset = self.launcher.scroll_offset.saturating_add(delta as usize).min(max_scroll);
        } else {
            self.launcher.scroll_offset = self.launcher.scroll_offset.saturating_sub((-delta) as usize);
        }
        if self.launcher.scroll_offset == old_offset { return; }
        self.launcher.dirty = true;
    }

    pub fn hide_launcher(&mut self) {
        if !self.launcher.visible { return }
        if let Some(ref layer) = self.launcher.layer {
            layer.set_keyboard_interactivity(KeyboardInteractivity::None);
        }
        // Drop wgpu surface BEFORE destroying wl_surface: wgpu internally holds
        // a VkSurfaceKHR wrapping the wl_surface pointer. If we destroy the
        // wl_surface first, the Vulkan surface cleanup path may reference a
        // freed proxy, causing a stall or GPU-side error.
        self.launcher.wgpu_surface = None;
        let _ = self.conn.flush();
        if let Some(l) = self.launcher.layer.take() { l.destroy(); }
        if let Some(s) = self.launcher.surface.take() { s.destroy(); }
        self.launcher.configured = false;
        self.launcher.frame_pending = false;
        self.launcher.dirty = false;
        self.launcher.visible = false;
        self.launcher.anim_hide.start_reverse(0.15);
        self.launcher.view = launcher::LauncherView::AppList;
        self.launcher.matching_actions.clear();
        self.launcher.panel = None;
        let _ = self.conn.flush();
    }
}
