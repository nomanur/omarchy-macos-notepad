import QtQuick
import Quickshell
import Quickshell.Io

// Service.qml — always-on half of Notes.
//
// Owns the HotCorner listener (which needs to be mounted at startup to
// catch pointer motion at any time) and exposes the same open/close/toggle
// IPC lifecycle the shell expects of a panel plugin.
//
// The shell loads `service` and `panel` entry points as separate instances.
// The service instance hosts HotCorner.qml; the panel instance hosts
// Panel.qml. They coordinate through the on-disk store at
// ~/.local/state/omarchy/notes/notes.json and through shell.summon/hide.

Scope {
    id: root

    property string omarchyPath: ""
    property var shell: null
    property var manifest: null

    readonly property string pluginId: "io.github.nomanur.notes"
    readonly property bool opened: panelLoaded && panelItem ? panelItem.opened === true : false

    // ---- IPC (mirrors the panel's lifecycle names) ----------------------

    IpcHandler {
        target: "notes"
        function show(): void { root.show() }
        function hide(): void { root.hide() }
        function open(): void { root.show() }
        function close(): void { root.hide() }
        function toggle(): void { root.toggle() }
        function quick(): void { root.showQuick() }
    }

    function show() {
        if (shell && typeof shell.summon === "function")
            shell.summon(pluginId, '{"mode":"full"}');
    }

    function showQuick() {
        if (shell && typeof shell.summon === "function")
            shell.summon(pluginId, '{"mode":"quick"}');
    }

    function hide() {
        if (shell && typeof shell.hide === "function")
            shell.hide(pluginId);
    }

    function toggle() {
        if (shell && typeof shell.toggle === "function")
            shell.toggle(pluginId, '{"mode":"full"}');
    }

    // ---- hot corner ------------------------------------------------------

    // Loaded lazily on first show call? No: it must be alive at startup to
    // notice the cursor. Loader active from the start.
    Loader {
        id: hotCornerLoader
        active: true
        asynchronous: true
        source: Qt.resolvedUrl("HotCorner.qml")
        onLoaded: {
            if (!item) return;
            if ("shell" in item) item.shell = Qt.binding(function() { return root.shell; });
            if ("manifest" in item) item.manifest = Qt.binding(function() { return root.manifest; });
            if ("omarchyPath" in item) item.omarchyPath = Qt.binding(function() { return root.omarchyPath; });
        }
    }

    // Panel existence tracking (the shell owns the panel Loader; this flag
    // only answers `opened` for IPC consumers).
    property bool panelLoaded: false
    property var panelItem: null
}
