.pragma library

function text(value) {
    return value === null || value === undefined ? "" : String(value);
}

function hyprlandWindows(toplevels, monitors) {
    return Array.from(toplevels).filter(window => {
        return window && window.address && window.lastIpcObject?.mapped !== false;
    }).map(window => {
        const ipc = window.lastIpcObject || {};
        const workspace = window.workspace || ipc.workspace || {};
        const name = text(workspace.name || workspace.id);
        const special = name === "special" || name.startsWith("special:");
        const monitor = monitors.find(item => item.id === ipc.monitor);
        return {
            key: "hyprland:" + window.address,
            windowId: window.address,
            title: text(window.title || ipc.title) || "Untitled window",
            appId: text(window.wayland?.appId || ipc.class),
            workspaceKey: "hyprland:" + text(workspace.id ?? name),
            workspaceLabel: special ? "Special: " + (name.slice(8) || "special")
                : (name ? "Workspace " + name : "Unknown workspace"),
            workspaceOrder: Number(workspace.id) > 0 ? Number(workspace.id) : Number.MAX_SAFE_INTEGER,
            output: text(window.monitor?.name || monitor?.name),
            active: !!window.wayland?.activated
        };
    });
}

function niriWindows(windows, workspaces) {
    return windows.map(window => {
        const workspace = workspaces.find(item => item.id === window.workspace_id);
        const name = workspace ? text(workspace.name || workspace.idx) : "";
        return {
            key: "niri:" + window.id,
            windowId: window.id,
            title: text(window.title) || "Untitled window",
            appId: text(window.app_id),
            workspaceKey: "niri:" + text(window.workspace_id),
            workspaceLabel: name ? "Workspace " + name : "No workspace",
            workspaceOrder: workspace?.idx ?? Number.MAX_SAFE_INTEGER,
            output: text(workspace?.output),
            active: !!window.is_focused
        };
    });
}

function filteredRows(windows, query) {
    const terms = text(query).trim().toLowerCase().split(/\s+/).filter(term => term.length > 0);
    const matches = windows.filter(window => {
        const searchable = [window.title, window.appId, window.workspaceLabel, window.output].join(" ").toLowerCase();
        return terms.every(term => searchable.includes(term));
    });

    matches.sort((a, b) => {
        return a.workspaceOrder - b.workspaceOrder
            || a.workspaceKey.localeCompare(b.workspaceKey)
            || a.output.localeCompare(b.output)
            || a.appId.localeCompare(b.appId)
            || a.title.localeCompare(b.title)
            || a.key.localeCompare(b.key);
    });

    const counts = {};
    for (const window of matches)
        counts[window.workspaceKey] = (counts[window.workspaceKey] || 0) + 1;

    return matches.map((window, index) => Object.assign({}, window, {
        showHeading: index === 0 || matches[index - 1].workspaceKey !== window.workspaceKey,
        groupCount: counts[window.workspaceKey]
    }));
}
