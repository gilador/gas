# 0003. The floating panel moves only by its handle

- **Status:** Superseded by ADR-0007
- **Date:** 2026-10-22

## Context

The floating panel had a white pill on its edge that flipped it between vertical and horizontal, and it could be dragged from anywhere on the strip, where a still click also opened the menu. The pill looked like a drag handle, so users dragged it and flipped the layout by accident, and a slightly moving click on the strip dragged the panel instead of opening the menu.

## Decision

- The pill is the drag handle and the only place that moves the panel. It shows while the pointer is inside the panel. AppKit's drag-by-background is off.
- A click anywhere else on the strip opens the menu.
- Flipping the layout moves to a small curved arrow right after the handle (above it in the horizontal panel). It shows only while the pointer is over it.
- Settings → Display gets a "Horizontal panel" toggle for the same choice.

## Consequences

- No accidental flips or drags; the strip is a plain button for the menu.
- Moving the panel needs the pointer on a small target, about 18 × 12 pt.
- Hover is read from the tracked pointer (`PointerTracker`), because SwiftUI hover stays silent in this never-active app.
