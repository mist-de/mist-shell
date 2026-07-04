// ---- Spacing & Padding ----
pub const SPACE_XS: f32 = 4.0;
pub const SPACE_SM: f32 = 8.0;
pub const SPACE_MD: f32 = 12.0;
pub const SPACE_LG: f32 = 16.0;
pub const SPACE_XL: f32 = 28.0;

pub const PAD_XS: f32 = 4.0;
pub const PAD_SM: f32 = 8.0;
pub const PAD_MD: f32 = 12.0;
pub const PAD_LG: f32 = 16.0;
pub const PAD_XL: f32 = 28.0;

// ---- Rounding ----
pub const RADIUS_XS: f32 = 4.0;
pub const RADIUS_SM: f32 = 8.0;
pub const RADIUS_MD: f32 = 12.0;
pub const RADIUS_LG: f32 = 16.0;
pub const RADIUS_XL: f32 = 28.0;
pub const RADIUS_FULL: f32 = 999.0;

// ---- Font Sizes (Point sizes converted to pixels approx) ----
pub const FONT_SMALL: f32 = 11.0;
pub const FONT_SMALLER: f32 = 12.0;
pub const FONT_NORMAL: f32 = 13.0;
pub const FONT_LARGER: f32 = 15.0;
pub const FONT_LARGE: f32 = 18.0;

// ---- Bar sizing ----
pub const BAR_INNER_W: f32 = 40.0;
pub const BAR_TOTAL_W: f32 = 48.0;

// ---- Module sizing ----
pub const MODULE_PILL_W: f32 = 28.0;
pub const MODULE_PILL_H: f32 = 28.0;
pub const MODULE_ITEM_H: f32 = 36.0;

// ---- Workspace item ----
pub const WS_ITEM_W: f32 = 32.0;
pub const WS_ITEM_H: f32 = 32.0;
pub const WS_LABEL_SIZE: f32 = FONT_SMALLER;
pub const WS_SPACING: f32 = SPACE_XS;
pub const WS_OCCUPIED_DOT: f32 = 4.0;

// ---- Clock ----
pub const CLOCK_TIME_SIZE: f32 = FONT_LARGE;
pub const CLOCK_DATE_SIZE: f32 = FONT_NORMAL;

// ---- Status icons ----
pub const STATUS_ICON_SIZE: f32 = 18.0;

// ---- M3 Dark Palette ----
pub const C_M3_BACKGROUND: (u8, u8, u8, u8) = (0x19, 0x11, 0x14, 0xFF);
pub const C_M3_ON_BACKGROUND: (u8, u8, u8, u8) = (0xEF, 0xDF, 0xE2, 0xFF);
pub const C_M3_SURFACE: (u8, u8, u8, u8) = (0x19, 0x11, 0x14, 0xFF);
pub const C_M3_SURFACE_CONTAINER: (u8, u8, u8, u8) = (0x26, 0x1D, 0x20, 0xFF);
pub const C_M3_SURFACE_CONTAINER_HIGH: (u8, u8, u8, u8) = (0x31, 0x28, 0x2A, 0xFF);
pub const C_M3_ON_SURFACE: (u8, u8, u8, u8) = (0xEF, 0xDF, 0xE2, 0xFF);
pub const C_M3_ON_SURFACE_VARIANT: (u8, u8, u8, u8) = (0xD5, 0xC2, 0xC6, 0xFF);
pub const C_M3_OUTLINE_VARIANT: (u8, u8, u8, u8) = (0x51, 0x43, 0x47, 0xFF);
pub const C_M3_PRIMARY: (u8, u8, u8, u8) = (0xFF, 0xB0, 0xCA, 0xFF);
pub const C_M3_ON_PRIMARY: (u8, u8, u8, u8) = (0x54, 0x1D, 0x34, 0xFF);
pub const C_M3_SECONDARY: (u8, u8, u8, u8) = (0xE2, 0xBD, 0xC7, 0xFF);
pub const C_M3_TERTIARY: (u8, u8, u8, u8) = (0xF0, 0xBC, 0x95, 0xFF);
pub const C_M3_ON_TERTIARY: (u8, u8, u8, u8) = (0x48, 0x29, 0x0C, 0xFF);
pub const C_M3_ERROR: (u8, u8, u8, u8) = (0xFF, 0xB4, 0xAB, 0xFF);

// ---- Semantic Aliases ----
pub const C_BAR_BG: (u8, u8, u8, u8) = (0x26, 0x1D, 0x20, 0xCC); // surfaceContainer with alpha
pub const C_BAR_BORDER: (u8, u8, u8, u8) = (0x51, 0x43, 0x47, 0x33); // outlineVariant with alpha
pub const C_MODULE_HOVER: (u8, u8, u8, u8) = (0xEF, 0xDF, 0xE2, 0x1A); // onSurface with alpha
pub const C_WS_ACTIVE_BG: (u8, u8, u8, u8) = C_M3_PRIMARY;
pub const C_WS_ACTIVE_TEXT: (u8, u8, u8, u8) = C_M3_ON_PRIMARY;
pub const C_WS_OCCUPIED_DOT: (u8, u8, u8, u8) = C_M3_ON_SURFACE_VARIANT;
pub const C_STATUS_ON: (u8, u8, u8, u8) = C_M3_SECONDARY;
pub const C_STATUS_OFF: (u8, u8, u8, u8) = C_M3_ON_SURFACE_VARIANT;
pub const C_CLOCK_TIME: (u8, u8, u8, u8) = C_M3_TERTIARY;
pub const C_CLOCK_DATE: (u8, u8, u8, u8) = C_M3_ON_SURFACE_VARIANT;
pub const C_POWER: (u8, u8, u8, u8) = C_M3_ERROR;
