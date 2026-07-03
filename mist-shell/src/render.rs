use vello::kurbo::{Affine, BezPath, Rect, RoundedRect};
use vello::peniko::{Brush, Color, Fill};
use vello::Scene;

pub fn color(c: (u8, u8, u8, u8)) -> Color {
    Color::from_rgba8(c.0, c.1, c.2, c.3)
}

pub fn rounded_rect(x: f32, y: f32, w: f32, h: f32, r: f32) -> RoundedRect {
    RoundedRect::from_rect(Rect::new(x as f64, y as f64, (x + w) as f64, (y + h) as f64), r as f64)
}

pub fn fill_rect(scene: &mut Scene, x: f32, y: f32, w: f32, h: f32, c: Color) {
    let rect = Rect::new(x as f64, y as f64, (x + w) as f64, (y + h) as f64);
    scene.fill(Fill::NonZero, Affine::IDENTITY, &Brush::Solid(c), None, &rect);
}

pub fn fill_rounded_rect(scene: &mut Scene, x: f32, y: f32, w: f32, h: f32, r: f32, c: Color) {
    let rr = rounded_rect(x, y, w, h, r);
    scene.fill(Fill::NonZero, Affine::IDENTITY, &Brush::Solid(c), None, &rr);
}

pub fn stroke_rounded_rect(scene: &mut Scene, x: f32, y: f32, w: f32, h: f32, r: f32, width: f32, c: Color) {
    let rr = rounded_rect(x, y, w, h, r);
    scene.stroke(
        &vello::kurbo::Stroke::new(width as f64),
        Affine::IDENTITY,
        &Brush::Solid(c),
        None,
        &rr,
    );
}

fn build_tri(a: (f32, f32), b: (f32, f32), c: (f32, f32)) -> BezPath {
    let mut path = BezPath::new();
    path.move_to((a.0 as f64, a.1 as f64));
    path.line_to((b.0 as f64, b.1 as f64));
    path.line_to((c.0 as f64, c.1 as f64));
    path.close_path();
    path
}

fn build_quad(a: (f32, f32), b: (f32, f32), c: (f32, f32), d: (f32, f32)) -> BezPath {
    let mut path = BezPath::new();
    path.move_to((a.0 as f64, a.1 as f64));
    path.line_to((b.0 as f64, b.1 as f64));
    path.line_to((c.0 as f64, c.1 as f64));
    path.line_to((d.0 as f64, d.1 as f64));
    path.close_path();
    path
}

// ============================================================
// Speaker icon (on / muted)
// ============================================================
pub fn draw_speaker(scene: &mut Scene, x: f32, y: f32, size: f32, muted: bool, c: (u8, u8, u8, u8)) {
    let col = color(c);
    let s = size;

    let body_w = s * 0.38;
    let body_h = s * 0.55;
    let bx = x + s * 0.02;
    let by = y + (s - body_h) / 2.0;
    fill_rounded_rect(scene, bx, by, body_w, body_h, s * 0.08, col);

    let tri_left = bx + body_w;
    let tri_right = tri_left + s * 0.28;
    let tri_top = by + s * 0.08;
    let tri_bot = by + body_h - s * 0.08;
    let tri = build_tri(
        (tri_left, tri_top),
        (tri_right, y + s / 2.0),
        (tri_left, tri_bot),
    );
    scene.fill(Fill::NonZero, Affine::IDENTITY, &Brush::Solid(col), None, &tri);

    if muted {
        let g = s * 0.12;
        let w = s * 0.12;
        let l1 = build_quad(
            (x + g - w * 0.3, y + g),
            (x + g + w * 0.7, y + g),
            (x + s - g + w * 0.3, y + s - g),
            (x + s - g - w * 0.7, y + s - g),
        );
        scene.fill(Fill::NonZero, Affine::IDENTITY, &Brush::Solid(col), None, &l1);

        let l2 = build_quad(
            (x + s - g - w * 0.7, y + g),
            (x + s - g + w * 0.3, y + g),
            (x + g + w * 0.7, y + s - g),
            (x + g - w * 0.3, y + s - g),
        );
        scene.fill(Fill::NonZero, Affine::IDENTITY, &Brush::Solid(col), None, &l2);
    }
}

