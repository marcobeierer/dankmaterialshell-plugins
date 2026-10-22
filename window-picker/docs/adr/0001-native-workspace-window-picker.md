# Native workspace-aware window picker

- Date: 2026-10-22
- Status: accepted

## Context

The plugin needs a global shortcut, live workspace grouping, search, and window
activation without requiring a bar widget. The repository targets DMS 1.6.

## Decision

Use a single daemon-surface QML plugin with an IPC handler and a native DankModal.
Read Hyprland's Quickshell models or DMS's NiriService, and activate through DMS's
compositor services. Keep normalization and filtering in a local JavaScript module.
Require DMS 1.6.2 and advertise only Hyprland and Niri support.

## Rationale

The native models already subscribe to compositor events. This avoids subprocess
polling, duplicate socket clients, extra runtime dependencies, and separate
shortcut or settings infrastructure.

## Consequences

The picker follows DMS's theme and modal focus lifecycle, works without a bar
widget, and does not edit user keybindings. Its integration depends on DMS service
APIs; supporting other compositors requires additional workspace-aware adapters.
The user must configure a compositor shortcut explicitly.
