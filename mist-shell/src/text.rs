use std::collections::HashMap;
use cosmic_text::{fontdb, Attrs, Buffer, Color as CosmicColor, FontSystem, Metrics, Shaping};
use vello::kurbo::Affine;
use vello::peniko::{Blob, Brush, Color, Fill, FontData};
use vello::{Glyph, Scene};

pub struct FontCache {
    map: HashMap<fontdb::ID, FontData>,
}

impl FontCache {
    pub fn new() -> Self {
        Self { map: HashMap::new() }
    }

    pub fn get_or_load(&mut self, font_sys: &FontSystem, id: fontdb::ID) -> &FontData {
        self.map.entry(id).or_insert_with(|| {
            let (bytes, index) = font_sys
                .db()
                .with_face_data(id, |data, idx| (data.to_vec(), idx))
                .expect("font face data must be accessible");
            FontData::new(Blob::from(bytes), index)
        })
    }
}

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

pub fn text_width(font: &mut FontSystem, text: &str, size: f32, family: &str) -> f32 {
    let mut b = Buffer::new(font, Metrics::new(size, (size * 1.4).ceil()));
    b.set_text(text, &Attrs::new().family(cosmic_text::Family::Name(family)), Shaping::Basic, None);
    b.set_size(Some(8192.0), None);
    b.shape_until_scroll(font, true);
    b.layout_runs()
        .flat_map(|r| r.glyphs.iter())
        .map(|g| (g.x + g.w).ceil())
        .fold(0.0, f32::max)
}

pub fn render_text(
    scene: &mut Scene,
    cache: &mut FontCache,
    font: &mut FontSystem,
    text: &str,
    x: f32,
    y: f32,
    size: f32,
    color: CosmicColor,
    family: &str,
) {
    let m = Metrics::new(size, (size * 1.4).ceil());
    let mut b = Buffer::new(font, m);
    b.set_text(text, &Attrs::new().family(cosmic_text::Family::Name(family)), Shaping::Basic, None);
    b.set_size(Some(8192.0), Some((size * 1.4).ceil()));
    b.shape_until_scroll(font, true);

    let vc = Color::from_rgba8(color.r(), color.g(), color.b(), color.a());

    for run in b.layout_runs() {
        let glyphs: Vec<Glyph> = run
            .glyphs
            .iter()
            .map(|g| Glyph {
                id: g.glyph_id as u32,
                x: g.x,
                y: g.y,
            })
            .collect();

        if glyphs.is_empty() {
            continue;
        }

        let fid = run.glyphs[0].font_id;
        let fd = cache.get_or_load(font, fid);

        scene
            .draw_glyphs(fd)
            .font_size(size)
            .brush(&Brush::Solid(vc))
            .transform(Affine::translate((x as f64, y as f64)))
            .draw(Fill::NonZero, glyphs.into_iter());
    }
}
