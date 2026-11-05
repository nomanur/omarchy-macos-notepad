import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "Markdown.js" as Md

// FormatBar.qml — macOS Notes formatting bar.
//
// Headings (Title/Heading/Subheading/Body), inline styles (Bold/Italic/
// Strikethrough/Underline), lists (Bullet/Numbered/Checklist), and quick
// insertions (Table/Horizontal rule/Timestamp).
//
// Follows the kit's Button component so states (hover/selected/focus) match
// every other Omarchy control exactly. Grouped with thin dividers.

Item {
    id: root

    // The editor this bar drives. Panel.qml wires it to the active TextArea.
    property var editor: null

    property color foreground: Color.menu.text
    property color muted: Color.muted
    property string fontFamily: Style.font.menuFamily

    implicitHeight: Style.space(36)

    // All actions route through the editor's applyFormat(action) so
    // undo/redo and autosave stay in one place.
    function act(action) {
        if (root.editor) root.editor.applyFormat(action);
    }

    component FormatButton: Button {
        // Compact pill: no border by default, highlighted when active.
        bordered: false
        foreground: root.foreground
        fontFamily: root.fontFamily
        fontSize: Style.font.bodySmall
        horizontalPadding: Style.spacing.sm
        verticalPadding: Style.spacing.xxs
    }

    component Divider: Item {
        width: 1
        height: Style.space(20)
        Rectangle {
            anchors.fill: parent
            color: root.muted
            opacity: 0.3
        }
    }

    Row {
        anchors.fill: parent
        spacing: Style.spacing.xs

        // ---- Headings ----------------------------------------------------
        FormatButton { text: "Title"; onClicked: root.act("title") }
        FormatButton { text: "Heading"; onClicked: root.act("heading") }
        FormatButton { text: "Subheading"; onClicked: root.act("subheading") }
        FormatButton { text: "Body"; onClicked: root.act("body") }

        Divider {}

        // ---- Inline styles ----------------------------------------------
        FormatButton { text: "B"; tooltipText: "Bold (Ctrl+B)"; onClicked: root.act("bold") }
        FormatButton { text: "I"; tooltipText: "Italic (Ctrl+I)"; onClicked: root.act("italic") }
        FormatButton { text: "S"; tooltipText: "Strikethrough"; onClicked: root.act("strike") }
        FormatButton { text: "U"; tooltipText: "Underline"; onClicked: root.act("underline") }

        Divider {}

        // ---- Lists --------------------------------------------------------
        FormatButton { text: "•"; tooltipText: "Bullet list"; onClicked: root.act("bullet") }
        FormatButton { text: "1."; tooltipText: "Numbered list"; onClicked: root.act("numbered") }
        FormatButton { text: "☑"; tooltipText: "Checklist"; onClicked: root.act("checklist") }

        Divider {}

        // ---- Insert -------------------------------------------------------
        FormatButton { text: "▦"; tooltipText: "Insert table"; onClicked: root.act("table") }
        FormatButton { text: "—"; tooltipText: "Horizontal rule"; onClicked: root.act("hr") }
        FormatButton { text: "🕐"; tooltipText: "Insert timestamp"; onClicked: root.act("timestamp") }
    }
}
