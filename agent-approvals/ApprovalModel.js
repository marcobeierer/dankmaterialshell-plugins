function append(requests, request) {
    if (!request || !request.id || requests.some(item => item.id === request.id))
        return requests;
    return requests.concat([request]);
}

function remove(requests, id) {
    return requests.filter(item => item.id !== id);
}

function agentName(source) {
    return ({ opencode: "OpenCode", codex: "Codex", claude: "Claude Code" })[source] || source;
}

function details(request) {
    if (!request)
        return "";
    const data = request.details || {};
    const input = data.tool_input || data.input || data.metadata || {};
    const sections = [];
    // Show multiline commands, edits, and patches literally as well as keeping
    // the complete structured event available below them.
    for (const key of ["description", "command", "cmd", "file_path", "path", "old_string", "new_string", "content", "patch", "diff"]) {
        if (typeof input[key] === "string" && input[key])
            sections.push(key + ":\n" + input[key]);
    }
    if (data.resources?.length)
        sections.push("Requested resources:\n" + data.resources.join("\n"));
    sections.push("Full request (JSON):\n" + JSON.stringify(data, null, 2));
    return sections.join("\n\n");
}

function preview(request) {
    if (!request)
        return "";
    const data = request.details || {};
    const input = data.tool_input || data.input || data.metadata || {};
    const action = input.command || input.cmd || input.file_path || input.path
        || (data.resources || []).join("\n") || JSON.stringify(input, null, 2);
    return String(action);
}
