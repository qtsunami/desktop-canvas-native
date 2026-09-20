# Desktop Canvas Native UI System

The searchable design catalog did not return a verified macOS utility match, so this project uses the selected grayscale prototype and native macOS controls as its source of truth.

## Principles

- Prefer standard SwiftUI and AppKit controls over custom chrome.
- Use system typography, semantic colors, materials, spacing, focus, and disabled states.
- Keep the permission explanation explicit before invoking the system prompt.
- Use a single primary action per section and place errors beside the failed action.
- Keep window selection locked while a workspace is active, but leave safe layout controls available for immediate adjustment.
- Explain whether a setting applies immediately or on the next activation; preserve the original restore point across live changes.
- All core operations must be keyboard reachable and VoiceOver labeled.
- Respect Increase Contrast, Reduce Transparency, and Reduce Motion automatically through system components.
- Never use color alone for permission, error, or selection state.

## Visual direction

- Platform: macOS 14+
- Tone: restrained, functional, trustworthy
- Palette: system background, control background, label, secondary label, separator, accent color
- Typography: San Francisco system text; no bundled fonts
- Density: standard macOS settings density
- Motion: system-default only; no decorative animation

## Core surfaces

- Main window: grouped form with permission, window selection, target display, live split preview, actions, and logs.
- Menu bar: status, open-window action, apply, live ratio/side/display controls, restore, refresh, quit.
- Future overlay: nonactivating AppKit panel with clearly labeled controls and no content interception.
