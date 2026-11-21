import QtQuick
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Modules.Plugins
import "Status.js" as Status

PluginComponent {
    id: root

    layerNamespacePlugin: "herdr-status"

    property var widgetData: null

    readonly property string herdrAppBinary: String(pluginData.herdrAppBinary || "herdr-app").trim() || "herdr-app"
    readonly property string herdrBinary: String(pluginData.herdrBinary || "herdr").trim() || "herdr"
    readonly property string session: String(pluginData.session || "").trim()
    readonly property int pollSeconds: Math.max(1, Math.min(30, Number(pluginData.pollSeconds) || 2))
    readonly property bool showEveryStatus: widgetData?.showEveryStatus ?? false
    readonly property bool hideZeroCounts: widgetData?.hideZeroCounts ?? false
    readonly property bool hideIdle: widgetData?.hideIdle ?? false
    readonly property int widgetEntryIndex: {
        const entries = barConfig?.[section + "Widgets"] || [];
        // DankBar gives each entry a runtime ID formed from its saved ID and index.
        return entries.findIndex((entry, index) => {
            const id = typeof entry === "string" ? entry : (entry.id || entry.widgetId);
            return widgetData?.id === id + "_" + index;
        });
    }
    readonly property var sources: [appSource, cliSource]
    // Agents from every source that answered; null when none did.
    readonly property var snapshot: {
        const answered = sources.filter(source => source.agents !== null);
        return answered.length ? Status.summarize(answered.map(source => source.agents)) : null;
    }
    // Problems worth showing even while another source answers: unreadable output.
    readonly property string readErrors: sources.filter(source => source.unreadable)
        .map(source => source.error).join("\n")
    readonly property string errorText: {
        if (snapshot)
            return "";
        if (sources.some(source => !source.answered))
            return "Connecting to Herdr…";
        return readErrors || "Herdr is not running. Open the Herdr app or start a Herdr CLI session, or check the executable settings.";
    }
    readonly property string status: errorText ? "offline" : (snapshot ? snapshot.state : "offline")
    readonly property var agents: errorText || !snapshot ? [] : snapshot.agents
    readonly property var barStates: {
        if (errorText || !snapshot)
            return [status];
        if (!showEveryStatus)
            return hideIdle && status === "idle" ? [] : [status];
        const states = ["idle", "working", "blocked", "done"];
        if (snapshot.counts.unknown > 0)
            states.push("unknown");
        const visibleStates = states.filter(state => (!hideIdle || state !== "idle")
            && (!hideZeroCounts || snapshot.counts[state] > 0));
        return visibleStates.length || hideIdle ? visibleStates : [status];
    }
    readonly property string summary: {
        if (errorText)
            return errorText;
        if (!agents.length)
            return "No Herdr agents";
        const counts = snapshot.counts;
        return counts.blocked + " need attention · " + counts.done + " ready · "
            + counts.working + " working · " + counts.idle + " idle"
            + (counts.unknown ? " · " + counts.unknown + " unknown" : "");
    }

    function statusColor(state) {
        const customColor = pluginData.useCustomColors ? pluginData[state + "Color"] : null;
        if (typeof customColor === "string" && customColor)
            return customColor;
        switch (state) {
        case "blocked": return Theme.error;
        case "done": return Theme.info;
        case "working": return Theme.warning;
        case "idle": return Theme.success;
        default: return Theme.surfaceVariantText;
        }
    }

    function setDisplaySetting(settingKey, value) {
        if (!barConfig?.id || widgetEntryIndex < 0)
            return;
        const key = section + "Widgets";
        const config = SettingsData.getBarConfig(barConfig.id);
        const entries = (config?.[key] || []).slice();
        const index = widgetEntryIndex;
        const entry = entries[index];
        if (entry === undefined)
            return;
        const id = typeof entry === "string" ? entry : (entry.id || entry.widgetId);
        if (widgetData.id !== id + "_" + index)
            return;
        entries[index] = Object.assign({}, typeof entry === "string" ? { id: entry } : entry, {
            [settingKey]: value
        });
        SettingsData.updateBarConfig(barConfig.id, { [key]: entries });
    }

    function refresh() {
        appSource.refresh();
        cliSource.refresh();
    }

    Timer {
        interval: root.pollSeconds * 1000
        repeat: true
        running: true
        onTriggered: root.refresh()
    }

    HerdrSource {
        id: appSource
        name: "Herdr app"
        kind: "app"
        command: [root.herdrAppBinary, "ls"]
    }

    HerdrSource {
        id: cliSource
        name: "Herdr CLI"
        kind: "cli"
        command: root.session ? [root.herdrBinary, "--session", root.session, "agent", "list"]
            : [root.herdrBinary, "agent", "list"]
        // A desktop widget must not accidentally inherit a pane's socket override.
        environment: ({ HERDR_SOCKET_PATH: null, HERDR_SESSION: null })
    }

    // One bounded, non-overlapping read-only poll of one Herdr source.
    component HerdrSource: QtObject {
        id: source

        required property string name
        required property string kind
        required property var command
        property var environment: ({})

        // Agents from the last successful poll; null while unavailable, so a
        // failed request never leaves stale counts.
        property var agents: null
        property string error: ""
        property bool unreadable: false
        property bool answered: false
        property bool pending: false
        property bool timedOut: false
        property string requestKey: ""
        readonly property string key: JSON.stringify([command, environment])

        function fail(message, outputUnreadable) {
            agents = null;
            error = message;
            unreadable = outputUnreadable;
            answered = true;
        }

        function refresh() {
            if (pending || process.running)
                return;
            pending = true;
            requestKey = key;
            timedOut = false;
            process.command = command;
            process.environment = environment;
            watchdog.restart();
            process.running = true;
        }

        onKeyChanged: {
            agents = null;
            error = "";
            unreadable = false;
            answered = false;
            Qt.callLater(refresh);
        }

        Component.onCompleted: Qt.callLater(refresh)

        property Timer watchdog: Timer {
            interval: 5000
            onTriggered: {
                source.timedOut = true;
                source.pending = false;
                source.fail(source.name + " did not respond.", false);
                // Only terminate our read-only CLI child, never Herdr itself.
                source.process.signal(9);
            }
        }

        property Process process: Process {
            stdout: StdioCollector {
                onStreamFinished: {
                    // An empty reply is a failed request, reported on exit.
                    if (source.timedOut || source.requestKey !== source.key || !text.trim())
                        return;
                    try {
                        source.agents = source.kind === "app" ? Status.parseApp(text) : Status.parseCli(text);
                        source.error = "";
                        source.unreadable = false;
                        source.answered = true;
                    } catch (error) {
                        source.fail("Cannot read " + source.name + " status: " + error.message, true);
                    }
                }
            }
            stderr: StdioCollector {}
            onExited: (exitCode, exitStatus) => {
                source.watchdog.stop();
                source.pending = false;
                if (source.requestKey !== source.key) {
                    Qt.callLater(source.refresh);
                    return;
                }
                if (exitCode !== 0 && !source.timedOut)
                    source.fail(source.name + " is not running.", false);
            }
        }
    }

    pillRightClickAction: () => root.refresh()

    horizontalBarPill: Component {
        StatusPill {}
    }

    verticalBarPill: Component {
        StatusPill { vertical: true }
    }

    component StatusPill: Item {
        property bool vertical: false

        implicitWidth: Math.max(root.iconSize, statusGrid.implicitWidth)
        implicitHeight: Math.max(root.iconSize, statusGrid.implicitHeight)
        Accessible.name: "Herdr: " + Status.label(root.status) + ". " + root.summary

        Grid {
            id: statusGrid
            columns: vertical ? 1 : Math.max(1, root.barStates.length)
            spacing: Theme.spacingS

            Repeater {
                model: root.barStates

                delegate: Item {
                    required property string modelData
                    readonly property int count: root.snapshot && !root.errorText
                        ? (root.snapshot.counts[modelData] || 0) : 0

                    implicitWidth: root.iconSize + (countText.visible ? countText.implicitWidth + 2 : 0)
                    implicitHeight: root.iconSize
                    Accessible.name: Status.label(modelData) + ": " + count

                    DankIcon {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        name: "smart_toy"
                        size: root.iconSize
                        color: root.statusColor(modelData)
                    }

                    StyledText {
                        id: countText
                        anchors.top: parent.top
                        anchors.right: parent.right
                        visible: parent.count > 0 || (root.showEveryStatus && !root.errorText && root.snapshot !== null)
                        text: parent.count
                        font.pixelSize: Math.max(9, Math.round(root.iconSize * 0.45))
                        font.weight: Font.Medium
                        color: Theme.surfaceText
                    }
                }
            }
        }
    }

    popoutWidth: 430
    popoutHeight: 420
    popoutContent: Component {
        PopoutComponent {
            id: popout
            property bool showSettings: false

            headerText: showSettings ? "Widget settings" : "Herdr · " + Status.label(root.status)
            detailsText: showSettings ? "Applies only to this widget." : root.summary
            showCloseButton: true

            headerActions: Component {
                DankActionButton {
                    buttonSize: 32
                    iconName: popout.showSettings ? "arrow_back" : "settings"
                    iconSize: Theme.iconSize - 4
                    iconColor: Theme.surfaceText
                    Accessible.name: popout.showSettings ? "Back to agents" : "Widget settings"
                    onClicked: popout.showSettings = !popout.showSettings
                }
            }

            Flickable {
                width: parent.width
                visible: popout.showSettings
                height: visible ? Math.max(0, root.popoutHeight - popout.headerHeight
                    - popout.detailsHeight - Theme.spacingXL) : 0
                contentHeight: settingsContent.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: settingsContent
                    width: parent.width
                    spacing: Theme.spacingM

                Row {
                    width: parent.width
                    height: Math.max(displayModeLabel.implicitHeight, displayModeToggle.height)
                    spacing: Theme.spacingM

                    StyledText {
                        id: displayModeLabel
                        width: parent.width - displayModeToggle.width - Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Show every status"
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceText
                        wrapMode: Text.WordWrap
                    }

                    DankToggle {
                        id: displayModeToggle
                        anchors.verticalCenter: parent.verticalCenter
                        enabled: root.widgetEntryIndex >= 0
                        checked: root.showEveryStatus
                        Accessible.name: "Show every status"
                        onToggled: isChecked => root.setDisplaySetting("showEveryStatus", isChecked)
                    }
                }

                StyledText {
                    width: parent.width
                    text: "Show separate colored bot icons and counts for blocked, ready, working, and idle agents. Unknown agents appear separately when present. Changes are saved automatically."
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    wrapMode: Text.WordWrap
                }

                Row {
                    width: parent.width
                    height: Math.max(hideZeroCountsLabel.implicitHeight, hideZeroCountsToggle.height)
                    spacing: Theme.spacingM

                    StyledText {
                        id: hideZeroCountsLabel
                        width: parent.width - hideZeroCountsToggle.width - Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Hide zero-count statuses"
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceText
                        wrapMode: Text.WordWrap
                    }

                    DankToggle {
                        id: hideZeroCountsToggle
                        anchors.verticalCenter: parent.verticalCenter
                        enabled: root.widgetEntryIndex >= 0 && root.showEveryStatus
                        checked: root.hideZeroCounts
                        Accessible.name: "Hide zero-count statuses"
                        onToggled: isChecked => root.setDisplaySetting("hideZeroCounts", isChecked)
                    }
                }

                StyledText {
                    width: parent.width
                    text: "In every-status mode, hide icons with no agents."
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    wrapMode: Text.WordWrap
                }

                Row {
                    width: parent.width
                    height: Math.max(hideIdleLabel.implicitHeight, hideIdleToggle.height)
                    spacing: Theme.spacingM

                    StyledText {
                        id: hideIdleLabel
                        width: parent.width - hideIdleToggle.width - Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Always hide idle status"
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceText
                        wrapMode: Text.WordWrap
                    }

                    DankToggle {
                        id: hideIdleToggle
                        anchors.verticalCenter: parent.verticalCenter
                        enabled: root.widgetEntryIndex >= 0
                        checked: root.hideIdle
                        Accessible.name: "Always hide idle status"
                        onToggled: isChecked => root.setDisplaySetting("hideIdle", isChecked)
                    }
                }

                StyledText {
                    width: parent.width
                    text: "Hide the green icon in both display modes, even with idle agents. If no icons remain, click the blank widget area to access settings."
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    wrapMode: Text.WordWrap
                }
                }
            }

            Column {
                width: parent.width
                visible: !popout.showSettings
                height: visible ? implicitHeight : 0

                StyledText {
                    id: readErrorsLabel
                    width: parent.width
                    visible: root.snapshot !== null && root.readErrors.length > 0
                    height: visible ? implicitHeight : 0
                    leftPadding: Theme.spacingS
                    bottomPadding: Theme.spacingM
                    text: root.readErrors
                    color: Theme.error
                    font.pixelSize: Theme.fontSizeSmall
                    wrapMode: Text.WordWrap
                    textFormat: Text.PlainText
                }

                DankListView {
                    width: parent.width
                    implicitHeight: Math.max(0, root.popoutHeight - popout.headerHeight
                        - popout.detailsHeight - readErrorsLabel.height - Theme.spacingXL)
                    clip: true
                    spacing: Theme.spacingS
                    model: root.agents

                    delegate: Rectangle {
                        id: agentRow
                        required property var modelData
                        width: ListView.view.width
                        height: rowContent.implicitHeight + Theme.spacingM * 2
                        radius: Theme.cornerRadius
                        color: Theme.surfaceContainerHigh

                        Column {
                            id: rowContent
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: Theme.spacingM
                            spacing: Theme.spacingXS

                            StyledText {
                                width: parent.width
                                text: agentRow.modelData.name + " · " + Status.label(agentRow.modelData.state)
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.Medium
                                color: root.statusColor(agentRow.modelData.state)
                                elide: Text.ElideRight
                                textFormat: Text.PlainText
                            }

                            StyledText {
                                width: parent.width
                                visible: text.length > 0
                                text: agentRow.modelData.title
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceText
                                elide: Text.ElideRight
                                textFormat: Text.PlainText
                            }

                            StyledText {
                                width: parent.width
                                text: (agentRow.modelData.source === "app" ? "App" : "CLI") + " · "
                                    + agentRow.modelData.id + " · " + agentRow.modelData.detail
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                elide: Text.ElideMiddle
                                textFormat: Text.PlainText
                            }
                        }
                    }
                }
            }
        }
    }
}
