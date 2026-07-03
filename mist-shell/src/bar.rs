use vello::Scene;

use crate::render::{draw_battery, draw_power, draw_speaker, draw_wifi, fill_rounded_rect, stroke_rounded_rect, color};
use crate::state::{State, Tag};
use crate::text::{render_text, text_width};
use crate::tokens::*;
use cosmic_text::{FontSystem, SwashCache};

fn draw_capsule(scene: &mut Scene, x: f32, y: f32, w: f32, h: f32, c: (u8, u8, u8, u8), radius: f32) {
    fill_rounded_rect(scene, x, y, w, h, radius, color(c));
}

fn c2cosmic(c: (u8, u8, u8, u8)) -> cosmic_text::Color {
    cosmic_text::Color::rgba(c.0, c.1, c.2, c.3)
}

pub struct RenderCtx<'a> {
    pub workspaces: &'a [(String, Tag)],
    pub font: &'a mut FontSystem,
    pub swash: &'a mut SwashCache,
    pub clock: &'a str,
    pub date: &'a str,
    pub volume_muted: bool,
    pub network_connected: bool,
    pub battery: Option<u8>,
    pub battery_charging: bool,
    pub hovered_ws: Option<usize>,
}

pub struct WorkspacesModule;

impl WorkspacesModule {
    pub fn height(&self, n: usize) -> f32 {
        n as f32 * WS_ITEM_H + (n.saturating_sub(1)) as f32 * WS_SPACING
    }

    pub fn render(&self, scene: &mut Scene, ctx: &mut RenderCtx, x: f32, y: f32, w: f32) {
        let item_x = x + (w - WS_ITEM_W) / 2.0;
        let mut cy = y;
        for (i, (name, tag)) in ctx.workspaces.iter().enumerate() {
            let item_y = cy;
            let is_active = tag.active;
            let is_occupied = tag.occupied;

            if is_active {
                draw_capsule(scene, item_x, item_y, WS_ITEM_W, WS_ITEM_H, C_WS_ACTIVE_BG, RADIUS_FULL);
            } else if Some(i) == ctx.hovered_ws {
                draw_capsule(scene, item_x, item_y, WS_ITEM_W, WS_ITEM_H, C_MODULE_HOVER, RADIUS_FULL);
            }

            if !is_active && is_occupied {
                let dot_x = item_x + WS_ITEM_W - 12.0;
                let dot_y = item_y + 6.0;
                draw_capsule(scene, dot_x, dot_y, WS_OCCUPIED_DOT, WS_OCCUPIED_DOT, C_WS_OCCUPIED_DOT, RADIUS_FULL);
            }

            let label_col = if is_active { C_WS_ACTIVE_TEXT } else { C_TEXT_ON_SURFACE };
            let tw = text_width(ctx.font, name, WS_LABEL_SIZE);
            render_text(scene, ctx.font, ctx.swash, name,
                item_x + (WS_ITEM_W - tw) / 2.0,
                item_y + (WS_ITEM_H - WS_LABEL_SIZE) / 2.0,
                WS_LABEL_SIZE, c2cosmic(label_col));

            cy += WS_ITEM_H + WS_SPACING;
        }
    }
}

pub struct OsIconModule;

impl OsIconModule {
    pub fn render(&self, scene: &mut Scene, _ctx: &mut RenderCtx, x: f32, y: f32, w: f32) {
        let px = x + (w - MODULE_PILL_W) / 2.0;
        let py = y + (MODULE_ITEM_H - MODULE_PILL_H) / 2.0;
        draw_capsule(scene, px, py, MODULE_PILL_W, MODULE_PILL_H, C_ACCENT, RADIUS_FULL);
        let mx = px + MODULE_PILL_W / 2.0 - 5.0;
        let my = py + MODULE_PILL_H / 2.0 - 2.0;
        draw_capsule(scene, mx, my, 10.0, 4.0, C_WS_ACTIVE_TEXT, 2.0);
    }
}

pub struct ClockModule;

impl ClockModule {
    pub fn height(&self) -> f32 { 54.0 }

    pub fn render(&self, scene: &mut Scene, ctx: &mut RenderCtx, x: f32, y: f32, w: f32) {
        let cx = x + w / 2.0;
        let tw = text_width(ctx.font, ctx.clock, CLOCK_TIME_SIZE);
        render_text(scene, ctx.font, ctx.swash, ctx.clock,
            cx - tw / 2.0, y + 8.0, CLOCK_TIME_SIZE, c2cosmic(C_CLOCK_TIME));
        let dw = text_width(ctx.font, ctx.date, CLOCK_DATE_SIZE);
        render_text(scene, ctx.font, ctx.swash, ctx.date,
            cx - dw / 2.0, y + 30.0, CLOCK_DATE_SIZE, c2cosmic(C_CLOCK_DATE));
    }
}

pub struct StatusIconsModule;

impl StatusIconsModule {
    pub fn height(&self) -> f32 { MODULE_ITEM_H * 3.0 }

