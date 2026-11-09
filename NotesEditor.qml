import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "NoteStore.js" as Store
import "Markdown.js" as Md

// NotesEditor.qml — detail pane: title field + formatting bar + Markdown editor.
//
// The editor is a TextArea in Markdown mode. Formatting routes
// through applyFormat() which mutates the TextArea text + restores the
// caret in one step; undo/redo are TextArea's built-in (and Panel.qml
// pushes a snapshot per format action into its own history so formatting
// survives reload — actually the per-note undo stack lives on the edited
// note via Panel.qml).

Item {
    id: root

    property var note: null            // live reference into store.notes
    property int fontSize: 14
    property color foreground: Color.menu.text
    property color muted: Color.muted
    property color background: Color.menu.background
    property string fontFamily: Style.font.menuFamily

    signal textChanged(string body)
    signal titleChanged(string title)
    signal formatApplied(string action)
    signal undoPressed()
    signal redoPressed()

    implicitWidth: Style.space(480)

    // ---- helpers --------------------------------------------------------

    function currentText() { return editor.text; }

    function formatWith(result) {
        var selStart = editor.selectionStart;
        var selEnd = editor.selectionEnd;
        editor.text = result.text;
        editor.select(result.start, result.end);
        editor.forceActiveFocus();
        root.formatApplied(result.text);
    }

    function applyFormat(action) {
        var text = editor.text;
        var start = editor.selectionStart;
        var end = editor.selectionEnd;
        var r;
        switch (action) {
        case "bold": r = Md.wrapSelection(text, start, end, "**", "**"); break;
        case "italic": r = Md.wrapSelection(text, start, end, "*", "*"); break;
        case "strike": r = Md.wrapSelection(text, start, end, "~~", "~~"); break;
        case "underline": r = Md.wrapSelection(text, start, end, "<u>", "</u>"); break;
        case "title": r = Md.toggleLinePrefix(text, start, end, "# "); break;
        case "heading": r = Md.toggleLinePrefix(text, start, end, "## "); break;
        case "subheading": r = Md.toggleLinePrefix(text, start, end, "### "); break;
        case "body": r = Md.toggleLinePrefix(text, start, end, ""); break;
        case "bullet": r = Md.toggleLinePrefix(text, start, end, "- "); break;
        case "numbered": r = Md.numberLines(text, start, end); break;
        case "checklist": r = Md.toggleChecklist(text, start, end); break;
        case "table": r = Md.insertAtCursor(text, start, end, Md.table(2, 2), true); break;
        case "hr": r = Md.insertAtCursor(text, start, end, "\n---\n\n", true); break;
        case "timestamp": r = Md.insertAtCursor(text, start, end, Md.timestampLine(), true); break;
        default: return;
        }
        formatWith(r);
    }

    function focusEditor() {
        editor.forceActiveFocus();
    }

    // Guard against programmatic text changes (note switch, undo/redo)
    // re-entering Panel.editBody via onTextChanged, which would push bogus
    // undo snapshots and re-sort/reset the selection mid-switch. Set in the
    // same turn the text is assigned; onTextChanged fires synchronously.
    property bool blockSignals: false

    onNoteChanged: {
        if (!note) {
            blockSignals = true;
            editor.text = "";
            blockSignals = false;
            return;
        }
        // Switch note text without triggering onTextChanged (which would
        // push a bogus undo snapshot and overwrite the note).
        blockSignals = true;
        editor.text = note.body || "";
        blockSignals = false;
    }

    Component.onCompleted: {
        if (note) {
            blockSignals = true;
            editor.text = note.body || "";
            blockSignals = false;
        }
    }

    // ---- layout ----------------------------------------------------------

    Column {
        anchors.fill: parent
        spacing: 0

        // Title — macOS Notes shows the first line as a large bold title.
        TextField {
            id: titleField
            width: parent.width
            text: root.note ? root.note.title : ""
            onTextChanged: if (activeFocus) root.titleChanged(text)
            foreground: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.display
            placeholderText: "New note"
            Keys.onReturnPressed: editor.forceActiveFocus()
        }

        FormatBar {
            id: formatBar
            width: parent.width
            editor: root
        }

        Item {
            width: parent.width
            height: parent.height - titleField.height - formatBar.height

            ScrollView {
                id: editorScroll
                anchors.fill: parent
                clip: true
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                TextArea {
                    id: editor
                    width: parent.width
                    height: Math.max(parent.height, implicitHeight)
                    wrapMode: TextArea.Wrap
                    rightPadding: editorScroll.ScrollBar.vertical.width + Style.spacing.xs
                    font.family: root.fontFamily
                    font.pixelSize: root.fontSize
                    color: root.foreground
                    selectionColor: Style.selectionFillFor(root.foreground, Color.accent)
                    selectedTextColor: root.foreground
                    placeholderText: "Type here..."
                    placeholderTextColor: Qt.darker(root.foreground, 1.6)
                    background: Item {}
                    onTextChanged: if (!root.blockSignals) root.textChanged(text)

                    Keys.onPressed: function(event) {
                        var ctrl = event.modifiers & Qt.ControlModifier;
                        if (ctrl && event.key === Qt.Key_B) { root.applyFormat("bold"); event.accepted = true; }
                        else if (ctrl && event.key === Qt.Key_I) { root.applyFormat("italic"); event.accepted = true; }
                        else if (ctrl && event.key === Qt.Key_Z && !(event.modifiers & Qt.ShiftModifier)) { root.undoPressed(); event.accepted = true; }
                        else if (ctrl && (event.key === Qt.Key_Y || (event.key === Qt.Key_Z && (event.modifiers & Qt.ShiftModifier)))) { root.redoPressed(); event.accepted = true; }
                        else if (ctrl && event.key === Qt.Key_L) { /* reserved */ }
                    }
                }
            }
        }
    }
}
