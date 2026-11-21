# Local permission bridge and focused-monitor notification

- Date: 2026-10-29
- Status: accepted

## Context

Users need enough context to answer three agents' permission requests without
returning to the terminal's workspace or display. Each agent owns its permission
policy and pending-request lifecycle.

## Decision

Use a DMS daemon plugin with a focused-monitor notification-style layer surface
and a Python standard-library Unix-socket bridge. Claude and Codex connect via
their synchronous PermissionRequest hooks. An OpenCode V2 companion subscribes
to native permission events and replies by session/request ID. Only DMS's stdin
pipe can resolve a bridge request. Offer allow-once, deny, and native-UI fallback.

## Rationale

Supported agent interfaces preserve exact request identity and agent policy.
An in-memory bridge supports concurrent sessions without terminal scraping,
keystroke injection, a network listener, or external services. A dedicated layer
surface provides full scrollable context and focused-monitor placement without
changing the user's global notification settings.

## Consequences

Decisions are local and single-request; disconnects and timeouts return control
to the agent. Request content is not written to notification history. The plugin
requires Python and per-agent setup. Its card is separate from DMS notification
history/DND, and Claude's sandbox network prompts are outside hook coverage.
Agent SDK/hook and DMS service contracts remain version-sensitive dependencies.
