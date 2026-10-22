import QtQuick
import Quickshell.Hyprland
import Quickshell.Io
import qs.Common
import qs.Modals.Common
import qs.Modules.Plugins
import qs.Services
import qs.Widgets
import "WindowModel.js" as WindowModel

PluginComponent {
    id: root

    readonly property bool supported: CompositorService.isHyprland || CompositorService.isNiri
    property string searchText: ""
    property string selectedKey: ""
    property string pendingKey: ""
    readonly property var windows: picker.shouldBeVisible ? snapshot() : []
    readonly property var rows: WindowModel.filteredRows(windows, searchText)
    readonly property int selectedIndex: rows.findIndex(row => row.key === selectedKey)

    onRowsChanged: {
        if (!rows.some(row => row.key === selectedKey))
            selectedKey = rows.length ? rows[0].key : "";
        Qt.callLater(ensureSelectionVisible);
    }

    function snapshot() {
        if (CompositorService.isHyprland)
            return WindowModel.hyprlandWindows(Hyprland.toplevels.values, Hyprland.monitors.values);
        if (CompositorService.isNiri)
            return WindowModel.niriWindows(NiriService.windows, NiriService.allWorkspaces);
        return [];
    }

    function show() {
        if (picker.shouldBeVisible)
            return;
        pendingKey = "";
        searchText = "";
        selectedKey = "";
        if (CompositorService.isHyprland) {
            Hyprland.refreshToplevels();
            Hyprland.refreshWorkspaces();
            Hyprland.refreshMonitors();
        }
        picker.open();
    }

    function pickerOpened() {
        if (!picker.shouldBeVisible)
            return;
        picker.contentLoader?.item?.resetSearch();
        selectedKey = rows.find(row => row.active)?.key || rows[0]?.key || "";
        ensureSelectionVisible();
    }

    function toggle() {
        if (picker.shouldBeVisible)
            hide();
        else
            show();
    }

    function hide(confirmedKey) {
        pendingKey = confirmedKey || "";
        picker.close();
    }

    function moveSelection(delta) {
        if (!rows.length)
            return;
        const index = (Math.max(0, selectedIndex) + delta + rows.length) % rows.length;
        selectedKey = rows[index].key;
        ensureSelectionVisible();
    }

    function ensureSelectionVisible() {
        picker.contentLoader?.item?.ensureSelectionVisible();
    }

    function confirmSelection() {
        if (selectedIndex < 0 || !picker.shouldBeVisible)
            return;
        hide(selectedKey);
    }

    function activatePendingWindow() {
        const key = pendingKey;
        pendingKey = "";
        if (!key)
            return;
        // Only confirmation changes desktop focus, after the modal releases its
        // keyboard grab. Resolve the stable identity again, never a stale row index.
        const window = snapshot().find(item => item.key === key);
        if (!window) {
            ToastService.showError("Window Picker", "That window is no longer open.");
            return;
        }
        if (CompositorService.isHyprland) {
            HyprlandService.focusWindow(window.windowId);
        } else if (CompositorService.isNiri) {
            CompositorService.closeNiriOverviewOnWindowFocus();
            if (!NiriService.focusWindow(window.windowId))
                ToastService.showError("Window Picker", "Could not focus the window. Check the Niri connection.");
        }
    }

    IpcHandler {
        target: "windowPicker"

        function toggle(): string {
            root.toggle();
            return "toggled";
        }

        function open(): string {
            root.show();
            return "opened";
        }

        function close(): string {
            root.hide();
            return "closed";
        }
    }

    DankModal {
        id: picker

        visible: false
        layerNamespace: "dms:window-picker"
        modalWidth: Math.min(680, Math.max(0, screenWidth - Theme.spacingL * 2))
        modalHeight: Math.min(600, Math.max(0, screenHeight - Theme.spacingL * 2))
        borderWidth: 1
        borderColor: Theme.outlineMedium
        keepContentLoaded: true

        onOpened: Qt.callLater(root.pickerOpened)
        onShouldBeVisibleChanged: {
            if (!shouldBeVisible)
                contentLoader?.item?.releaseSearchFocus();
        }
        onBackgroundClicked: root.hide()
        onDialogClosed: root.activatePendingWindow()

        content: Component {
            FocusScope {
                id: content

                anchors.fill: parent
                focus: true

                function focusSearch() {
                    if (picker.shouldBeVisible)
                        searchField.forceActiveFocus();
                }

                function resetSearch() {
                    searchField.text = "";
                    focusSearch();
                }

                function releaseSearchFocus() {
                    searchField.setFocus(false);
                }

                function ensureSelectionVisible() {
                    if (root.selectedIndex >= 0)
                        windowList.positionViewAtIndex(root.selectedIndex, ListView.Contain);
                }

                Keys.onPressed: event => {
                    switch (event.key) {
                    case Qt.Key_Down:
                    case Qt.Key_Tab:
                        root.moveSelection(event.modifiers & Qt.ShiftModifier ? -1 : 1);
                        break;
                    case Qt.Key_Up:
                    case Qt.Key_Backtab:
                        root.moveSelection(-1);
                        break;
                    case Qt.Key_Return:
                    case Qt.Key_Enter:
                        root.confirmSelection();
                        break;
                    case Qt.Key_Escape:
                        root.hide();
                        break;
                    default:
                        return;
                    }
                    event.accepted = true;
                }

                Column {
                    id: header
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: Theme.spacingM
                    spacing: Theme.spacingM

                    Item {
                        width: parent.width
                        height: 40

                        StyledText {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Window Picker"
                            font.pixelSize: Theme.fontSizeLarge
                            font.weight: Font.Medium
                            color: Theme.surfaceText
                        }

                        DankActionButton {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            iconName: "close"
                            tooltipText: "Close window picker"
                            Accessible.name: tooltipText
                            onClicked: root.hide()
                        }
                    }

                    DankTextField {
                        id: searchField
                        width: parent.width
                        leftIconName: "search"
                        placeholderText: "Search windows, apps, or workspaces…"
                        showClearButton: true
                        ignoreTabKeys: true
                        keyForwardTargets: [content]
                        Accessible.name: "Search open windows"
                        onTextChanged: {
                            root.searchText = text;
                            root.selectedKey = root.rows[0]?.key || "";
                            Qt.callLater(content.ensureSelectionVisible);
                        }
                    }
                }

                ListView {
                    id: windowList
                    anchors.top: header.bottom
                    anchors.bottom: footer.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: Theme.spacingM
                    clip: true
                    model: root.rows
                    currentIndex: root.selectedIndex
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: Item {
                        id: row
                        required property var modelData
                        required property int index
                        readonly property bool selected: root.selectedKey === modelData.key
                        readonly property int headingHeight: modelData.showHeading ? 36 : 0
                        width: windowList.width
                        height: headingHeight + 64 + Theme.spacingXS

                        StyledText {
                            visible: row.modelData.showHeading
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: row.headingHeight
                            verticalAlignment: Text.AlignVCenter
                            text: row.modelData.workspaceLabel
                                + (row.modelData.output ? " · " + row.modelData.output : "")
                                + " · " + row.modelData.groupCount
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Medium
                            color: Theme.primary
                            elide: Text.ElideRight
                            textFormat: Text.PlainText
                        }

                        Rectangle {
                            anchors.top: parent.top
                            anchors.topMargin: row.headingHeight
                            width: parent.width
                            height: 64
                            radius: Theme.cornerRadius
                            color: row.selected ? Theme.primarySelected
                                : (mouse.containsMouse ? Theme.withAlpha(Theme.surfaceText, 0.06) : "transparent")
                            border.width: row.selected ? 1 : 0
                            border.color: Theme.primary
                            Accessible.role: Accessible.ListItem
                            Accessible.name: row.modelData.title + ", " + row.modelData.appId + ", " + row.modelData.workspaceLabel
                            Accessible.selected: row.selected
                            Accessible.onPressAction: {
                                root.selectedKey = row.modelData.key;
                                root.confirmSelection();
                            }

                            DankIcon {
                                id: windowIcon
                                anchors.left: parent.left
                                anchors.leftMargin: Theme.spacingM
                                anchors.verticalCenter: parent.verticalCenter
                                name: row.modelData.active ? "my_location" : "window"
                                size: Theme.iconSize
                                color: row.selected ? Theme.primary : Theme.surfaceVariantText
                            }

                            Column {
                                anchors.left: windowIcon.right
                                anchors.right: parent.right
                                anchors.leftMargin: Theme.spacingM
                                anchors.rightMargin: Theme.spacingM
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Theme.spacingXS

                                StyledText {
                                    width: parent.width
                                    text: row.modelData.title
                                    textFormat: Text.PlainText
                                    color: Theme.surfaceText
                                    font.pixelSize: Theme.fontSizeMedium
                                    elide: Text.ElideRight
                                }

                                StyledText {
                                    width: parent.width
                                    text: (row.modelData.appId || "Unknown application") + (row.modelData.active ? " · Focused" : "")
                                    textFormat: Text.PlainText
                                    color: Theme.surfaceVariantText
                                    font.pixelSize: Theme.fontSizeSmall
                                    elide: Text.ElideRight
                                }
                            }

                            MouseArea {
                                id: mouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.selectedKey = row.modelData.key;
                                    root.confirmSelection();
                                }
                            }
                        }
                    }

                    StyledText {
                        anchors.centerIn: parent
                        width: parent.width - Theme.spacingL * 2
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: !root.supported ? "Window Picker supports Hyprland and Niri."
                            : (!root.windows.length ? "No open windows" : "No matching windows")
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeMedium
                        visible: !root.rows.length
                    }
                }

                StyledText {
                    id: footer
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: Theme.spacingM
                    text: root.rows.length + (root.rows.length === 1 ? " window" : " windows")
                        + " · ↑/↓ or Tab to select · Enter to focus · Esc to close"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    wrapMode: Text.WordWrap
                }
            }
        }
    }
}
