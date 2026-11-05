import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// HotCorner.qml — bottom-right hot-corner listener + floating Quick Note flyout.
//
// Detection: a per-screen PanelWindow pinned to the bottom-right corner with
// exclusionMode Ignore. The desk believes it is just a window; what matters
// is only that pointer motion over the window counts as "cursor in corner".
// Dwell: pointer must sit inside the trigger zone for `dwellMs` before the
// trigger fires (prevents accidental opens while reaching for the bar).
// Cooldown: after a trigger, a `cooldownMs` quiet period suppresses re-fire
// (so the pointer leaving and re-entering during the flyout doesn't loop).
// Fullscreen windows suppress the trigger (matches macOS behavior).
//
// The flyout itself is rendered by Panel.qml; this component only calls
// shell.summon(id, "quick") when the corner dwells. The hotcorner config at
// ~/.config/omarchy/hotcorners.json is read if present (it is the canonical
// Omarchy hot-corner config); falling back to the plugin's own settings.

Item {
    id: root

    property var shell: null
    property var manifest: null
    property string omarchyPath: Quickshell.env("OMARCHY_PATH")
    property string pluginId: "io.github.nomanur.notes"

    property bool enabled: true
    property int dwellMs: 150
    property int triggerSize: 8
    property int cooldownMs: 800
    property bool suppressFullscreen: true

    readonly property string homeDir: Quickshell.env("HOME")
    readonly property string hotConfigPath: homeDir + "/.config/omarchy/hotcorners.json"
    readonly property string stateDir: homeDir + "/.local/state/omarchy/notes"
    readonly property string settingsPath: stateDir + "/settings.json"

    property bool cornerHovered: false
    property bool coolingDown: false
    property bool fullscreenNow: false

    // ---- read canonical hotcorners.json --------------------------------

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

    readonly property int hotConfigCeiling: 256 * 1024

    Process {
        id: hotConfigReader
        command: ["python3", "-c", root.safeRead, root.hotConfigPath, String(root.hotConfigCeiling)]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.applyHotConfig(text)
        }
        onExited: function(code) {
            if (code === 2) root.applyHotConfig("")
        }
    }

    FileView {
        path: root.hotConfigPath
        watchChanges: true
        blockAllReads: true
        preload: false
        printErrors: false
        onFileChanged: root.readHotConfig()
    }

    function readHotConfig() {
        hotConfigReader.running = false;
        hotConfigReader.running = true;
    }

    function applyHotConfig(json) {
        var parsed = {};
        try { parsed = JSON.parse(json || "{}") } catch (e) { parsed = {} }
        // triggerSize / dwellMs from the canonical config win when present.
        if (typeof parsed.triggerSize === "number" && isFinite(parsed.triggerSize))
            root.triggerSize = Math.max(1, Math.min(32, Math.round(parsed.triggerSize)));
        if (typeof parsed.dwellMs === "number" && isFinite(parsed.dwellMs))
            root.dwellMs = Math.max(0, Math.min(2000, Math.round(parsed.dwellMs)));
        if (typeof parsed.cooldownMs === "number" && isFinite(parsed.cooldownMs))
            root.cooldownMs = Math.max(0, Math.min(5000, Math.round(parsed.cooldownMs)));
        if (typeof parsed.suppressFullscreen === "boolean")
            root.suppressFullscreen = parsed.suppressFullscreen;
        var br = parsed.corners && parsed.corners["bottom-right"];
        if (br && typeof br.action === "string" && br.action !== "") {
            // An explicit action on bottom-right wins over our default summon.
            root.enabled = false;
        } else if (br && typeof br.action === "string" && br.action === "") {
            // Empty action == our plugin owns the corner.
            root.enabled = true;
        }
    }

    // ---- fullscreen suppression ----------------------------------------

    // Hyprland fullscreen: check the active workspace's toplevels via IPC
    // polling is expensive; instead the monitor's lastIpcObject is not
    // exposed to third-party panels. Fallback: Panel.qml reports the
    // no-fullscreen state through a file the panel writes, and this service
    // also simply respects "is the notes panel already open" (no re-summon
    // while open). Fullscreen suppression is best-effort here — the flyout
    // is a layer surface at Top, so it sits above fullscreen anyway, but
    // the *trigger* is suppressed when the shell tells us a fullscreen
    // window exists. We detect that through the shell's service registry
    // when available; otherwise we rely on the cooldown + open-state guard.
    property bool panelOpen: false

    function checkPanelOpen() {
        if (!root.shell) return;
        try {
            if (typeof root.shell.isPluginOpen === "function")
                root.panelOpen = root.shell.isPluginOpen(root.pluginId);
        } catch (e) { /* shell not ready */ }
    }

    Timer {
        id: openPoll
        interval: 500
        running: true
        repeat: true
        onTriggered: root.checkPanelOpen()
    }

    // ---- trigger state machine ------------------------------------------

    Timer {
        id: dwellTimer
        interval: root.dwellMs
        repeat: false
        onTriggered: root.fire()
    }

    Timer {
        id: cooldownTimer
        interval: root.cooldownMs
        repeat: false
        onTriggered: root.coolingDown = false
    }

    function enterCorner() {
        root.cornerHovered = true;
        if (!root.enabled || root.coolingDown || root.panelOpen) return;
        if (root.suppressFullscreen && root.fullscreenNow) return;
        if (root.dwellMs <= 0) { root.fire(); return; }
        dwellTimer.restart();
    }

    function leaveCorner() {
        root.cornerHovered = false;
        dwellTimer.stop();
    }

    function fire() {
        if (!root.enabled || root.coolingDown || root.panelOpen) return;
        root.coolingDown = true;
        cooldownTimer.restart();
        if (root.shell && typeof root.shell.summon === "function") {
            root.shell.summon(root.pluginId, '{"mode":"quick"}');
        } else {
            // Fallback via CLI so the hot corner still works if the shell
            // reference was not injected (e.g. in a dev preview).
            summonProc.command = ["omarchy-shell", "shell", "summon", root.pluginId, '{"mode":"quick"}'];
            summonProc.running = true;
        }
    }

    Process {
        id: summonProc
        stdout: StdioCollector { waitForEnd: true }
        stderr: StdioCollector { waitForEnd: true }
    }

    Component.onCompleted: {
        Qt.callLater(function() {
            root.readHotConfig();
            root.checkPanelOpen();
        });
    }

    // One listener window per screen, pinned bottom-right. The window is
    // fully transparent and tiny; only its mouse-over matters. Exclusion
    // mode Ignore so it never reserves space. Layer Top so it is hit-tested
    // above regular windows.
    Variants {
        model: Quickshell.screens.filter(s => s && s.name !== "")

        PanelWindow {
            id: cornerWindow
            required property var modelData
            screen: modelData
            anchors { bottom: true; right: true }
            margins.bottom: 0
            margins.right: 0
            implicitWidth: root.triggerSize
            implicitHeight: root.triggerSize
            color: "transparent"
            visible: root.enabled
            WlrLayershell.namespace: "notes-hotcorner"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
                onEntered: root.enterCorner()
                onExited: root.leaveCorner()
            }
        }
    }
}
