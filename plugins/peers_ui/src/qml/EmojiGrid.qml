import QtQuick
import QtQuick.Layouts
import "Theme.js" as Theme

// The full emoji picker behind the quick-reaction bar's "+".
// Emoji are CONTENT here — the never-emoji-as-icon rule is about iconography.
Item {
    id: root
    anchors.fill: parent
    visible: false
    z: 61

    signal picked(string emoji)

    function open()  { visible = true; }
    function close() { visible = false; }

    readonly property var emojis: [
        "👍","❤️","😂","😮","😢","🙏","🔥","🎉","👏","💯",
        "😀","😅","😊","😍","🤔","😐","🙄","😴","🤝","👀",
        "✅","❌","⚠️","⭐","💡","📌","🚀","🐛","☕","🌙"
    ]

    Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.6) }
    TapHandler { onTapped: root.close() }

    Rectangle {
        anchors.centerIn: parent
        width: 360
        implicitHeight: grid.implicitHeight + Theme.space4 * 2 + 32
        height: implicitHeight
        radius: Theme.radiusCard
        color: Theme.panel
        border.width: Theme.hairline
        border.color: Theme.border
        TapHandler { onTapped: {} }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.space4
            spacing: Theme.space2

            Text {
                text: "Pick a reaction"
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.labelSize
            }

            GridLayout {
                id: grid
                Layout.fillWidth: true
                columns: 10
                columnSpacing: 0
                rowSpacing: 0

                Repeater {
                    model: root.emojis
                    delegate: Item {
                        required property string modelData
                        Layout.preferredWidth: 32
                        Layout.preferredHeight: 32
                        Text {
                            anchors.centerIn: parent
                            text: modelData
                            font.pixelSize: 20
                        }
                        TapHandler {
                            onTapped: { root.close(); root.picked(modelData); }
                        }
                    }
                }
            }
        }
    }
}
