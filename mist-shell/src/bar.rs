use crate::render::*;
use crate::state::State;
use crate::tokens::*;

fn render_text(cr: &cairo::Context, x: f64, y: f64, text: &str, size: f64, col: (u8, u8, u8, u8)) {
    let layout = pangocairo::functions::create_layout(cr);
    layout.set_text(text);
    let desc = pango::FontDescription::from_string(&format!("GoogleSansFlex {}", size as i32));
    layout.set_font_description(Some(&desc));
    set_source_rgba(cr, col);
    cr.move_to(x, y);
    pangocairo::functions::show_layout(cr, &layout);
}

fn text_width(cr: &cairo::Context, text: &str, size: f64) -> f64 {
    let layout = pangocairo::functions::create_layout(cr);
    layout.set_text(text);
    let desc = pango::FontDescription::from_string(&format!("GoogleSansFlex {}", size as i32));
    layout.set_font_description(Some(&desc));
    let (w, _) = layout.pixel_size();
    w as f64
}

fn text_h(size: f64) -> f64 {
    (size * 1.4).ceil()
}

fn tl(text: &str, size: f64) -> f64 {
    text.len() as f64 * size * 0.55
}

fn apply_alpha(c: (u8, u8, u8, u8), a: f32) -> (u8, u8, u8, u8) {
    (c.0, c.1, c.2, (c.3 as f32 * a).min(255.0).max(0.0) as u8)
}

fn draw_workspace_pills(cr: &cairo::Context, workspaces: &[(String, crate::state::Tag)], x: f64, y: f64, h: f64) -> f64 {
    // Determine primary active workspace if multiple are active
    let active_indices: Vec<usize> = workspaces.iter()
        .enumerate()
        .filter(|(_, (_, t))| t.active)
        .map(|(i, _)| i)
        .collect();
    let primary_active = if active_indices.len() == 1 { Some(active_indices[0]) }
    else if active_indices.len() > 1 { Some(active_indices[0]) }
    else { None };

    let mut cx = x;
    for (i, (name, tag)) in workspaces.iter().enumerate() {
        let is_primary = Some(i) == primary_active;
        let is_active_multi = tag.active && !is_primary;

        let (bg, fg) = if tag.urgent {
            (C_ERROR, C_WS_ACTIVE_TEXT)
        } else if is_primary {
            (C_WS_ACTIVE_BG, C_WS_ACTIVE_TEXT)
        } else if is_active_multi || tag.occupied {
            (C_WS_OCCUPIED_BG, C_WS_OCCUPIED_TEXT)
        } else {
            (apply_alpha(C_SECONDARY, WS_EMPTY_ALPHA), C_WS_EMPTY_TEXT)
        };

        let label_size = WS_LABEL_SIZE as f64;
        let tw = text_width(cr, name, label_size);
        let base = WS_BASE_SIZE as f64;
        let min_w = if tag.active { base * WS_ACTIVE_SCALE as f64 } else { base * WS_INACTIVE_SCALE as f64 };
        let pad2 = 2.0 * WS_PILL_PAD as f64;
        let pill_w = min_w.max(tw + pad2);

        fill_rounded_rect(cr, cx, y, pill_w, h, h / 2.0, bg);

        render_text(cr,
            cx + (pill_w - tw) / 2.0,
            y + (h - text_h(label_size)) / 2.0,
            name, label_size, fg);

        cx += pill_w + WS_PILL_GAP as f64;
    }
    cx - x  // total width consumed
}

// ============================================================
// Clock (center zone)
// ============================================================

fn draw_clock_center(cr: &cairo::Context, clock: &str, cx: f64, y: f64) {
    let size = CLOCK_SIZE as f64;
    let tw = text_width(cr, clock, size);
    render_text(cr, cx - tw / 2.0, y, clock, size, C_CLOCK);
}

// ============================================================
// Status icons (right zone)
// ============================================================

