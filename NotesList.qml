import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "NoteStore.js" as Store

// NotesList.qml — middle pane: note rows.
//
// Each row: title (bold, truncated), relative date, 1-2 line preview.
// Pinned notes sort to the top (Store.filterNotes already orders them).

Item {
    id: root

    property var store: null
    property var notes: []          // filtered + sorted, owned by Panel.qml
    property string activeNoteId: ""
    property color foreground: Color.menu.text
    property color muted: Color.muted
    property string fontFamily: Style.font.menuFamily

    signal noteClicked(string noteId)
    signal notePinned(string noteId)
    signal noteDeleted(string noteId)
    signal noteDuplicated(string noteId)
    signal newNoteRequested()

    // Right-click context menu state (single instance for the whole list,
    // following the dock's menuEntry/menuPoint pattern).
    property string contextNoteId: ""
    property point contextPoint: Qt.point(0, 0)
    property bool contextOpen: false
    property var contextNote: {
        if (!contextNoteId || !root.store) return null;
        for (var i = 0; i < root.store.notes.length; i++)
            if (root.store.notes[i].id === contextNoteId) return root.store.notes[i];
        return null;
    }

    implicitWidth: Style.space(260)

    // Empty state
    Column {
        visible: root.notes.length === 0
        anchors.centerIn: parent
        spacing: Style.spacing.sm
        width: parent.width - Style.space(32)

        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            textFormat: Text.PlainText
            text: "No notes"
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
        }
        Button {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "New note"
            bordered: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.newNoteRequested()
        }
    }

    ListView {
        id: list
        visible: root.notes.length > 0
        anchors.fill: parent
        clip: true
        model: root.notes
        spacing: Style.spacing.xxs

        delegate: BorderSurface {
            id: row
            required property var modelData
            required property int index
            width: list.width
            height: Style.space(64)
            radius: Style.cornerRadius
            readonly property bool selected: modelData.id === root.activeNoteId
            color: row.selected ? Style.selectedFill : (mouse.containsMouse ? Style.hoverFill : "transparent")
            borderSpec: row.selected && Style.selectedBorderWidth > 0 ? Border.controlSpec("selected", root.foreground, Color.accent) : Border.none()

            Column {
                anchors.fill: parent
                anchors.leftMargin: Style.spacing.sm
                anchors.rightMargin: Style.spacing.sm
                anchors.topMargin: Style.spacing.xs
                anchors.bottomMargin: Style.spacing.xxs
                spacing: 1

                Row {
                    width: parent.width
                    spacing: Style.spacing.xs
                    Text {
                        text: (modelData.pinned ? "📌 " : "") + modelData.title
                        textFormat: Text.PlainText
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        font.bold: true
                        elide: Text.ElideRight
                        width: parent.width - dateLabel.implicitWidth - Style.spacing.xs
                        maximumLineCount: 1
                    }
                    Text {
                        id: dateLabel
                        text: Store.relativeDate(modelData.modified)
                        textFormat: Text.PlainText
                        color: root.muted
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                    }
                }
                Text {
                    width: parent.width
                    text: {
                        var preview = Store.previewOf(modelData);
                        return preview === "" ? "No additional text" : preview;
                    }
                    textFormat: Text.PlainText
                    color: root.muted
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    elide: Text.ElideRight
                    maximumLineCount: 2
                    wrapMode: Text.Wrap
                }
            }

            MouseArea {
                id: mouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: function(m) {
                    if (m.button === Qt.RightButton) {
                        root.contextNoteId = modelData.id;
                        root.contextPoint = row.mapToItem(root, m.x, m.y);
                        root.contextOpen = true;
                    } else {
                        root.contextOpen = false;
                        root.noteClicked(modelData.id);
                    }
                }
            }
        }
    }

    // Context menu — contextNoteId/contextPoint pattern from the dock.
    // Buttons instead of a MenuRow component (not in the public qmldir).
    BorderSurface {
        id: contextMenu
        visible: root.contextOpen && root.contextNote
        width: Math.max(Style.space(160), menuColumn.implicitWidth) + padding * 2
        height: menuColumn.implicitHeight + padding * 2
        x: Math.min(root.contextPoint.x, Math.max(0, root.width - width))
        y: Math.min(root.contextPoint.y, Math.max(0, root.height - height))
        z: 10
        radius: Style.cornerRadius
        color: Color.popups.background
        borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Style.normalBorderWidth)
        padding: Style.spacing.sm

        Column {
            id: menuColumn
            x: contextMenu.contentLeftInset
            y: contextMenu.contentTopInset
            width: contextMenu.width - contextMenu.contentLeftInset - contextMenu.contentRightInset
            spacing: Style.spacing.xxs

            Button {
                width: parent.width
                text: root.contextNote && root.contextNote.pinned ? "Unpin" : "Pin"
                bordered: false
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: { root.notePinned(root.contextNoteId); root.contextOpen = false; }
            }
            Button {
                width: parent.width
                text: "Duplicate"
                bordered: false
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: { root.noteDuplicated(root.contextNoteId); root.contextOpen = false; }
            }
            Button {
                width: parent.width
                text: "Delete"
                bordered: false
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: { root.noteDeleted(root.contextNoteId); root.contextOpen = false; }
            }
        }

    }

    MouseArea {
        visible: root.contextOpen
        anchors.fill: parent
        z: 9
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: root.contextOpen = false
    }
}
