# Native QML widget using Herdr's CLI

- Date: 2026-10-22
- Status: accepted

## Context

The integration targets DMS 1.6.2 and Herdr 0.9.3. Herdr exposes agent state
through a read-only CLI with a structured JSON response.

## Decision

Use a QML bar widget with a bounded, non-overlapping `herdr agent list` poll.
Let Herdr own agent detection and acknowledgement. Do not install an agent
plugin, read databases, or implement a socket subscription client.

## Rationale

This uses the native DMS extension model and Herdr's recommended CLI integration
layer with no additional runtime dependencies or persistent state.

## Consequences

Installation is a plugin-directory symlink, with no background service to manage.
Updates have polling latency and launch one short-lived CLI child per widget
instance per interval. One selected local session is monitored; cross-session
and remote-machine aggregation are outside this initial scope.