fn draw_status_right(cr: &cairo::Context, status: &crate::status::SystemStatus, right_x: f64, y: f64) {
    let icon_sz = STATUS_ICON_SIZE as f64;
    let spacing = STATUS_SPACING as f64;

    let total_w = 3.0 * icon_sz + 2.0 * spacing;
    let mut cx = right_x - total_w;

    let acol = if status.volume_muted { C_STATUS_OFF } else { C_STATUS_ON };
    draw_speaker(cr, cx, y, icon_sz, status.volume_muted, acol);
    cx += icon_sz + spacing;

    let ncol = if status.network_connected { C_STATUS_ON } else { C_STATUS_OFF };
    draw_wifi(cr, cx, y, icon_sz, status.network_connected, ncol);
    cx += icon_sz + spacing;

    if let Some(pct) = status.battery {
        let bcol = if pct <= 15 { C_ERROR } else { C_STATUS_ON };
        draw_battery(cr, cx, y, icon_sz, pct, status.battery_charging, bcol);
    }
}

// ============================================================
// Main render entry point
// ============================================================

pub fn render_bar(state: &mut State) {
    let Some(ref mut shm_triple) = state.bar.shm else { return };

    let bar_w = state.bar.w.max(1) as f64;
    let bar_h = state.bar.h.max(1) as f64;
    let clock = state.clock.clone();
    let status = state.status.clone();
    let shown_ws: Vec<_> = state.workspaces.iter().take(9).cloned().collect();

    let slot = shm_triple.next_slot();
    let width = slot.width;
    let height = slot.height;
    let stride = slot.stride;

    let data = unsafe { slot.data_mut() };
    data.fill(0);
    let surface = unsafe {
        cairo::ImageSurface::create_for_data_unsafe(
            data.as_mut_ptr(),
            cairo::Format::ARgb32,
            width,
            height,
            stride,
        ).unwrap()
    };
    let _ = data;

    let cr = cairo::Context::new(&surface).unwrap();

    // Bar background
    fill_rect(&cr, 0.0, 0.0, bar_w, bar_h, C_BAR_BG);

    let pad = BAR_PADDING as f64;
    let left_x = pad;
    let right_x = bar_w - pad;

    let ws_h = WS_PILL_H as f64;
    let ws_y = (bar_h - ws_h) / 2.0;
    let clock_y = (bar_h - text_h(CLOCK_SIZE as f64)) / 2.0;
    let icon_y = (bar_h - STATUS_ICON_SIZE as f64) / 2.0;

    // Left zone: workspace pills
    if !shown_ws.is_empty() {
        draw_workspace_pills(&cr, &shown_ws, left_x, ws_y, ws_h);
    }

    // Center zone: clock
    if !clock.is_empty() {
        draw_clock_center(&cr, &clock, bar_w / 2.0, clock_y);
    }

    // Right zone: status icons
    draw_status_right(&cr, &status, right_x, icon_y);

    surface.flush();
}

/// Hit-test workspace pills for pointer events (horizontal layout).
pub fn hit_test_workspace(state: &State, x: f64, y: f64) -> Option<usize> {
    let bar_h = state.bar.h as f64;
    let pad = BAR_PADDING as f64;
    let left_x = pad;
    let ws_h = WS_PILL_H as f64;
    let ws_y = (bar_h - ws_h) / 2.0;

    if y < ws_y || y > ws_y + ws_h {
        return None;
    }

    let shown_ws: Vec<_> = state.workspaces.iter().take(9).cloned().collect();
    if shown_ws.is_empty() { return None; }

    let mut cx = left_x;
    for (i, (name, tag)) in shown_ws.iter().enumerate() {
        let base = WS_BASE_SIZE as f64;
        let min_w = if tag.active { base * WS_ACTIVE_SCALE as f64 } else { base * WS_INACTIVE_SCALE as f64 };
        let label_size = WS_LABEL_SIZE as f64;
        let tw = tl(name, label_size);
        let pad2 = 2.0 * WS_PILL_PAD as f64;
        let pill_w = min_w.max(tw + pad2);

        if x >= cx && x <= cx + pill_w {
            return Some(i);
        }
        cx += pill_w + WS_PILL_GAP as f64;
    }
    None
}
