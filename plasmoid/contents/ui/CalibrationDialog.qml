import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasma5support as P5Support
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

Kirigami.ApplicationWindow {
    id: dialog
    title: i18n("Duskwatch - Display Calibration")
    width: Kirigami.Units.gridUnit * 26
    height: Kirigami.Units.gridUnit * 20

    readonly property string listScript: "$HOME/Projects/duskwatch/brightness/list-displays.sh"
    readonly property string previewScript: "$HOME/Projects/duskwatch/brightness/preview-raw.sh"
    readonly property string configScript: "$HOME/Projects/duskwatch/brightness/set-config.sh"
    readonly property string swdimScript: "$HOME/Projects/duskwatch/brightness/set-software-dimming.sh"

    property var displays: []

    P5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            if (sourceName === dialog.listScript) {
                dialog.parseDisplays(data["stdout"] || "")
            }
            disconnectSource(sourceName)
        }
        function exec(cmd) {
            connectSource(cmd)
        }
    }

    function reload() {
        executable.exec(listScript)
    }

    function parseDisplays(text) {
        var rows = []
        text.split("\n").forEach(line => {
            if (!line.trim()) return
            var parts = line.split("|")
            if (parts.length !== 7) return
            rows.push({
                id: parts[0], label: parts[1],
                floor: parseInt(parts[2]), ceil: parseInt(parts[3]),
                // Calibration is written under the stable label-derived key
                // so it stays with the physical monitor even if the displayN
                // list reindexes.
                calKey: parts[4] || parts[0],
                connector: parts[5], swdim: parts[6],
                controllable: parts[0] !== "-"
            })
        })
        displays = rows
    }

    function preview(displayId, pct) {
        executable.exec(previewScript + " " + displayId + " " + pct)
    }

    function setFloor(display, value) {
        executable.exec(configScript + " FLOOR_" + display.calKey + " " + value)
    }

    function setCeil(display, value) {
        executable.exec(configScript + " CEIL_" + display.calKey + " " + value)
    }

    function setSoftwareDimming(display, enabled) {
        var target = display.controllable ? display.id : display.connector
        executable.exec(swdimScript + " " + target + " " + (enabled ? "on" : "off"))
    }

    Component.onCompleted: reload()

    pageStack.initialPage: Kirigami.ScrollablePage {
        title: i18n("Display Calibration")

        ColumnLayout {
            width: parent.width
            spacing: Kirigami.Units.largeSpacing

            PlasmaComponents3.Label {
                text: i18n("Monitors vary a lot in perceived brightness at the same raw percentage. Drag Floor/Ceiling for a display to preview it live on that monitor, then leave it where it visually matches the others.")
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                opacity: 0.7
            }

            Repeater {
                model: dialog.displays
                delegate: ColumnLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.topMargin: Kirigami.Units.largeSpacing

                    PlasmaComponents3.Label {
                        text: modelData.label
                        font.bold: true
                    }
                    PlasmaComponents3.Label {
                        visible: !modelData.controllable
                        text: i18n("No brightness control - this display's DDC/CI isn't working. Software dimming makes it controllable (and lets it go darker than hardware would, though it saves no power).")
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                        opacity: 0.7
                    }
                    RowLayout {
                        visible: modelData.controllable
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        PlasmaComponents3.Label { text: i18n("Floor") }
                        PlasmaComponents3.Slider {
                            Layout.fillWidth: true
                            from: 0; to: 100
                            value: modelData.floor
                            onMoved: dialog.preview(modelData.id, Math.round(value))
                            onPressedChanged: if (!pressed) dialog.setFloor(modelData, Math.round(value))
                        }
                        PlasmaComponents3.Label {
                            text: modelData.floor + "%"
                            Layout.minimumWidth: Kirigami.Units.gridUnit * 2
                        }
                    }
                    RowLayout {
                        visible: modelData.controllable
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        PlasmaComponents3.Label { text: i18n("Ceiling") }
                        PlasmaComponents3.Slider {
                            Layout.fillWidth: true
                            from: 0; to: 100
                            value: modelData.ceil
                            onMoved: dialog.preview(modelData.id, Math.round(value))
                            onPressedChanged: if (!pressed) dialog.setCeil(modelData, Math.round(value))
                        }
                        PlasmaComponents3.Label {
                            text: modelData.ceil + "%"
                            Layout.minimumWidth: Kirigami.Units.gridUnit * 2
                        }
                    }
                    PlasmaComponents3.CheckBox {
                        visible: modelData.swdim !== "na" && modelData.connector !== ""
                        checked: modelData.swdim === "on"
                        text: i18n("Software dimming (disable DDC/CI hardware control)")
                        onToggled: dialog.setSoftwareDimming(modelData, checked)

                        PlasmaComponents3.ToolTip {
                            text: i18n("Dims by scaling colors in the compositor instead of the monitor's backlight: works when DDC/CI doesn't, and can go darker than the hardware range, but saves no power. Takes a moment to apply; reopen this window to see the new state.")
                        }
                    }
                    Kirigami.Separator {
                        Layout.fillWidth: true
                        Layout.topMargin: Kirigami.Units.smallSpacing
                    }
                }
            }
        }
    }
}
