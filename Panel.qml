import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "NoteStore.js" as Store

// Panel.qml — Notes. The main window.
//
// Two modes, one PanelWindow:
//   - "full":  three-pane Notes window (folders / list / editor), centered.
//   - "quick": floating flyout in the bottom-right, macOS Quick Note style.
//              A mini preview square expands (scale + slide) into the card;
//              Escape or clicking outside collapses it back.
//
// The Shell loads this as the `panel` entry point with the standard
// open()/close()/toggle() lifecycle. A Mode opens through
// summon(id, '{"mode":"quick"}') from Service.qml / HotCorner.qml, or
// '{"mode":"full"}' from the bar widget.
//
// State lives in ~/.local/state/omarchy/notes/notes.json, written debounced
// (300ms) and atomically (FileView atomicWrites). Reads go through the
// safeRead helper (refuse symlinks / non-regular / oversized) so a
// hand-edited or partially-synced file can never wedge the shell.

Item {
    id: root

    // ---- shell contract --------------------------------------------------
    property string omarchyPath: Quickshell.env("OMARCHY_PATH")
    property var shell: null
    property var manifest: null

    property bool opened: false
    property string mode: "full"          // "full" | "quick"
    property bool collapsed: false        // quick mode: mini square
    property bool stayOnTop: false

    readonly property string homeDir: Quickshell.env("HOME")
    readonly property string pluginDir: homeDir + "/.config/omarchy/plugins/io.github.nomanur.notes"
    readonly property string stateDir: homeDir + "/.local/state/omarchy/notes"
    readonly property string notesPath: stateDir + "/notes.json"

    // ---- store -----------------------------------------------------------

    property var store: Store.newStore()
    property bool storeLoaded: false
    property bool savingNow: false
    property string notesPending: ""

    // Undo/redo: per-session stacks of { noteId, body } snapshots.
    // TextArea has its own undo for the visible editor; this stack covers
    // format-bar operations and cross-note edits, and survives note switches.
    property var undoStack: []
    property var redoStack: []

    readonly property string safeRead: [
        'import os, stat, sys',
        'path = sys.argv[1]; ceiling = int(sys.argv[2])',
        'try:',
        '    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)',
        'except FileNotFoundError:',
        '    raise SystemExit(2)',
        'except OSError:',
        '    raise SystemExit(1)',
        'try:',
        '    if not stat.S_ISREG(os.fstat(fd).st_mode):',
        '        raise SystemExit(1)',
        '    with os.fdopen(fd, "rb") as handle:',
        '        fd = None',
        '        raw = handle.read(ceiling + 1)',
        'except OSError:',
        '    raise SystemExit(1)',
        'finally:',
        '    if fd is not None:',
        '        os.close(fd)',
        'if len(raw) > ceiling:',
        '    raise SystemExit(1)',
        'sys.stdout.buffer.write(raw)'
    ].join("\n")
    readonly property int notesCeiling: 4 * 1024 * 1024

    Process {
        id: notesReader
        command: ["python3", "-c", root.safeRead, root.notesPath, String(root.notesCeiling)]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.notesPending = text
        }
        onExited: function(code) {
            if (code === 0) {
                root.store = Store.deserialize(root.notesPending);
                root.storeLoaded = true;
                root.refreshActive();
            } else if (code === 2) {
                root.store = Store.newStore();
                root.storeLoaded = true;
                root.refreshActive();
            }
            // Other failures: keep in-memory state, retry next save cycle.
            root.notesPending = "";
        }
    }

    FileView {
        id: notesFile
        path: root.notesPath
        watchChanges: true
        atomicWrites: true
        blockAllReads: true
        preload: false
        printErrors: true
        onFileChanged: {
            if (root.savingNow) { root.savingNow = false; return; }
            root.readNotes();
        }
    }

    Timer {
        id: saveTimer
        interval: 300
        repeat: false
        onTriggered: {
            if (!root.storeLoaded) return;
            root.savingNow = true;
            notesFile.setText(Store.serialize(root.store));
        }
    }

    function scheduleSave() { if (root.storeLoaded) saveTimer.restart(); }

    function readNotes() { notesReader.running = false; notesReader.running = true; }

    Process {
        id: ensureDirsProc
        command: ["mkdir", "-p", root.stateDir]
    }

    Component.onCompleted: {
        ensureDirsProc.running = true;
        Qt.callLater(function() { root.readNotes(); });
    }

    // ---- derived state -----------------------------------------------------

    property string searchText: ""
    property string activeNoteId: ""
    property var filteredNotes: []

    function refreshActive() {
        if (!root.store) return;
        // Always adopt the store's persisted selection — including after
        // reloads and panel reopens — so the note saved as active is what
        // opens. The !root.activeNoteId guard broke this when the panel
        // item survived close/reopen (keepLoaded) with a stale selection.
        var fromStore = root.store.settings.activeNoteId;
        if (fromStore && Store.findNote(root.store, fromStore))
            root.activeNoteId = fromStore;
        root.recomputeFiltered();
    }

    function recomputeFiltered() {
        if (!root.store) { root.filteredNotes = []; return; }
        var folderId = root.store.settings.activeFolderId;
        root.filteredNotes = Store.filterNotes(root.store.notes, {
            folderId: folderId,
            query: root.searchText
        });
        // Keep the selection inside the filtered set when possible.
        var stillThere = false;
        for (var i = 0; i < root.filteredNotes.length; i++)
            if (root.filteredNotes[i].id === root.activeNoteId) { stillThere = true; break; }
        if (!stillThere) {
            root.activeNoteId = root.filteredNotes.length > 0 ? root.filteredNotes[0].id : "";
            root.store.settings.activeNoteId = root.activeNoteId || null;
        }
    }

    // Monotonic counter to force QML bindings that read the store to
    // re-evaluate after in-place JS-object mutations (QML does not track
    // plain-object fields on `property var store`).
    property int storeRev: 0

    property var activeNote: {
        if (!root.store || !root.activeNoteId) return null;
        void root.storeRev;
        return Store.findNote(root.store, root.activeNoteId);
    }

    // ---- note operations ----------------------------------------------------

    function createNote() {
        var folderId = root.store.settings.activeFolderId || "inbox";
        var note = Store.newNote(folderId);
        root.store.notes.push(note);
        root.store.settings.activeNoteId = note.id;
        root.activeNoteId = note.id;
        root.pushUndo(note.id, "");
        root.recomputeFiltered();
        root.scheduleSave();
        Qt.callLater(function() { editor.focusEditor(); });
    }

    function getOrCreateQuickNote() {
        var id = root.store.settings.quickNoteId;
        var note = id ? Store.findNote(root.store, id) : null;
        if (!note) {
            note = Store.newNote("inbox");
            note.title = "Quick Note";
            root.store.notes.push(note);
            root.store.settings.quickNoteId = note.id;
        }
        root.store.settings.activeNoteId = note.id;
        root.activeNoteId = note.id;
        root.recomputeFiltered();
        root.scheduleSave();
        return note;
    }

    function selectNote(id) {
        root.activeNoteId = id;
        root.store.settings.activeNoteId = id;
        root.scheduleSave();
    }

    function renameNote(id, title) {
        var n = Store.findNote(root.store, id);
        if (!n) return;
        Store.setTitle(n, title, n.body);
        root.recomputeFiltered();
        root.scheduleSave();
    }

    function editBody(id, body) {
        var n = Store.findNote(root.store, id);
        if (!n) return;
        if (n.body === body) return; // programmatic echo / no-op
        // Push undo snapshot before mutating, but debounce typing bursts:
        // only snapshot when the previous snapshot is older than 800ms.
        var now = Date.now();
        var last = root.undoStack.length > 0 ? root.undoStack[root.undoStack.length - 1] : null;
        if (!last || last.noteId !== id || (now - last.ts) > 800) {
            root.undoStack.push({ noteId: id, body: n.body, ts: now });
            if (root.undoStack.length > 200) root.undoStack.shift();
            root.redoStack = [];
        }
        Store.setBody(n, body);
        root.storeRev++;
        root.recomputeFiltered();
        root.scheduleSave();
    }

    function pushUndo(noteId, body) {
        root.undoStack.push({ noteId: noteId, body: body, ts: Date.now() });
        root.redoStack = [];
    }

    function undo() {
        var last = root.undoStack.pop();
        if (!last) return;
        var n = Store.findNote(root.store, last.noteId);
        if (!n) return;
        root.redoStack.push({ noteId: n.id, body: n.body, ts: Date.now() });
        n.body = last.body;
        Store.setBody(n, last.body);
        root.storeRev++;
        root.activeNoteId = n.id;
        root.recomputeFiltered();
        root.scheduleSave();
    }

    function redo() {
        var last = root.redoStack.pop();
        if (!last) return;
        var n = Store.findNote(root.store, last.noteId);
        if (!n) return;
        root.undoStack.push({ noteId: n.id, body: n.body, ts: Date.now() });
        n.body = last.body;
        Store.setBody(n, last.body);
        root.storeRev++;
        root.activeNoteId = n.id;
        root.recomputeFiltered();
        root.scheduleSave();
    }

    function togglePin(id) {
        var n = Store.findNote(root.store, id);
        if (!n) return;
        Store.togglePinned(n);
        root.recomputeFiltered();
        root.scheduleSave();
    }

    function deleteNote(id) {
        Store.deleteForever(root.store, id);
        if (root.activeNoteId === id) root.activeNoteId = "";
        root.recomputeFiltered();
        root.scheduleSave();
    }

    function duplicate(id) {
        var copy = Store.duplicateNote(root.store, id);
        if (!copy) return;
        root.activeNoteId = copy.id;
        root.store.settings.activeNoteId = copy.id;
        root.recomputeFiltered();
        root.scheduleSave();
    }

    function selectFolder(folderId) {
        root.store.settings.activeFolderId = folderId;
        root.recomputeFiltered();
        root.scheduleSave();
    }

    // ---- lifecycle (shell contract) -------------------------------------------

    function open(payloadJson) {
        var mode = "full";
        try {
            var p = JSON.parse(payloadJson || "{}");
            if (p.mode === "quick" || p.mode === "full") mode = p.mode;
        } catch (e) { }
        root.opened = true;
        root.mode = mode;
        root.store.settings.lastMode = mode;
        root.stayOnTop = false;
        if (mode === "quick") {
            root.getOrCreateQuickNote();
            root.collapsed = !!root.store.settings.collapsed;
        } else {
            root.refreshActive();
        }
        Qt.callLater(function() {
            if (mode === "quick" && !root.collapsed) quickEditor.focusEditor();
            else if (mode === "full") editor.focusEditor();
        });
        root.scheduleSave();
    }

    function focusActiveEditor() {
        if (root.isQuick) {
            if (!root.collapsed) quickEditor.focusEditor();
        } else {
            editor.focusEditor();
        }
    }

    onOpenedChanged: {
        if (root.opened) Qt.callLater(function() { root.focusActiveEditor(); });
    }

    function close() {
        // Shell-initiated close: just flip state; don't call back into shell.
        root.opened = false;
        root.collapsed = false;
        root.store.settings.collapsed = false;
    }

    function dismiss() {
        root.opened = false;
        root.collapsed = false;
        root.store.settings.collapsed = false;
        root.scheduleSave();
        if (root.shell && typeof root.shell.hide === "function")
            root.shell.hide((root.manifest && root.manifest.id) || "io.github.nomanur.notes");
    }

    function toggle() {
        if (root.opened) root.dismiss();
        else root.open("{}");
    }

    function collapseQuick() {
        root.collapsed = true;
        root.store.settings.collapsed = true;
    }

    function expandQuick() {
        root.collapsed = false;
        root.store.settings.collapsed = false;
        Qt.callLater(function() { quickEditor.focusEditor(); });
    }

    // ---- appearance ----------------------------------------------------------

    property color background: Color.menu.background
    property color foreground: Color.menu.text
    property color muted: Color.muted
    property color border: Color.menu.border
    property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
    readonly property int cornerRadius: Style.cornerRadius
    property string fontFamily: Style.font.menuFamily
    property int contentMargin: Style.spacing.panelPadding
    property int gap: Style.gapsOut

    // Full window: macOS Notes-ish 3-pane at a centered size.
    readonly property int fullWidth: Style.space(860)
    readonly property int fullHeight: Style.space(560)
    // Quick Note card: a generous but corner-sized flyout.
    readonly property int quickWidth: Style.space(380)
    readonly property int quickHeight: Style.space(300)
    // Collapsed mini square (macOS Quick Note's small preview).
    readonly property int miniSize: Style.space(64)

    readonly property bool isQuick: root.mode === "quick"

    // Entry animation: scale from the bottom-right origin. The card scales
    // 0.85 -> 1.0 and fades in; collapsing reverses it. Anchored by
    // transformOrigin on the card below.
    property real flyoutOpacity: root.opened ? 1 : 0
    property real flyoutScale: root.opened ? 1 : 0.85
    Behavior on flyoutOpacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    Behavior on flyoutScale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

    // ---- window -------------------------------------------------------------

    PanelWindow {
        id: panel
        visible: root.opened
        // Quick mode hugs the bottom-right; full mode centers.
        anchors {
            bottom: root.isQuick
            right: root.isQuick
            top: !root.isQuick
            left: !root.isQuick
        }
        margins.bottom: root.isQuick ? root.gap : 0
        margins.right: root.isQuick ? root.gap : 0
        implicitWidth: root.isQuick ? (root.collapsed ? root.miniSize : root.quickWidth) : root.fullWidth
        implicitHeight: root.isQuick ? (root.collapsed ? root.miniSize : root.quickHeight) : root.fullHeight
        color: "transparent"
        WlrLayershell.namespace: "notes"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        exclusionMode: ExclusionMode.Ignore

        HyprlandFocusGrab {
            active: root.opened && !root.stayOnTop
            windows: [panel]
            onCleared: root.dismiss()
        }

        BorderSurface {
            id: card
            anchors.fill: parent
            radius: root.cornerRadius
            color: root.background
            borderSpec: root.borderSpec
            padding: root.contentMargin
            opacity: root.flyoutOpacity
            scale: root.isQuick ? root.flyoutScale : 1
            transformOrigin: Item.BottomRight

            Item {
                id: cardContent
                anchors.fill: parent
                anchors.topMargin: card.contentTopInset
                anchors.rightMargin: card.contentRightInset
                anchors.bottomMargin: card.contentBottomInset
                anchors.leftMargin: card.contentLeftInset

                // Mini collapsed square (quick mode only).
                BorderSurface {
                    id: miniSquare
                    visible: root.isQuick && root.collapsed
                    anchors.fill: parent
                    radius: root.cornerRadius
                    color: root.background
                    borderSpec: root.borderSpec
                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.expandQuick()
                    }
                    Text {
                        anchors.centerIn: parent
                        text: "Notes"
                        textFormat: Text.PlainText
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                    }
                }

                // ---- full mode: three panes --------------------------------
                Row {
                    id: fullRow
                    visible: !root.isQuick
                    anchors.fill: parent
                    spacing: 0

                    NotesSidebar {
                        id: sidebar
                        height: parent.height
                        store: root.store
                        searchText: root.searchText
                        foreground: root.foreground
                        muted: root.muted
                        fontFamily: root.fontFamily
                        onFolderClicked: root.selectFolder(folderId)
                        onSearchTextChanged: { root.searchText = searchText; root.recomputeFiltered(); }
                    }
                    Item {
                        width: 1
                        height: parent.height
                        Rectangle { anchors.fill: parent; color: root.border }
                    }
                    NotesList {
                        id: noteList
                        height: parent.height
                        store: root.store
                        notes: root.filteredNotes
                        activeNoteId: root.activeNoteId
                        foreground: root.foreground
                        muted: root.muted
                        fontFamily: root.fontFamily
                        onNoteClicked: root.selectNote(noteId)
                        onNotePinned: root.togglePin(noteId)
                        onNoteDeleted: root.deleteNote(noteId)
                        onNoteDuplicated: root.duplicate(noteId)
                        onNewNoteRequested: root.createNote()
                    }
                    Item {
                        width: 1
                        height: parent.height
                        Rectangle { anchors.fill: parent; color: root.border }
                    }
                    Item {
                        width: parent.width - sidebar.width - noteList.width - 2
                        height: parent.height

                        Column {
                            anchors.fill: parent
                            spacing: Style.spacing.xs

                            // Toolbar row: New / Pin / Duplicate / Delete.
                            Row {
                                id: toolbar
                                width: parent.width
                                height: Style.space(32)
                                spacing: Style.spacing.sm

                                PanelActionButton {
                                    iconText: "+"
                                    tooltipText: "New note (Ctrl+N)"
                                    foreground: root.foreground
                                    onClicked: root.createNote()
                                }
                                PanelActionButton {
                                    iconText: root.activeNote && root.activeNote.pinned ? "■" : "□"
                                    tooltipText: "Pin note (Ctrl+Shift+P)"
                                    foreground: root.foreground
                                    onClicked: { if (root.activeNoteId) root.togglePin(root.activeNoteId); }
                                }
                                PanelActionButton {
                                    iconText: "⧉"
                                    tooltipText: "Duplicate note"
                                    foreground: root.foreground
                                    onClicked: { if (root.activeNoteId) root.duplicate(root.activeNoteId); }
                                }
                                PanelActionButton {
                                    iconText: "🗑"
                                    tooltipText: "Delete note permanently (Ctrl+Backspace)"
                                    foreground: root.foreground
                                    onClicked: { if (root.activeNoteId) root.deleteNote(root.activeNoteId); }
                                }
                                Item { width: Style.space(8); height: 1 }
                                Button {
                                    text: root.stayOnTop ? "Pinned" : "Pin"
                                    bordered: true
                                    selected: root.stayOnTop
                                    foreground: root.foreground
                                    fontFamily: root.fontFamily
                                    fontSize: Style.font.bodySmall
                                    onClicked: root.stayOnTop = !root.stayOnTop
                                }
                            }

                            NotesEditor {
                                id: editor
                                width: parent.width
                                height: parent.height - toolbar.height - Style.spacing.xs
                                note: root.activeNote
                                fontSize: root.store ? root.store.settings.fontSize : 14
                                foreground: root.foreground
                                muted: root.muted
                                background: root.background
                                fontFamily: root.fontFamily
                                onTextChanged: function(body) { root.editBody(root.activeNoteId, body); }
                                onTitleChanged: function(title) { root.renameNote(root.activeNoteId, title); }
                                onUndoPressed: root.undo()
                                onRedoPressed: root.redo()
                            }
                        }
                    }
                }

                // ---- quick mode: single editor + collapse ------------------
                Column {
                    id: quickColumn
                    visible: root.isQuick && !root.collapsed
                    anchors.fill: parent
                    spacing: Style.spacing.xs

                    Row {
                        width: parent.width
                        height: Style.space(28)
                        spacing: Style.spacing.sm

                        Text {
                            text: root.activeNote ? root.activeNote.title : "Quick Note"
                            textFormat: Text.PlainText
                            color: root.foreground
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.body
                            font.bold: true
                            elide: Text.ElideRight
                            width: parent.width - Style.space(120)
                            verticalAlignment: Text.AlignVCenter
                            height: parent.height
                        }
                        PanelActionButton {
                            iconText: "–"
                            tooltipText: "Collapse to mini note"
                            foreground: root.foreground
                            onClicked: root.collapseQuick()
                        }
                        PanelActionButton {
                            iconText: "⤢"
                            tooltipText: "Open in full Notes"
                            foreground: root.foreground
                            onClicked: root.open('{"mode":"full"}')
                        }
                        PanelActionButton {
                            iconText: "✕"
                            tooltipText: "Close (Esc)"
                            foreground: root.foreground
                            onClicked: root.dismiss()
                        }
                    }

                    NotesEditor {
                        id: quickEditor
                        width: parent.width
                        height: parent.height - Style.space(28) - Style.spacing.xs
                        note: root.activeNote
                        fontSize: root.store ? root.store.settings.fontSize : 14
                        foreground: root.foreground
                        muted: root.muted
                        background: root.background
                        fontFamily: root.fontFamily
                        onTextChanged: function(body) { root.editBody(root.activeNoteId, body); }
                        onTitleChanged: function(title) { root.renameNote(root.activeNoteId, title); }
                        onUndoPressed: root.undo()
                        onRedoPressed: root.redo()
                    }
                }
            }
        }

        // ---- keyboard shortcuts (work in both modes) ------------------------

        Item {
            id: shortcuts
            width: 1
            height: 1
            focus: true
            Keys.onPressed: function(event) {
                var ctrl = event.modifiers & Qt.ControlModifier;
                var shift = event.modifiers & Qt.ShiftModifier;
                if (event.key === Qt.Key_Escape) {
                    if (root.isQuick && root.collapsed) root.expandQuick();
                    else root.dismiss();
                    event.accepted = true;
                } else if (ctrl && event.key === Qt.Key_N) {
                    root.createNote();
                    event.accepted = true;
                } else if (ctrl && shift && event.key === Qt.Key_P) {
                    if (root.activeNoteId) root.togglePin(root.activeNoteId);
                    event.accepted = true;
                } else if (ctrl && event.key === Qt.Key_F) {
                    if (!root.isQuick) {
                        root.searchText = "";
                        searchFieldFocusHack();
                    }
                    event.accepted = true;
                } else if (ctrl && event.key === Qt.Key_Backspace) {
                    if (root.activeNoteId) root.deleteNote(root.activeNoteId);
                    event.accepted = true;
                }
            }
            function searchFieldFocusHack() {
                // Focus the sidebar search field via a binding-free lookup.
                try {
                    var f = sidebar;
                    if (f) f.forceActiveFocus();
                } catch (e) { }
            }
        }
    }
}