    pub fn render(&self, scene: &mut Scene, ctx: &mut RenderCtx, x: f32, y: f32, w: f32) {
        let cx = x + w / 2.0;
        let mut cy = y;
        let icon_x = cx - STATUS_ICON_SIZE / 2.0;

        let acol = if ctx.volume_muted { C_STATUS_OFF } else { C_STATUS_ON };
        draw_speaker(scene, icon_x, cy + (MODULE_ITEM_H - STATUS_ICON_SIZE) / 2.0, STATUS_ICON_SIZE, ctx.volume_muted, acol);
        cy += MODULE_ITEM_H;

        let ncol = if ctx.network_connected { C_STATUS_ON } else { C_STATUS_OFF };
        draw_wifi(scene, icon_x, cy + (MODULE_ITEM_H - STATUS_ICON_SIZE) / 2.0, STATUS_ICON_SIZE, ctx.network_connected, ncol);
        cy += MODULE_ITEM_H;

        if let Some(pct) = ctx.battery {
            let bcol = if pct <= 15 { C_ERROR } else { C_STATUS_ON };
            let by = cy + (MODULE_ITEM_H - STATUS_ICON_SIZE - 12.0) / 2.0;
            draw_battery(scene, icon_x, by, STATUS_ICON_SIZE, pct, ctx.battery_charging, bcol);
            let ps = format!("{}%", pct);
            let pw = text_width(ctx.font, &ps, 9.0);
            render_text(scene, ctx.font, ctx.swash, &ps,
                cx - pw / 2.0, by + STATUS_ICON_SIZE + 2.0, 9.0, c2cosmic(bcol));
        }
    }
}

pub struct PowerModule;

impl PowerModule {
    pub fn render(&self, scene: &mut Scene, _ctx: &mut RenderCtx, x: f32, y: f32, w: f32) {
        let px = x + (w - MODULE_PILL_W) / 2.0;
        let py = y + (MODULE_ITEM_H - MODULE_PILL_H) / 2.0;
        draw_capsule(scene, px, py, MODULE_PILL_W, MODULE_PILL_H, C_POWER, RADIUS_FULL);
        draw_power(scene, px + (MODULE_PILL_W - 16.0) / 2.0, py + (MODULE_PILL_H - 16.0) / 2.0, 16.0, C_WS_ACTIVE_TEXT);
    }
}

pub fn render_bar(state: &mut State) -> Scene {
    let w = state.bar.w.max(1) as u32;
    let h = state.bar.h.max(1) as u32;

    let workspaces = &state.workspaces[..];
    let font = &mut state.font;
    let swash = &mut state.swash;
    let clock = &state.clock[..];
    let date = &state.date[..];
    let volume_muted = state.status.volume_muted;
    let network_connected = state.status.network_connected;
    let battery = state.status.battery;
    let battery_charging = state.status.battery_charging;
    let hovered_ws = state.hovered_ws;

    let mut scene = Scene::new();

    let mut ctx = RenderCtx { workspaces, font, swash, clock, date, volume_muted, network_connected, battery, battery_charging, hovered_ws };

    let bar_x = 0.0;
    let bar_y = 0.0;
    let bar_w = w as f32;
    let bar_h = h as f32;
    let inner_x = bar_x + PAD_XS;
    let inner_w = BAR_INNER_W;

    draw_capsule(&mut scene, bar_x, bar_y, bar_w, bar_h, C_BAR_BG, RADIUS_LG);
    stroke_rounded_rect(&mut scene, bar_x, bar_y, bar_w, bar_h, RADIUS_LG, 1.0, color(C_BAR_BORDER));

    let os_icon = OsIconModule;
    let ws_mod = WorkspacesModule;
    let status_mod = StatusIconsModule;
    let clock_mod = ClockModule;
    let power_mod = PowerModule;

    let os_h = MODULE_ITEM_H;
    let ws_h = ws_mod.height(ctx.workspaces.len());
    let status_h = status_mod.height();
    let clock_h = clock_mod.height();
    let power_h = MODULE_ITEM_H;

    let fixed_h = os_h + ws_h + status_h + clock_h + power_h;
    let avail_h = bar_h - PAD_LG * 2.0;

    let top_spacer = ((avail_h - fixed_h) / 3.0).max(SPACE_SM);
    let mid_spacer = top_spacer;
    let bottom_flex = (avail_h - fixed_h - top_spacer - mid_spacer).max(SPACE_SM);

    let mut cy = bar_y + PAD_LG;

    os_icon.render(&mut scene, &mut ctx, inner_x, cy, inner_w);
    cy += os_h + top_spacer;

    ws_mod.render(&mut scene, &mut ctx, inner_x, cy, inner_w);
    cy += ws_h + mid_spacer;

    status_mod.render(&mut scene, &mut ctx, inner_x, cy, inner_w);
    cy += status_h + SPACE_XS;

    clock_mod.render(&mut scene, &mut ctx, inner_x, cy, inner_w);
    cy += clock_h + bottom_flex;

    power_mod.render(&mut scene, &mut ctx, inner_x, cy, inner_w);

    state.bar.dirty = false;
    scene
}

pub fn hit_test_workspace(state: &State, x: f64, y: f64) -> Option<usize> {
    let bar_w = state.bar.w as f32;
    let bar_h = state.bar.h as f32;
    let xf = x as f32;
    let yf = y as f32;
    if xf < 0.0 || xf > bar_w { return None; }

    let inner_x = PAD_XS;
    let item_x = inner_x + (BAR_INNER_W - WS_ITEM_W) / 2.0;

    let os_h = MODULE_ITEM_H;
    let status_h = MODULE_ITEM_H * 3.0;
    let clock_h = 54.0;
    let power_h = MODULE_ITEM_H;

    let n = state.workspaces.len();
    let ws_h = n as f32 * WS_ITEM_H + (n.saturating_sub(1)) as f32 * WS_SPACING;
    let fixed_h = os_h + ws_h + status_h + clock_h + power_h;
    let avail_h = bar_h - PAD_LG * 2.0;
    let top_spacer = ((avail_h - fixed_h) / 3.0).max(SPACE_SM);
    let ws_y = PAD_LG + os_h + top_spacer;

    let mut w_cy = ws_y;
    for (i, _) in state.workspaces.iter().enumerate() {
        if xf >= item_x && xf <= item_x + WS_ITEM_W
            && yf >= w_cy && yf <= w_cy + WS_ITEM_H {
            return Some(i);
        }
        w_cy += WS_ITEM_H + WS_SPACING;
    }
    None
}
