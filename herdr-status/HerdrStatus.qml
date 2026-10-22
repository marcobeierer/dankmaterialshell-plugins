import QtQuick
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Modules.Plugins
import "Status.js" as Status

PluginComponent {
    id: root

    layerNamespacePlugin: "herdr-status"

    readonly property string herdrBinary: String(pluginData.herdrBinary || "herdr").trim() || "herdr"
    readonly property string session: String(pluginData.session || "").trim()
    readonly property int pollSeconds: Math.max(1, Math.min(30, Number(pluginData.pollSeconds) || 2))
    readonly property bool showLabel: pluginData.showLabel ?? true
    readonly property string connectionKey: JSON.stringify([herdrBinary, session])

    property var snapshot: null
    property string errorText: "Connecting to Herdr…"
    property bool requestPending: false
    property string requestKey: ""
    property bool timedOut: false
    readonly property string status: errorText ? "offline" : (snapshot ? snapshot.state : "offline")
    readonly property var agents: errorText || !snapshot ? [] : snapshot.agents
    readonly property int statusCount: snapshot && !errorText ? (snapshot.counts[status] || 0) : 0
    readonly property string barText: (showLabel ? "Herdr" : "")
        + (statusCount > 0 ? (showLabel ? " · " : "") + statusCount : "")
    readonly property string summary: {
        if (errorText)
            return errorText;
        if (!agents.length)
            return "No agents in this session";
        const counts = snapshot.counts;
        return counts.blocked + " need attention · " + counts.done + " ready · "
            + counts.working + " working · " + counts.idle + " idle"
            + (counts.unknown ? " · " + counts.unknown + " unknown" : "");
    }

    function statusColor(state) {
        switch (state) {
        case "blocked": return "#ef5350";
        case "done": return "#42a5f5";
        case "working": return "#fdd835";
        case "idle": return "#66bb6a";
        default: return Theme.surfaceVariantText;
        }
    }

    function refresh() {
        if (requestPending || query.running)
            return;
        requestPending = true;
        requestKey = connectionKey;
        timedOut = false;
        const command = [herdrBinary];
        if (session)
            command.push("--session", session);
        command.push("agent", "list");
        query.command = command;
        watchdog.restart();
        query.running = true;
    }

    onConnectionKeyChanged: {
        snapshot = null;
        errorText = "Connecting to Herdr…";
        Qt.callLater(refresh);
    }

    Component.onCompleted: Qt.callLater(refresh)

    Timer {
        interval: root.pollSeconds * 1000
        repeat: true
        running: true
        onTriggered: root.refresh()
    }

    Timer {
        id: watchdog
        interval: 5000
        onTriggered: {
            root.timedOut = true;
            root.errorText = "Herdr did not respond. Check the executable and session settings.";
            root.requestPending = false;
            // Only terminate our read-only CLI child, never the Herdr server.
            query.signal(9);
        }
    }

    Process {
        id: query
        // A desktop widget must not accidentally inherit a pane's socket override.
        environment: ({ HERDR_SOCKET_PATH: null, HERDR_SESSION: null })
        stdout: StdioCollector {
            id: output
            onStreamFinished: {
                if (root.timedOut || root.requestKey !== root.connectionKey)
                    return;
                try {
                    root.snapshot = Status.parse(text);
                    root.errorText = "";
                } catch (error) {
                    root.errorText = "Cannot read Herdr status: " + error.message;
                }
            }
        }
        stderr: StdioCollector {}
        onExited: (exitCode, exitStatus) => {
            watchdog.stop();
            root.requestPending = false;
            if (root.requestKey !== root.connectionKey) {
                Qt.callLater(root.refresh);
                return;
            }
            if (exitCode !== 0 && !root.timedOut)
                root.errorText = "Herdr is unavailable. Start Herdr or check the executable and session settings.";
        }
    }

    pillRightClickAction: () => root.refresh()

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingS
            Accessible.name: "Herdr: " + Status.label(root.status) + ". " + root.summary

            DankIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: Status.icon(root.status)
                size: root.iconSize
                color: root.statusColor(root.status)
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                visible: text.length > 0
                text: root.barText
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceText
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXS
            Accessible.name: "Herdr: " + Status.label(root.status) + ". " + root.summary

            DankIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                name: Status.icon(root.status)
                size: root.iconSize
                color: root.statusColor(root.status)
            }

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: root.statusCount > 0
                text: root.statusCount
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceText
            }
        }
    }

    popoutWidth: 430
    popoutHeight: 420
    popoutContent: Component {
        PopoutComponent {
            id: popout
            headerText: "Herdr · " + Status.label(root.status)
            detailsText: root.summary
            showCloseButton: true

            StyledText {
                width: parent.width
                leftPadding: Theme.spacingS
                bottomPadding: Theme.spacingM
                text: root.session ? "Session: " + root.session : "Default session"
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall
                textFormat: Text.PlainText
            }

            ListView {
                width: parent.width
                implicitHeight: Math.max(0, root.popoutHeight - popout.headerHeight
                    - popout.detailsHeight - Theme.fontSizeSmall - Theme.spacingM * 3 - Theme.spacingXL)
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
                            text: agentRow.modelData.paneId + " · " + agentRow.modelData.directory
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
