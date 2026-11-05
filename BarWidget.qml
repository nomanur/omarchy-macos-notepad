import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
    id: root
    moduleName: "io.github.nomanur.notes"

    // showIcon=false collapses the widget to nothing: the plugin stays
    // enabled and the keybind keeps working, the bar just shows no icon.
    // `omarchy bar set <id> showIcon false` without --json stores the *string*
    // "false", which is not the boolean, so a strict test left the icon
    // showing and the setting silently ignored.
    readonly property bool showIcon: {
        var v = setting("showIcon", true)
        return !(v === false || v === "false" || v === 0 || v === "0")
    }

    implicitWidth: showIcon ? button.implicitWidth : 0
    implicitHeight: showIcon ? button.implicitHeight : 0

    BarIconButton {
        id: button
        visible: root.showIcon
        anchors.fill: parent
        bar: root.bar
        text: "N"
        tooltipText: "Notes (Ctrl+N for a new note)"
        onPressed: function(b) {
            if (!root.bar) return
            root.bar.run("omarchy-shell shell toggle io.github.nomanur.notes")
        }
    }
}
