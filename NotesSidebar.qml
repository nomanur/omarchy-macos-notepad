import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "NoteStore.js" as Store

// NotesSidebar.qml — folder list + trash + search source.
//
// macOS Notes sidebar: Folders section list, each row shows an icon,
// name, and note count. Trash lives at the bottom. Selection is bound to
// the single `activeFolderId` / `showTrash` on the store object (owned by
// Panel.qml), so this component is purely presentational.

Item {
    id: root

    property var store: null
    property string searchText: ""
    property color foreground: Color.menu.text
    property color muted: Color.muted
    property string fontFamily: Style.font.menuFamily

    signal folderClicked(string folderId)
    signal trashClicked()
    signal newFolderRequested()

    implicitWidth: Style.space(180)

    readonly property var folderList: store ? store.folders : []

    function countFor(folderId) {
        if (!store) return 0;
        var n = 0;
        for (var i = 0; i < store.notes.length; i++) {
            var note = store.notes[i];
            if (folderId === "trash") {
                if (note.deletedAt != null) n++;
            } else if (note.deletedAt == null && note.folderId === folderId) {
                n++;
            }
        }
        return n;
    }

    function isActive(folderId) {
        if (!store) return false;
        if (folderId === "trash") return store.settings.showTrash;
        return !store.settings.showTrash && store.settings.activeFolderId === folderId;
    }

    Column {
        anchors.fill: parent
        spacing: Style.spacing.sm

        Text {
            text: "FOLDERS"
            textFormat: Text.PlainText
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.sm
        }

        ListView {
            id: folderView
            width: parent.width
            height: Math.min(folderList.length * (Style.space(30) + Style.spacing.xxs), folderList.length > 4 ? Style.space(160) : 9999)
            clip: true
            model: folderList
            delegate: BorderSurface {
                id: folderRow
                required property var modelData
                required property int index
                width: folderView.width
                height: Style.space(30)
                radius: Style.cornerRadius
                color: root.isActive(modelData.id) ? Style.selectedFill : "transparent"
                borderSpec: root.isActive(modelData.id) && Style.selectedBorderWidth > 0 ? Border.controlSpec("selected", root.foreground, Color.accent) : Border.none()
                property bool hovered: false

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: Style.spacing.sm
                    anchors.rightMargin: Style.spacing.sm
                    spacing: Style.spacing.sm

                    Text {
                        text: modelData.id === "trash" ? "Trash" : (modelData.id === "inbox" ? "Notes" : modelData.name)
                        textFormat: Text.PlainText
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        width: parent.width - Style.space(50)
                    }
                }
                Text {
                    text: String(root.countFor(modelData.id))
                    textFormat: Text.PlainText
                    color: root.muted
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    anchors.right: parent.right
                    anchors.rightMargin: Style.spacing.sm
                    anchors.verticalCenter: parent.verticalCenter
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: folderRow.hovered = true
                    onExited: folderRow.hovered = false
                    onClicked: {
                        if (modelData.id === "trash") root.trashClicked();
                        else root.folderClicked(modelData.id);
                    }
                }
            }
        }

        Item { width: 1; height: Style.spacing.xs }

        // Search drives the middle pane filter; the sidebar owns the field
        // so it stays reachable in quick mode (which hides the sidebar).
        TextField {
            id: searchField
            width: parent.width
            text: root.searchText
            placeholderText: "Search"
            foreground: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            onTextChanged: root.searchText = text
            Keys.onEscapePressed: { text = ""; root.searchText = ""; }
        }
    }
}
