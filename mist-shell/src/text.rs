use cosmic_text::{Attrs, Buffer, Color as CosmicColor, FontSystem, Metrics, Shaping, SwashCache};
use vello::kurbo::{Affine, Rect};
use vello::peniko::{Brush, Color, Fill};
use vello::Scene;

pub fn init_font_system() -> FontSystem {
    let mut fs = FontSystem::new();

    let home = std::env::var("HOME").unwrap_or_default();
    let dirs = [
        "/usr/share/fonts",
        "/run/current-system/sw/share/X11/fonts",
        "/run/current-system/fonts",
        &format!("{}/.fonts", home),
        &format!("{}/.local/share/fonts", home),
        &format!("{}/.nix-profile/share/fonts", home),
    ];

    for dir in dirs {
        load_fonts_recursive(&mut fs, dir);
    }

    let n = fs.db_mut().len();
    eprintln!("[mist] loaded {n} font faces");
    fs
}

fn load_fonts_recursive(fs: &mut FontSystem, dir: &str) {
    let Ok(d) = std::fs::read_dir(dir) else { return };
    for entry in d.flatten() {
        let path = entry.path();
        if path.is_dir() {
            load_fonts_recursive(fs, &path.to_string_lossy());
            continue;
        }
        let ext = path.extension().and_then(|e| e.to_str()).unwrap_or("");
        if matches!(ext, "ttf" | "otf" | "ttc") {
            if let Ok(data) = std::fs::read(&path) {
                fs.db_mut().load_font_data(data);
            }
        }
    }
}

pub fn text_width(font: &mut FontSystem, text: &str, size: f32) -> f32 {
    let mut b = Buffer::new(font, Metrics::new(size, (size * 1.4).ceil()));
    b.set_text(text, &Attrs::new(), Shaping::Basic, None);
    b.set_size(Some(8192.0), None);
    b.shape_until_scroll(font, true);
    b.layout_runs().flat_map(|r| r.glyphs.iter()).map(|g| (g.x + g.w).ceil()).fold(0.0, f32::max)
}

pub fn render_text(scene: &mut Scene, font: &mut FontSystem, swash: &mut SwashCache, text: &str, x: f32, y: f32, size: f32, color: CosmicColor) {
    let m = Metrics::new(size, (size * 1.4).ceil());
    let mut b = Buffer::new(font, m);
    b.set_text(text, &Attrs::new(), Shaping::Basic, None);
    b.set_size(Some(8192.0), Some((size * 1.4).ceil()));
    b.shape_until_scroll(font, true);
    
    b.draw(font, swash, color, |gx, gy, gw, gh, gc| {
        let rect = Rect::new(
            (x + gx as f32) as f64,
            (y + gy as f32) as f64,
            (x + gx as f32 + gw as f32) as f64,
            (y + gy as f32 + gh as f32) as f64,
        );
        let glyph_color = Color::from_rgba8(gc.r(), gc.g(), gc.b(), gc.a());
        scene.fill(Fill::NonZero, Affine::IDENTITY, &Brush::Solid(glyph_color), None, &rect);
    });
}
