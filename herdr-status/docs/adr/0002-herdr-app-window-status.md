# Combine the Herdr app window and the Herdr CLI

- Date: 2026-11-21
- Status: accepted
- Supersedes: [0001](0001-native-herdr-widget.md)

## Context

Agents can now run in the Herdr desktop app (`herdr-app` 0.1.16), whose terminals
run in herdr-core (`hc`), as well as in the `herdr` CLI. `herdr agent list`
returns none of the app's agents. `hc ls` reports raw status words, but only the
app knows whether someone has looked at a finished agent, which is what the blue
"results ready" state means. Users may run either or both.

## Decision

Poll `herdr-app ls` and `herdr agent list` side by side each interval, each with
its own bounded, non-overlapping request, and combine the agents of every source
that answers. Show gray only when neither answers. In the app, count terminals
that report a status as agents and treat `error` as needing attention, like the
app's agents list. Keep the CLI's executable and session settings; add one for
the app's executable. Let Herdr own agent detection and acknowledgement as before.

## Rationale

`herdr-app ls` is the app's public read-only view and names agents by the spaces
and tabs the user sees. Combining both sources needs no mode setting and keeps
existing CLI installations working after an update.

## Consequences

- One widget covers app and CLI agents, with no source to choose.
- Each poll launches two short-lived child processes per widget instead of one.
- A source that is not in use fails every poll; that is silent unless its output
  is unreadable, so a broken source can go unnoticed while the other answers.
- When the app window is closed, its agents keep running in herdr-core but are
  not shown until the window opens again.
- App agents show space and tab instead of terminal title and directory.
- App sub-agents without their own pane are not counted.
