import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Modules.Plugins
import qs.Services
import qs.Widgets
import "ApprovalModel.js" as ApprovalModel

PluginComponent {
    id: root

    property var requests: []
    readonly property var current: requests.length ? requests[0] : null
    readonly property string currentId: current?.id || ""
    property bool expanded: false
    property bool submitting: false
    property bool ready: false
    property bool stopping: false
    property bool armed: false
    readonly property var focusedScreen: CompositorService.getFocusedScreen()

    onCurrentIdChanged: {
        expanded = false;
        submitting = false;
        arm();
        fullDetails.contentY = 0;
    }
    onFocusedScreenChanged: arm()

    function arm() {
        armed = false;
        armDelay.restart();
    }

    function decide(id, decision) {
        if (!ready || !armed || submitting || !current || current.id !== id || SessionService.locked)
            return;
        submitting = true;
        bridge.write(JSON.stringify({ id: id, decision: decision }) + "\n");
    }

    function receive(line) {
        try {
            const message = JSON.parse(line);
            switch (message.type) {
            case "ready":
                ready = true;
                break;
            case "request":
                requests = ApprovalModel.append(requests, message.request);
                break;
            case "remove":
                requests = ApprovalModel.remove(requests, message.id);
                break;
            }
        } catch (error) {
            console.warn("Agent Approvals: invalid bridge message", error.message);
        }
    }

    Component.onDestruction: {
        stopping = true;
        bridge.running = false;
    }

    Timer {
        id: armDelay
        interval: 400
        onTriggered: root.armed = true
    }

    Timer {
        id: reconnect
        interval: 3000
        onTriggered: if (!root.stopping) bridge.running = true
    }

    Process {
        id: bridge
        command: ["python3", "-u", Paths.strip(Qt.resolvedUrl("bridge.py")), "serve"]
        stdinEnabled: true
        running: true
        stdout: SplitParser { onRead: data => root.receive(data) }
        stderr: SplitParser { onRead: data => console.warn("Agent Approvals:", data) }
        onExited: {
            root.ready = false;
            root.requests = [];
            if (!root.stopping)
                reconnect.restart();
        }
    }

    PanelWindow {
        id: notification
        screen: root.focusedScreen
        visible: root.ready && !!root.current && !!screen && !SessionService.locked
        color: "transparent"
        anchors.top: true
        anchors.right: true
        margins.top: 64
        margins.right: Theme.spacingM
        implicitWidth: Math.min(560, (screen?.width || 600) - Theme.spacingM * 2)
        implicitHeight: Math.min(cardColumn.implicitHeight + Theme.spacingM * 2, (screen?.height || 800) - 90)
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "dms:agent-approvals"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        Rectangle {
            anchors.fill: parent
            radius: Theme.cornerRadius
            color: Theme.surfaceContainer
            border.width: 1
            border.color: Theme.outlineMedium

            // The whole card scrolls on small displays; decision buttons never
            // disappear outside an unscrollable, clipped surface.
            Flickable {
                anchors.fill: parent
                anchors.margins: Theme.spacingM
                contentHeight: cardColumn.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar {}

                Column {
                    id: cardColumn
                    width: parent.width
                    spacing: Theme.spacingS

                    StyledText {
                        width: parent.width
                        text: ApprovalModel.agentName(root.current?.source || "") + " · Permission requested"
                        textFormat: Text.PlainText
                        font.pixelSize: Theme.fontSizeLarge
                        font.weight: Font.Medium
                        wrapMode: Text.WrapAnywhere
                        color: Theme.surfaceText
                    }

                    StyledText {
                        width: parent.width
                        text: (root.current?.title ? root.current.title + "\n" : "")
                            + (root.current?.cwd || "")
                        textFormat: Text.PlainText
                        wrapMode: Text.WrapAnywhere
                        color: Theme.surfaceText
                    }

                    StyledText {
                        width: parent.width
                        text: (root.current?.action || "") + " · Session " + (root.current?.session || "")
                        textFormat: Text.PlainText
                        wrapMode: Text.WrapAnywhere
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                    }

                    StyledText {
                        width: parent.width
                        visible: !!root.current?.reason
                        text: root.current?.reason || ""
                        textFormat: Text.PlainText
                        wrapMode: Text.WrapAnywhere
                        maximumLineCount: 3
                        elide: Text.ElideRight
                        color: Theme.surfaceText
                    }

                    StyledText {
                        width: parent.width
                        visible: !root.expanded
                        text: ApprovalModel.preview(root.current)
                        textFormat: Text.PlainText
                        wrapMode: Text.WrapAnywhere
                        maximumLineCount: 5
                        elide: Text.ElideRight
                        font.family: "monospace"
                        color: Theme.surfaceText
                    }

                    ActionButton {
                        width: parent.width
                        label: root.expanded ? "Hide full request" : "Preview above · Show full request"
                        onTriggered: root.expanded = !root.expanded
                    }

                    Flickable {
                        id: fullDetails
                        width: parent.width
                        height: visible ? Math.min(320, Math.max(100, (notification.screen?.height || 800) * 0.35)) : 0
                        visible: root.expanded
                        contentHeight: detailText.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar {}

                        TextEdit {
                            id: detailText
                            width: parent.width - 12
                            text: ApprovalModel.details(root.current)
                            textFormat: TextEdit.PlainText
                            readOnly: true
                            selectByMouse: true
                            wrapMode: TextEdit.WrapAnywhere
                            font.family: "monospace"
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceText
                        }
                    }

                    Row {
                        width: parent.width
                        spacing: Theme.spacingS

                        ActionButton {
                            width: (parent.width - Theme.spacingS * 2) / 3
                            label: "Use terminal"
                            decision: "defer"
                        }
                        ActionButton {
                            width: (parent.width - Theme.spacingS * 2) / 3
                            label: "Deny"
                            decision: "deny"
                        }
                        ActionButton {
                            width: (parent.width - Theme.spacingS * 2) / 3
                            label: "Allow once"
                            decision: "allow"
                            primary: true
                        }
                    }

                    StyledText {
                        width: parent.width
                        text: root.submitting ? "Sending decision…" : root.requests.length + " pending · Single request only"
                        textFormat: Text.PlainText
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                    }

                    ActionButton {
                        width: parent.width
                        visible: root.requests.length > 1
                        label: "Next request"
                        enabled: !root.submitting
                        onTriggered: root.requests = root.requests.slice(1).concat([root.current])
                    }
                }
            }
        }
    }

    component ActionButton: Button {
        id: button
        property string label: ""
        property string decision: ""
        property string pressedId: ""
        property bool primary: false
        signal triggered()
        implicitHeight: 38
        enabled: !decision || (root.armed && !root.submitting)
        Accessible.name: label
        onPressed: pressedId = root.current?.id || ""
        onClicked: {
            if (decision)
                root.decide(pressedId, decision);
            else
                triggered();
        }
        background: Rectangle {
            radius: Theme.cornerRadius
            color: button.primary ? Theme.primary : Theme.surfaceVariant
            opacity: button.enabled ? (button.down ? 0.7 : 1) : 0.45
            border.width: button.hovered ? 1 : 0
            border.color: Theme.outlineMedium
        }
        contentItem: StyledText {
            text: button.label
            textFormat: Text.PlainText
            color: button.primary ? Theme.primaryText : Theme.surfaceText
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            font.pixelSize: Theme.fontSizeSmall
        }
    }
}
