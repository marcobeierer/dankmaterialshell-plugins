// Herdr owns completion acknowledgement: use agent_status, not completion_seq
// (which remains set after viewing), focus, or locally inferred transitions.
function parse(text) {
    const response = JSON.parse(text);
    if (response.error)
        throw new Error(response.error.message || "Herdr returned an error");
    if (!response.result || response.result.type !== "agent_list"
            || !Array.isArray(response.result.agents))
        throw new Error("Unexpected response from herdr agent list");

    const counts = { blocked: 0, done: 0, working: 0, idle: 0, unknown: 0 };
    const agents = response.result.agents.map(function (agent) {
        if (!agent || typeof agent.pane_id !== "string"
                || typeof agent.agent_status !== "string")
            throw new Error("Invalid agent record from Herdr");
        const state = Object.prototype.hasOwnProperty.call(counts, agent.agent_status)
            ? agent.agent_status : "unknown";
        counts[state]++;
        return {
            paneId: agent.pane_id,
            state: state,
            name: agent.name || agent.display_agent || agent.agent || "Agent",
            title: agent.title || agent.terminal_title_stripped || agent.terminal_title || "",
            directory: agent.foreground_cwd || agent.cwd || ""
        };
    });

    // Attention outranks unread results, which outrank work in progress. Unknown
    // agents must never produce an all-idle indication; an empty herd is idle.
    const priority = ["blocked", "done", "working", "unknown", "idle"];
    const state = priority.filter(function (key) { return counts[key] > 0; })[0] || "idle";
    agents.sort(function (a, b) {
        return priority.indexOf(a.state) - priority.indexOf(b.state)
            || a.paneId.localeCompare(b.paneId);
    });
    return { state: state, counts: counts, agents: agents };
}

function label(state) {
    switch (state) {
    case "blocked": return "Needs attention";
    case "done": return "Results ready";
    case "working": return "Working";
    case "idle": return "Idle";
    case "unknown": return "Unknown status";
    default: return "Disconnected";
    }
}

function icon(state) {
    switch (state) {
    case "blocked": return "front_hand";
    case "done": return "task_alt";
    case "working": return "pending";
    case "idle": return "smart_toy";
    default: return "help_outline";
    }
}
