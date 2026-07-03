// ---- Spacing ----
pub const SPACE_XS: f32 = 4.0;
pub const SPACE_SM: f32 = 8.0;

// ---- Padding ----
pub const PAD_XS: f32 = 4.0;
pub const PAD_LG: f32 = 16.0;

// ---- Rounding ----
pub const RADIUS_LG: f32 = 16.0;
pub const RADIUS_FULL: f32 = 999.0;

// ---- Bar sizing ----
pub const BAR_INNER_W: f32 = 40.0;
pub const BAR_PADDING: f32 = PAD_XS; // 4px
pub const BAR_TOTAL_W: f32 = BAR_INNER_W + BAR_PADDING * 2.0; // 48px

// ---- Module sizing ----
// OsIcon / Power: small accent pills
pub const MODULE_PILL_W: f32 = 28.0; // inner width for logo/power pills
pub const MODULE_PILL_H: f32 = 28.0;
pub const MODULE_ITEM_H: f32 = 36.0;

// ---- Workspace item (full-width, matching inner bar width minus internal padding) ----
pub const WS_ITEM_W: f32 = BAR_INNER_W - SPACE_SM; // 32px
pub const WS_ITEM_H: f32 = 36.0;
pub const WS_LABEL_SIZE: f32 = 13.0;
pub const WS_SPACING: f32 = SPACE_XS; // 4px
pub const WS_OCCUPIED_DOT: f32 = 4.0;

// ---- Clock ----
pub const CLOCK_TIME_SIZE: f32 = 11.0;
pub const CLOCK_DATE_SIZE: f32 = 9.0;

// ---- Status icons ----
pub const STATUS_ICON_SIZE: f32 = 14.0;

// ---- Colors (Material 3 Dark tonal palette, matching caelestia) ----
pub const C_BAR_BG: (u8, u8, u8, u8) = (0x1E, 0x1E, 0x2E, 0xC8);
pub const C_BAR_BORDER: (u8, u8, u8, u8) = (0xCD, 0xD6, 0xF4, 0x08);
pub const C_MODULE_HOVER: (u8, u8, u8, u8) = (0xCD, 0xD6, 0xF4, 0x12);
pub const C_ACCENT: (u8, u8, u8, u8) = (0x7A, 0xA2, 0xF7, 0xFF);
pub const C_TEXT_ON_SURFACE: (u8, u8, u8, u8) = (0xCD, 0xD6, 0xF4, 0xFF);

pub const C_ERROR: (u8, u8, u8, u8) = (0xF3, 0x8B, 0x8B, 0xFF);
pub const C_WS_ACTIVE_BG: (u8, u8, u8, u8) = (0x7A, 0xA2, 0xF7, 0xFF);
pub const C_WS_ACTIVE_TEXT: (u8, u8, u8, u8) = (0xFF, 0xFF, 0xFF, 0xFF);
pub const C_WS_OCCUPIED_DOT: (u8, u8, u8, u8) = (0x6C, 0x70, 0x86, 0xFF);
pub const C_STATUS_ON: (u8, u8, u8, u8) = (0xA6, 0xAD, 0xC8, 0xFF);
pub const C_STATUS_OFF: (u8, u8, u8, u8) = (0x6C, 0x70, 0x86, 0xFF);
pub const C_CLOCK_TIME: (u8, u8, u8, u8) = (0xA6, 0xAD, 0xC8, 0xFF);
pub const C_CLOCK_DATE: (u8, u8, u8, u8) = (0x6C, 0x70, 0x86, 0xFF);
pub const C_POWER: (u8, u8, u8, u8) = (0xF3, 0x8B, 0x8B, 0xFF);
