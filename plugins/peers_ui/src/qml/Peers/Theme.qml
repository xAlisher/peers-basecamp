pragma Singleton
import QtQuick

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
QtObject {
    // ── surfaces ────────────────────────────────────────────────────────────
    readonly property color canvas:      "#0A0A0A"   // app ground, avatar ground
    readonly property color pane:        "#111111"   // panels
    readonly property color panel:       "#161616"   // raised cards, menus
    readonly property color border:      "#2a2a2a"   // 1px hairlines

    // ── text ────────────────────────────────────────────────────────────────
    readonly property color text:        "#FAFAFA"
    readonly property color textDim:     "#6B7280"
    readonly property color textFaint:   "#4B5563"   // placeholders, always

    // ── accent ──────────────────────────────────────────────────────────────
    readonly property color accent:        "#FF5000"
    readonly property color accentHover:   "#FF7A33"
    readonly property color accentPressed: "#CC4000"
    // White on accent, everywhere. The Android source comment is explicit that
    // this is never black.
    readonly property color onAccent:      "#FFFFFF"

    // ── message bubbles ─────────────────────────────────────────────────────
    readonly property color bubbleOwn:      accent
    readonly property color bubbleOwnText:  onAccent
    readonly property color bubblePeer:     "#1F1F1F"
    readonly property color bubblePeerText: text

    // ── state ───────────────────────────────────────────────────────────────
    readonly property color unread:      "#EF4444"
    readonly property color pulse:       "#F59E0B"
    readonly property color verified:    "#1D9BF0"
    readonly property color errorFill:   "#5c1a1a"
    readonly property color errorBorder: "#C62828"
    readonly property color link:        "#4EA3FF"

    // ── typography ──────────────────────────────────────────────────────────
    // Peers is JetBrains Mono throughout. If the font is unavailable the
    // fallback is the platform monospace family, never a proportional one —
    // address strings and hex labels depend on fixed advance.
    readonly property string fontFamily: "JetBrains Mono"

    readonly property int brandSize:   16   // Bold
    readonly property int titleSize:   16   // Medium
    readonly property int bodySize:    14
    readonly property int labelSize:   12
    readonly property int captionSize: 10
    readonly property int codeSize:    13

    // ── spacing ─────────────────────────────────────────────────────────────
    readonly property int space1: 4
    readonly property int space2: 8
    readonly property int space3: 12
    readonly property int space4: 16
    readonly property int space6: 24

    // ── radii ───────────────────────────────────────────────────────────────
    readonly property int radiusBubble: 8
    readonly property int radiusCard:   8
    readonly property int radiusPill:   999

    // ── layout ──────────────────────────────────────────────────────────────
    readonly property real bubbleMaxWidthRatio: 0.78
    readonly property int conversationRowHeight: 64
    readonly property int headerHeight: 56
    readonly property int minTouchTarget: 44
    readonly property int hairline: 1

    // Identicon container radius, as a fraction of the side.
    readonly property real avatarRadiusRatio: 0.22
}
