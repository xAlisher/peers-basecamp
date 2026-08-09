.pragma library

// Peers design tokens.
//
// A JS library, NOT a QML singleton, deliberately: a singleton needs a qmldir
// entry, and qml/qmldir is BUILDER-OWNED — it carries
// "module com.logos.module.peers_ui", which is how the host registers the view.
// Shipping our own qmldir replaces that line and the plugin silently fails to
// load. See fails/2026-08-09-*.md.
//
// Source of truth: src/theme/colors.ts in logos-chat-android (NOT its stale
// docs/theme.md, which still says the accent is emerald #10B981; it is orange
// #FF5000). Full citations in docs/DESIGN-SPEC.md. Peers is dark-only.

//
// The Peers token set, hardcoded (ADR 0005).
//
// Source of truth is `src/theme/{colors,typography,spacing}.ts` in
// logos-chat-android — NOT that repo's docs/theme.md, which is stale and still
// documents an emerald #10B981 accent. The real accent is orange #FF5000.
// Full citations in docs/DESIGN-SPEC.md.
//
// Peers is DARK ONLY. There is no light palette in the app and no
// useColorScheme anywhere, so there is nothing here to switch.
//
// ── surfaces ────────────────────────────────────────────────────────────
var canvas = "#0A0A0A"; // app ground, avatar ground
var pane = "#111111"; // panels
var panel = "#161616"; // raised cards, menus
var border = "#2a2a2a"; // 1px hairlines
// ── text ────────────────────────────────────────────────────────────────
var text = "#FAFAFA";
var textDim = "#6B7280";
var textFaint = "#4B5563"; // placeholders, always
// ── accent ──────────────────────────────────────────────────────────────
var accent = "#FF5000";
var accentHover = "#FF7A33";
var accentPressed = "#CC4000";
// White on accent, everywhere. The Android source comment is explicit that
// this is never black.
var onAccent = "#FFFFFF";
// ── message bubbles ─────────────────────────────────────────────────────
var bubblePeer = "#1F1F1F";
// ── state ───────────────────────────────────────────────────────────────
var unread = "#EF4444";
var pulse = "#F59E0B";
var verified = "#1D9BF0";
var errorFill = "#5c1a1a";
var errorBorder = "#C62828";
var link = "#4EA3FF";
// ── typography ──────────────────────────────────────────────────────────
// Peers is JetBrains Mono throughout. If the font is unavailable the
// fallback is the platform monospace family, never a proportional one —
// address strings and hex labels depend on fixed advance.
var fontFamily = "JetBrains Mono";
var brandSize = 16; // Bold
var titleSize = 16; // Medium
var bodySize = 14;
var labelSize = 12;
var captionSize = 10;
var codeSize = 13;
// ── spacing ─────────────────────────────────────────────────────────────
var space1 = 4;
var space2 = 8;
var space3 = 12;
var space4 = 16;
var space6 = 24;
// ── radii ───────────────────────────────────────────────────────────────
var radiusBubble = 8;
var radiusCard = 8;
var radiusPill = 999;
// ── layout ──────────────────────────────────────────────────────────────
var bubbleMaxWidthRatio = 0.78;
var conversationRowHeight = 64;
var headerHeight = 56;
var minTouchTarget = 44;
var hairline = 1;
// Identicon container radius, as a fraction of the side.
var avatarRadiusRatio = 0.22;

// Derived tokens (these referenced other tokens in the QML original).
var bubbleOwn      = accent;
var bubbleOwnText  = onAccent;
var bubblePeerText = text;
