// ---- Noctalia color palette (dark) ----
pub const C_SURFACE: (u8, u8, u8, u8) = (0x07, 0x07, 0x22, 0xFF);
pub const C_ON_SURFACE: (u8, u8, u8, u8) = (0xF3, 0xED, 0xF7, 0xFF);
pub const C_PRIMARY: (u8, u8, u8, u8) = (0xFF, 0xF5, 0x9B, 0xFF);
pub const C_ON_PRIMARY: (u8, u8, u8, u8) = (0x0E, 0x0E, 0x43, 0xFF);
pub const C_SECONDARY: (u8, u8, u8, u8) = (0xA9, 0xAE, 0xFE, 0xFF);
pub const C_ON_SECONDARY: (u8, u8, u8, u8) = (0x0E, 0x0E, 0x43, 0xFF);
pub const C_TERTIARY: (u8, u8, u8, u8) = (0x9B, 0xFE, 0xCE, 0xFF);
pub const C_ERROR: (u8, u8, u8, u8) = (0xFD, 0x46, 0x63, 0xFF);
pub const C_SURFACE_VARIANT: (u8, u8, u8, u8) = (0x11, 0x11, 0x2D, 0xFF);
pub const C_ON_SURFACE_VARIANT: (u8, u8, u8, u8) = (0x7C, 0x80, 0xB4, 0xFF);

// ---- Bar sizing (from Noctalia Style) ----
pub const BAR_THICKNESS: f32 = 34.0;
pub const BAR_RADIUS: f32 = 12.0;
pub const BAR_PADDING: f32 = 14.0;
pub const BAR_WIDGET_SPACING: f32 = 6.0;

// ---- Workspace pills (Noctalia proportional design) ----
pub const WS_BASE_SIZE: f32 = 16.0;
pub const WS_PILL_H: f32 = WS_BASE_SIZE;
pub const WS_ACTIVE_SCALE: f32 = 2.2;
pub const WS_INACTIVE_SCALE: f32 = 1.0;
pub const WS_PILL_PAD: f32 = WS_BASE_SIZE * 0.6;
pub const WS_PILL_GAP: f32 = 4.0;
pub const WS_LABEL_SIZE: f32 = 11.0;
pub const WS_EMPTY_ALPHA: f32 = 0.55;

// ---- Clock ----
pub const CLOCK_SIZE: f32 = 14.0;

// ---- Status icons ----
pub const STATUS_ICON_SIZE: f32 = 16.0;
pub const STATUS_SPACING: f32 = 6.0;

// ---- Legacy tokens (used by launcher.rs) ----
pub const RADIUS_SM: f32 = 8.0;
pub const RADIUS_LG: f32 = 16.0;
pub const RADIUS_FULL: f32 = 999.0;
pub const FONT_SMALL: f32 = 11.0;
pub const FONT_SMALLER: f32 = 12.0;
pub const FONT_NORMAL: f32 = 13.0;

// ---- Capsule padding (from Noctalia Style::barCapsulePadding) ----
pub const CAPSULE_PAD: f32 = 6.0;

// ---- Semantic aliases ----
pub const C_BAR_BG: (u8, u8, u8, u8) = C_SURFACE;
pub const C_BAR_TEXT: (u8, u8, u8, u8) = C_ON_SURFACE;
pub const C_WS_ACTIVE_BG: (u8, u8, u8, u8) = C_PRIMARY;
pub const C_WS_ACTIVE_TEXT: (u8, u8, u8, u8) = C_ON_PRIMARY;
pub const C_WS_OCCUPIED_BG: (u8, u8, u8, u8) = C_SECONDARY;
pub const C_WS_OCCUPIED_TEXT: (u8, u8, u8, u8) = C_ON_SECONDARY;
pub const C_WS_EMPTY_TEXT: (u8, u8, u8, u8) = C_ON_SURFACE_VARIANT;
pub const C_STATUS_ON: (u8, u8, u8, u8) = C_ON_SURFACE;
pub const C_STATUS_OFF: (u8, u8, u8, u8) = C_ON_SURFACE_VARIANT;
pub const C_CLOCK: (u8, u8, u8, u8) = C_ON_SURFACE;
