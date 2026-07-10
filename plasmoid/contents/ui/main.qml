import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    readonly property int tempMin: 2300
    readonly property int tempMax: 6500
    property int brightnessPct: 100
    property int temperatureK: 6300

    Plasmoid.icon: "weather-clear-night"

    P5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => disconnectSource(sourceName)
        function exec(cmd) {
            connectSource(cmd)
        }
    }

    function setBrightnessLive(pct) {
        executable.exec("$HOME/Projects/gloaming/brightness/set-brightness-live.sh " + pct)
    }

    function previewTemperature(k) {
        executable.exec("gdbus call --session --dest org.kde.KWin --object-path /org/kde/KWin/NightLight --method org.kde.KWin.NightLight.preview " + k)
    }

    function stopPreview() {
        executable.exec("gdbus call --session --dest org.kde.KWin --object-path /org/kde/KWin/NightLight --method org.kde.KWin.NightLight.stopPreview")
    }

    onExpandedChanged: {
        if (!expanded) {
            stopPreview()
        }
    }

    fullRepresentation: ColumnLayout {
        Layout.preferredWidth: Kirigami.Units.gridUnit * 16
        Layout.margins: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        QQC2.Label {
            text: i18n("Brightness")
        }
        RowLayout {
            Layout.fillWidth: true
            QQC2.Slider {
                id: brightnessSlider
                Layout.fillWidth: true
                from: 0
                to: 100
                value: root.brightnessPct
                onMoved: {
                    root.brightnessPct = Math.round(value)
                    root.setBrightnessLive(root.brightnessPct)
                }
            }
            QQC2.Label {
                text: Math.round(brightnessSlider.value) + "%"
                Layout.minimumWidth: Kirigami.Units.gridUnit * 2
            }
        }

        QQC2.Label {
            text: i18n("Color temperature")
        }
        RowLayout {
            Layout.fillWidth: true
            QQC2.Slider {
                id: temperatureSlider
                Layout.fillWidth: true
                from: root.tempMin
                to: root.tempMax
                value: root.temperatureK
                onMoved: {
                    root.temperatureK = Math.round(value)
                    root.previewTemperature(root.temperatureK)
                }
            }
            QQC2.Label {
                text: Math.round(temperatureSlider.value) + "K"
                Layout.minimumWidth: Kirigami.Units.gridUnit * 3
            }
        }

        QQC2.Label {
            text: i18n("Color temperature reverts to the schedule when you close this; brightness stays where you set it.")
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            opacity: 0.6
            font.pointSize: Kirigami.Theme.smallFont.pointSize
        }
    }
}
