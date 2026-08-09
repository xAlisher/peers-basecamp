import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "Theme.js" as Theme

//
// Peers — Settings, the right-hand pane when the Settings section is selected.
//
// Self-contained: everything arrives through properties, everything leaves
// through `setSetting(key, jsonValue)` / `resetRequested()`. This file owns no
// backend reference and performs no persistence of its own.
//
// Shape follows SettingsScreen.tsx (docs/DESIGN-SPEC.md §5.12 "Settings row"):
// section heading in accent, then a bordered `panel` card whose rows are
// separated by a 1px hairline inset 16px from the left. Row = 16px padding,
// 52px minimum, label `title` / sub-line `caption`, control on the right.
//
// Deliberately absent: Tor, private mode, mesh, Bluetooth. Out of scope for the
// desktop port — a row that cannot do anything is worse than no row.
//
Rectangle {
    id: root

    // ── inputs ──────────────────────────────────────────────────────────────

    // Parsed from backend.settingsJson by the caller. Missing keys fall back to
    // the Android defaults below, so a fresh profile renders correctly.
    property var settings: ({})
    property string myAddress: ""
    // e.g. "logos.test". Read-only here; it is fixed at core startup.
    property string deliveryPreset: ""

    // ── outputs ─────────────────────────────────────────────────────────────

    // `jsonValue` is JSON-encoded: a boolean is the literal "true" / "false".
    signal setSetting(string key, string jsonValue)
    signal resetRequested

    color: Theme.canvas
    implicitWidth: 560
    implicitHeight: 720

    // Settings arrive as JSON, so a boolean may already be a bool (fresh from
    // JSON.parse) or a string (round-tripped through a KV store). Accept both
    // and never let an unknown shape silently read as "off".
    function boolAt(key, fallback) {
        if (!settings)
            return fallback;
        const v = settings[key];
        if (v === undefined || v === null || v === "")
            return fallback;
        if (typeof v === "boolean")
            return v;
        if (typeof v === "string")
            return v === "true" || v === "1";
        return !!v;
    }

    function flip(key, fallback) {
        root.setSetting(key, boolAt(key, fallback) ? "false" : "true");
    }

    // ── reusable pieces ─────────────────────────────────────────────────────

    // The pill switch. Accent when on, panel when off, thumb slides.
    // Hand-built rather than a design-system control: Peers' switch is a
    // specific shape and the host's control would import someone else's theme.
    component PillSwitch: Item {
        id: sw

        property bool checked: false
        signal toggled

        implicitWidth: 44
        implicitHeight: 26
        opacity: enabled ? 1.0 : 0.4

        Rectangle {
            id: track
            anchors.fill: parent
            radius: Theme.radiusPill
            color: sw.checked ? (swHover.hovered ? Theme.accentHover : Theme.accent) : Theme.panel
            border.width: Theme.hairline
            border.color: sw.checked ? (swHover.hovered ? Theme.accentHover : Theme.accent) : Theme.border

            HoverHandler {
                id: swHover
                enabled: sw.enabled
                cursorShape: Qt.PointingHandCursor
            }
            TapHandler {
                enabled: sw.enabled
                onTapped: sw.toggled()
            }

            Rectangle {
                width: 20
                height: 20
                radius: width / 2
                anchors.verticalCenter: parent.verticalCenter
                x: sw.checked ? track.width - width - 3 : 3
                color: sw.checked ? Theme.onAccent : Theme.textDim

                Behavior on x {
                    NumberAnimation {
                        duration: 120
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }
    }

    // A settings row carrying a switch.
    component ToggleRow: Item {
        id: tr

        property string label: ""
        property string sublabel: ""
        property bool checked: false
        signal toggled

        implicitHeight: Math.max(52, trBody.implicitHeight + Theme.space4 * 2)

        RowLayout {
            id: trBody
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Theme.space4
            anchors.rightMargin: Theme.space4
            spacing: Theme.space3

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    Layout.fillWidth: true
                    text: tr.label
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.titleSize
                    font.weight: Font.Medium
                    wrapMode: Text.Wrap
                }
                Text {
                    Layout.fillWidth: true
                    visible: tr.sublabel !== ""
                    text: tr.sublabel
                    color: Theme.textDim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.captionSize
                    wrapMode: Text.Wrap
                }
            }

            PillSwitch {
                Layout.alignment: Qt.AlignVCenter
                checked: tr.checked
                onToggled: tr.toggled()
            }
        }
    }

    // A settings row whose right-hand side is a read-only value, not a control.
    component ValueRow: Item {
        id: vr

        property string label: ""
        property string sublabel: ""
        property string value: ""

        implicitHeight: Math.max(52, vrBody.implicitHeight + Theme.space4 * 2)

        ColumnLayout {
            id: vrBody
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Theme.space4
            anchors.rightMargin: Theme.space4
            spacing: Theme.space1

            Text {
                Layout.fillWidth: true
                text: vr.label
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.titleSize
                font.weight: Font.Medium
            }
            // The value is machine text (a preset id), so it gets the code size
            // and stays selectable — people paste these into bug reports.
            TextEdit {
                Layout.fillWidth: true
                text: vr.value
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.codeSize
                readOnly: true
                selectByMouse: true
                selectionColor: Theme.accent
                selectedTextColor: Theme.onAccent
                wrapMode: TextEdit.WrapAnywhere
            }
            Text {
                Layout.fillWidth: true
                visible: vr.sublabel !== ""
                text: vr.sublabel
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.captionSize
                wrapMode: Text.Wrap
            }
        }
    }

    // A row for something that genuinely does not exist yet. It renders dimmed
    // with a "not available yet" pill instead of a control, because a switch
    // that flips and changes nothing is a lie about the product.
    component UnavailableRow: Item {
        id: ur

        property string label: ""
        property string sublabel: ""

        implicitHeight: Math.max(52, urBody.implicitHeight + Theme.space4 * 2)
        opacity: 0.55

        RowLayout {
            id: urBody
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Theme.space4
            anchors.rightMargin: Theme.space4
            spacing: Theme.space3

            PeersIcon {
                Layout.alignment: Qt.AlignTop
                Layout.topMargin: 2
                name: "lock"
                size: 18
                color: Theme.textFaint
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    Layout.fillWidth: true
                    text: ur.label
                    color: Theme.textDim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.titleSize
                    font.weight: Font.Medium
                    wrapMode: Text.Wrap
                }
                Text {
                    Layout.fillWidth: true
                    visible: ur.sublabel !== ""
                    text: ur.sublabel
                    color: Theme.textFaint
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.captionSize
                    wrapMode: Text.Wrap
                }
            }

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: notAvailable.implicitWidth + Theme.space3 * 2
                implicitHeight: notAvailable.implicitHeight + Theme.space1 * 2
                radius: Theme.radiusPill
                color: "transparent"
                border.width: Theme.hairline
                border.color: Theme.border

                Text {
                    id: notAvailable
                    anchors.centerIn: parent
                    text: "not available yet"
                    color: Theme.textFaint
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.captionSize
                }
            }
        }
    }

    component Separator: Rectangle {
        Layout.fillWidth: true
        Layout.leftMargin: Theme.space4
        Layout.preferredHeight: Theme.hairline
        color: Theme.border
    }

    component SectionHeading: Text {
        Layout.fillWidth: true
        Layout.topMargin: Theme.space2
        color: Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: Theme.labelSize
    }

    component Helper: Text {
        Layout.fillWidth: true
        color: Theme.textDim
        font.family: Theme.fontFamily
        font.pixelSize: Theme.labelSize
        lineHeight: 1.4
        wrapMode: Text.Wrap
    }

    // ── layout ──────────────────────────────────────────────────────────────

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Header, matching the thread pane's 56px header + hairline.
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.headerHeight

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.space4
                anchors.rightMargin: Theme.space4
                spacing: Theme.space3

                PeersIcon {
                    name: "settings"
                    size: 20
                    color: Theme.text
                }
                Text {
                    Layout.fillWidth: true
                    text: "Settings"
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.titleSize
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.hairline
            color: Theme.border
        }

        Flickable {
            id: scroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: width
            contentHeight: page.implicitHeight + Theme.space4 * 2
            boundsBehavior: Flickable.StopAtBounds

            ScrollBar.vertical: ScrollBar {}

            ColumnLayout {
                id: page
                x: Theme.space4
                y: Theme.space4
                // The card column is capped so rows stay readable when the pane
                // is wide; Settings is a form, not a canvas.
                width: Math.min(scroll.width - Theme.space4 * 2, 560)
                spacing: Theme.space3

                // ── identity ────────────────────────────────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    visible: root.myAddress !== ""
                    implicitHeight: identity.implicitHeight + Theme.space4 * 2
                    color: Theme.panel
                    radius: Theme.radiusCard
                    border.width: Theme.hairline
                    border.color: Theme.border

                    RowLayout {
                        id: identity
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: Theme.space4
                        anchors.rightMargin: Theme.space4
                        spacing: Theme.space3

                        HexAvatar {
                            seed: root.myAddress
                            kind: "contact"
                            size: 40
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Text {
                                Layout.fillWidth: true
                                text: "This device"
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.titleSize
                                font.weight: Font.Medium
                            }
                            TextEdit {
                                Layout.fillWidth: true
                                text: root.myAddress
                                color: Theme.textDim
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.codeSize
                                readOnly: true
                                selectByMouse: true
                                selectionColor: Theme.accent
                                selectedTextColor: Theme.onAccent
                                wrapMode: TextEdit.WrapAnywhere
                            }
                        }
                    }
                }

                // ── notifications ───────────────────────────────────────────
                SectionHeading {
                    text: "Notifications"
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: notifCard.implicitHeight
                    color: Theme.panel
                    radius: Theme.radiusCard
                    border.width: Theme.hairline
                    border.color: Theme.border
                    clip: true

                    ColumnLayout {
                        id: notifCard
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        spacing: 0

                        ToggleRow {
                            Layout.fillWidth: true
                            label: "Notifications"
                            sublabel: "Alerts for new messages while Peers is in the background."
                            checked: root.boolAt("notifLocal", true)
                            onToggled: root.flip("notifLocal", true)
                        }
                        Separator {}
                        ToggleRow {
                            Layout.fillWidth: true
                            label: "Message sound"
                            sublabel: "Play a sound on a new message."
                            checked: root.boolAt("notifSound", true)
                            onToggled: root.flip("notifSound", true)
                        }
                        Separator {}
                        ToggleRow {
                            Layout.fillWidth: true
                            label: "Vibration"
                            sublabel: "Vibrate on a new message, where the device supports it."
                            checked: root.boolAt("notifVibrate", true)
                            onToggled: root.flip("notifVibrate", true)
                        }
                        Separator {}
                        ToggleRow {
                            Layout.fillWidth: true
                            label: "Show message content"
                            sublabel: "Off keeps notifications generic (New message)."
                            checked: root.boolAt("notifShowContent", false)
                            onToggled: root.flip("notifShowContent", false)
                        }
                    }
                }

                // ── network ─────────────────────────────────────────────────
                SectionHeading {
                    text: "Network"
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: networkCard.implicitHeight
                    color: Theme.panel
                    radius: Theme.radiusCard
                    border.width: Theme.hairline
                    border.color: Theme.border
                    clip: true

                    ColumnLayout {
                        id: networkCard
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        spacing: 0

                        ValueRow {
                            Layout.fillWidth: true
                            label: "Delivery preset"
                            value: root.deliveryPreset !== "" ? root.deliveryPreset : "logos.test"
                            sublabel: "Read-only. The preset is chosen when the chat core starts, so a change takes effect on restart."
                        }
                    }
                }

                Helper {
                    text: "The preset picks which Logos delivery network this device talks to. Peers on different presets cannot reach each other."
                }

                // ── security ────────────────────────────────────────────────
                SectionHeading {
                    text: "Security"
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: securityCard.implicitHeight
                    color: Theme.panel
                    radius: Theme.radiusCard
                    border.width: Theme.hairline
                    border.color: Theme.border
                    clip: true

                    ColumnLayout {
                        id: securityCard
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        spacing: 0

                        UnavailableRow {
                            Layout.fillWidth: true
                            label: "App lock (PIN)"
                            sublabel: "Ask for a PIN before Peers opens."
                        }
                        Separator {}
                        UnavailableRow {
                            Layout.fillWidth: true
                            label: "Duress PIN"
                            sublabel: "A second PIN that wipes this identity and its data instead of unlocking."
                        }
                    }
                }

                Helper {
                    text: "Neither is implemented in the desktop build yet. On Android the PIN is a screen lock, not disk encryption — it keeps a passer-by out, not someone with the disk."
                }

                // ── danger ──────────────────────────────────────────────────
                SectionHeading {
                    text: "Danger"
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: dangerRow.implicitHeight + Theme.space4 * 2
                    // The danger card keeps the panel fill and swaps the border,
                    // per SettingsScreen.tsx:505-512.
                    color: resetHover.hovered ? Theme.errorFill : Theme.panel
                    radius: Theme.radiusCard
                    border.width: Theme.hairline
                    border.color: Theme.errorBorder

                    HoverHandler {
                        id: resetHover
                        cursorShape: Qt.PointingHandCursor
                    }
                    TapHandler {
                        onTapped: root.resetRequested()
                    }

                    RowLayout {
                        id: dangerRow
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: Theme.space4
                        anchors.rightMargin: Theme.space4
                        spacing: Theme.space3

                        PeersIcon {
                            Layout.alignment: Qt.AlignTop
                            Layout.topMargin: 2
                            name: "trash"
                            size: 18
                            color: Theme.unread
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Text {
                                Layout.fillWidth: true
                                text: "Reset identity and data"
                                color: Theme.unread
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.titleSize
                                font.weight: Font.Medium
                                wrapMode: Text.Wrap
                            }
                            Text {
                                Layout.fillWidth: true
                                text: "Deletes this identity, its keys and every message on this device, then starts over with a new address."
                                color: Theme.textDim
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.captionSize
                                wrapMode: Text.Wrap
                            }
                        }
                    }
                }

                Helper {
                    text: "There is no undo, and no copy anywhere else. Contacts keep messaging the old address into a void until you send them the new one."
                }
            }
        }
    }
}