// ============================================================
// WiFi icon (three bars)
// ============================================================
pub fn draw_wifi(scene: &mut Scene, x: f32, y: f32, size: f32, connected: bool, c: (u8, u8, u8, u8)) {
    let col = color(c);
    let s = size;
    if !connected { return; }

    let bar_w = s * 0.15;
    let gap = s * 0.07;
    let total_w = 3.0 * bar_w + 2.0 * gap;
    let start_x = x + (s - total_w) / 2.0;
    let heights = [s * 0.25, s * 0.50, s * 0.80];

    for i in 0..3 {
        let bx = start_x + i as f32 * (bar_w + gap);
        let bh = heights[i];
        let by = y + s - bh;
        fill_rect(scene, bx, by, bar_w, bh, col);
    }
    fill_rounded_rect(scene, x + s / 2.0 - 1.5, y + s - 4.0, 3.0, 3.0, 1.5, col);
}

// ============================================================
// Battery icon
// ============================================================
pub fn draw_battery(scene: &mut Scene, x: f32, y: f32, size: f32, pct: u8, charging: bool, c: (u8, u8, u8, u8)) {
    let col = color(c);
    let s = size;

    let body_w = s * 0.65;
    let body_h = s * 0.48;
    let body_x = x + (s - body_w) / 2.0;
    let body_y = y + (s - body_h) / 2.0;

    let tab_w = s * 0.08;
    let tab_h = s * 0.20;
    let tab_x = body_x + body_w;
    let tab_y = y + (s - tab_h) / 2.0;
    fill_rect(scene, tab_x, tab_y, tab_w, tab_h, col);

    stroke_rounded_rect(scene, body_x, body_y, body_w, body_h, s * 0.06, 1.5, col);

    let fm = 2.5;
    let fill_w = (body_w - fm * 2.0) * (pct as f32 / 100.0).min(1.0).max(0.0);
    let fill_h = body_h - fm * 2.0;
    if fill_w > 0.0 {
        fill_rect(scene, body_x + fm, body_y + fm, fill_w, fill_h, col);
    }

    if charging {
        let cx = body_x + body_w / 2.0;
        let cy = body_y + body_h / 2.0;
        let bs = s * 0.08;
        let bolt = build_quad(
            (cx - bs, body_y - 1.0),
            (cx + bs, body_y - 1.0),
            (cx, cy),
            (cx + bs * 0.5, cy),
        );
        scene.fill(Fill::NonZero, Affine::IDENTITY, &Brush::Solid(col), None, &bolt);

        let bolt2 = build_quad(
            (cx + bs, body_y + body_h + 1.0),
            (cx - bs, body_y + body_h + 1.0),
            (cx, cy),
            (cx - bs * 0.5, cy),
        );
        scene.fill(Fill::NonZero, Affine::IDENTITY, &Brush::Solid(col), None, &bolt2);
    }
}

// ============================================================
// Power icon
// ============================================================
pub fn draw_power(scene: &mut Scene, x: f32, y: f32, size: f32, c: (u8, u8, u8, u8)) {
    let col = color(c);
    let s = size;

    let stem_w = s * 0.18;
    let stem_h = s * 0.45;
    let stem_x = x + (s - stem_w) / 2.0;
    let stem_y = y + s * 0.05;
    fill_rect(scene, stem_x, stem_y, stem_w, stem_h, col);

    let cs = s * 0.65;
    let cx = x + (s - cs) / 2.0;
    let cy = y + (s - cs) / 2.0 + s * 0.10;
    stroke_rounded_rect(scene, cx, cy, cs, cs, cs / 2.0, s * 0.14, col);
}
