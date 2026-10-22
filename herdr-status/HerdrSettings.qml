import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    pluginId: "herdrStatus"

    StyledText {
        width: parent.width
        text: "Herdr Status"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StringSetting {
        settingKey: "herdrBinary"
        label: "Herdr executable"
        description: "Command name or absolute path, without arguments. Use an absolute path if DMS cannot find herdr."
        placeholder: "/home/you/.local/bin/herdr"
        defaultValue: "herdr"
    }

    StringSetting {
        settingKey: "session"
        label: "Named session"
        description: "Leave empty for Herdr's default session. Monitors all agents in the selected session."
        placeholder: "Default session"
        defaultValue: ""
    }

    SliderSetting {
        settingKey: "pollSeconds"
        label: "Refresh interval"
        defaultValue: 2
        minimum: 1
        maximum: 30
        unit: "s"
    }

    ToggleSetting {
        id: customColorsToggle
        settingKey: "useCustomColors"
        label: "Override status colors"
        description: "Use custom colors for all Herdr widgets and agent lists. Turn off to follow the DMS theme without losing your saved colors."
        defaultValue: false
    }

    ColorSetting {
        settingKey: "idleColor"
        label: "Idle color"
        defaultValue: Theme.success
        visible: customColorsToggle.value
    }

    ColorSetting {
        settingKey: "workingColor"
        label: "Working color"
        defaultValue: Theme.warning
        visible: customColorsToggle.value
    }

    ColorSetting {
        settingKey: "blockedColor"
        label: "Needs attention color"
        defaultValue: Theme.error
        visible: customColorsToggle.value
    }

    ColorSetting {
        settingKey: "doneColor"
        label: "Results ready color"
        defaultValue: Theme.info
        visible: customColorsToggle.value
    }

    ColorSetting {
        settingKey: "unknownColor"
        label: "Unknown status color"
        defaultValue: Theme.surfaceVariantText
        visible: customColorsToggle.value
    }

    ColorSetting {
        settingKey: "offlineColor"
        label: "Disconnected color"
        defaultValue: Theme.surfaceVariantText
        visible: customColorsToggle.value
    }

    StyledText {
        width: parent.width
        text: "Click the widget for agent details. Right-click to refresh. Viewing the popout does not mark results as read."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }
}
