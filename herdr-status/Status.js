// Herdr owns completion acknowledgement in both sources: `done` means finished
// and not yet viewed, and becomes `idle` once someone looks. Use the reported
// word as is, not completion counters, focus, or locally inferred transitions.
const states = ["blocked", "done", "working", "idle", "unknown"];

function stateOf(word) {
    return states.indexOf(word) >= 0 ? word : "unknown";
}

function rejectError(response) {
    if (response.error)
        throw new Error(typeof response.error === "string" ? response.error
            : response.error.message || "Herdr returned an error");
}

// `herdr-app ls`: the open Herdr app window's spaces, tabs, and terminals.
function parseApp(text) {
    const response = JSON.parse(text);
    rejectError(response);
    if (!Array.isArray(response.spaces))
        throw new Error("Unexpected response from herdr-app ls");

    const agents = [];
    response.spaces.forEach(function (space) {
        if (!space || !Array.isArray(space.tabs))
            throw new Error("Invalid space record from Herdr");
        space.tabs.forEach(function (tab) {
            if (!tab || !Array.isArray(tab.terminals))
                throw new Error("Invalid tab record from Herdr");
            tab.terminals.forEach(function (terminal) {
                if (!terminal || typeof terminal.terminal !== "string")
                    throw new Error("Invalid terminal record from Herdr");
                // Only programs that report a status are agents; shells are not.
                if (terminal.status === null || terminal.status === undefined)
                    return;
                agents.push({
                    source: "app",
                    // The app lists an agent's error with the agents that need you.
                    state: stateOf(terminal.status === "error" ? "blocked" : terminal.status),
                    id: terminal.terminal,
                    name: terminal.name || terminal.app || "Agent",
                    title: "",
                    detail: (space.name || "") + " / " + (tab.name || "")
                });
            });
        });
    });
    return agents;
}

// `herdr agent list`: one session of the Herdr CLI.
function parseCli(text) {
    const response = JSON.parse(text);
    rejectError(response);
    if (!response.result || response.result.type !== "agent_list"
            || !Array.isArray(response.result.agents))
        throw new Error("Unexpected response from herdr agent list");

    return response.result.agents.map(function (agent) {
        if (!agent || typeof agent.pane_id !== "string"
                || typeof agent.agent_status !== "string")
            throw new Error("Invalid agent record from Herdr");
        return {
            source: "cli",
            state: stateOf(agent.agent_status),
            id: agent.pane_id,
            name: agent.name || agent.display_agent || agent.agent || "Agent",
            title: agent.title || agent.terminal_title_stripped || agent.terminal_title || "",
            detail: agent.foreground_cwd || agent.cwd || ""
        };
    });
}

// Combines the agent lists of every source that answered.
function summarize(sources) {
    const counts = { blocked: 0, done: 0, working: 0, idle: 0, unknown: 0 };
    const agents = [];
    sources.forEach(function (sourceAgents) {
        sourceAgents.forEach(function (agent) {
            counts[agent.state]++;
            agents.push(Object.assign({ order: agents.length }, agent));
        });
    });

    // Attention outranks unread results, which outrank work in progress. Unknown
    // agents must never produce an all-idle indication; no agents is idle.
    const priority = ["blocked", "done", "working", "unknown", "idle"];
    const state = priority.filter(function (key) { return counts[key] > 0; })[0] || "idle";
    // Agents with the same state keep their sources' order.
    agents.sort(function (a, b) {
        return priority.indexOf(a.state) - priority.indexOf(b.state) || a.order - b.order;
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
