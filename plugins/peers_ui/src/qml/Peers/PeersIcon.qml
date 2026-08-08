import QtQuick
import QtQuick.Shapes

//
// Peers iconography — hand-ported Lucide glyphs drawn as VECTOR PATHS.
//
// Deliberately not `LogosIcon` and deliberately not a tinted raster: the design
// system tints its assets through a MultiEffect, which renders BLANK under the
// software backend. That is not hypothetical — upstream logos-chat-ui's own
// offscreen captures lose their New-chat button, copy buttons and send arrow to
// exactly this, and our first capture of it reproduced the bug. Drawing paths
// keeps the screenshot verification loop honest (ADR 0005).
//
// Path data is transcribed verbatim from the Android *Icon.tsx components; see
// docs/ICONS.md for the per-glyph citations. Lines and circles from the source
// are converted to equivalent `d` strings here so every primitive renders
// through one code path — the conversion is mechanical and the originals are
// noted beside each glyph.
//
// Never emoji-as-icon. Emoji appear only as content, e.g. a reaction a user
// picked.
//
Item {
    id: root

    // Glyph name. An unknown name draws nothing, rather than falling back to
    // something that would misdescribe the action.
    property string name: ""
    property color color: Theme.text
    property int size: 22
    // Android uses 1.8 for menu/nav glyphs; the send arrow uses 2.
    property real strokeWidth: 1.8
    // A few glyphs have a filled element (the `about` dot).
    property bool filled: false

    implicitWidth: size
    implicitHeight: size

    // Every glyph is authored on Lucide's 24x24 grid.
    readonly property real s: size / 24

    // Helpers that turn the source's <Line>/<Circle> primitives into `d` data.
    function line(x1, y1, x2, y2) {
        return "M" + x1 + " " + y1 + "L" + x2 + " " + y2;
    }
    function circle(cx, cy, r) {
        // Two half-arcs — the standard SVG circle-as-path form.
        return "M" + (cx - r) + " " + cy
             + "a" + r + "," + r + " 0 1,0 " + (2 * r) + ",0"
             + "a" + r + "," + r + " 0 1,0 " + (-2 * r) + ",0";
    }

    // name → { stroke: [d…], fill: [d…] }
    readonly property var glyphs: ({
        // ── SideMenu nav glyphs (docs/ICONS.md §4) ──────────────────────────
        "chats":    { stroke: ["M4 5h16v11H9l-4 3.5V16H4z"] },
        "groups":   { stroke: [circle(9, 9, 3),
                               "M3.5 19c0-3 2.5-5 5.5-5s5.5 2 5.5 5",
                               "M16 6.2a3 3 0 0 1 0 5.6",
                               "M17 14.2c2.4.5 3.5 2.2 3.5 4.8"] },
        "contacts": { stroke: [circle(12, 8, 3.5),
                               "M5 20c0-3.6 3.1-6 7-6s7 2.4 7 6"] },
        "settings": { stroke: [line(4, 8, 20, 8), circle(15, 8, 2.2),
                               line(4, 16, 20, 16), circle(9, 16, 2.2)] },
        "about":    { stroke: [circle(12, 12, 9), line(12, 11, 12, 16.5)],
                      fill:   [circle(12, 8.2, 0.9)] },
        "all":      { stroke: [line(4, 7, 20, 7), line(4, 12, 20, 12),
                               line(4, 17, 20, 17)] },

        // ── actions (docs/ICONS.md §1, §3) ──────────────────────────────────
        "send":     { stroke: ["M14.536 21.686a.5.5 0 0 0 .937-.024l6.5-19a.496.496 0 0 0-.635-.635l-19 6.5a.5.5 0 0 0-.024.937l7.93 3.18a2 2 0 0 1 1.112 1.11z",
                               "m21.854 2.147-10.94 10.939"] },
        "close":    { stroke: ["M6 6 18 18", "M18 6 6 18"] },
        "reply":    { stroke: ["M9 17l-5-5 5-5", "M4 12h11a5 5 0 0 1 5 5v2"] },
        "copy":     { stroke: ["M9 9h10v10H9z",
                               "M5 15H4a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1h10a1 1 0 0 1 1 1v1"] },
        "pin":      { stroke: ["M12 17v5",
                               "M9 10.76a2 2 0 0 1-1.11 1.79l-1.78.9A2 2 0 0 0 5 15.24V16a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-.76a2 2 0 0 0-1.11-1.79l-1.78-.9A2 2 0 0 1 15 10.76V7a1 1 0 0 1 1-1 2 2 0 0 0 0-4H8a2 2 0 0 0 0 4 1 1 0 0 1 1 1z"] },
        "trash":    { stroke: ["M3 6h18",
                               "M9 6V4.5A1.5 1.5 0 0 1 10.5 3h3A1.5 1.5 0 0 1 15 4.5V6",
                               "M6 6l1 13a2 2 0 0 0 2 1.8h6a2 2 0 0 0 2-1.8L18 6"] },
        "plus":     { stroke: [line(12, 5, 12, 19), line(5, 12, 19, 12)] },
        "search":   { stroke: [circle(11, 11, 7), "m20 20-3.5-3.5"] },
        "userplus": { stroke: [circle(9, 8, 3.5), "M3 20c0-3.3 2.7-6 6-6s6 2.7 6 6",
                               line(18, 9, 18, 15), line(15, 12, 21, 12)] },
        "back":     { stroke: ["M15 6l-6 6 6 6"] },
        "lock":     { stroke: ["M7 11V7a5 5 0 0 1 10 0v4", "M5 11h14v10H5z"] }
    })

    readonly property var glyph: glyphs[name] !== undefined
                                 ? glyphs[name] : ({ stroke: [], fill: [] })

    Shape {
        anchors.fill: parent
        antialiasing: true

        // Stroked primitives.
        Repeater {
            model: root.glyph.stroke !== undefined ? root.glyph.stroke : []
            delegate: ShapePath {
                required property string modelData
                strokeColor: root.color
                fillColor: "transparent"
                strokeWidth: root.strokeWidth * root.s
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                scale: Qt.size(root.s, root.s)
                PathSvg { path: modelData }
            }
        }

        // Filled primitives.
        Repeater {
            model: root.glyph.fill !== undefined ? root.glyph.fill : []
            delegate: ShapePath {
                required property string modelData
                strokeColor: "transparent"
                fillColor: root.color
                strokeWidth: 0
                scale: Qt.size(root.s, root.s)
                PathSvg { path: modelData }
            }
        }
    }
}
