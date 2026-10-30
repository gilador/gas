# 0007. The floating panel moves from anywhere on it

- **Status:** Accepted
- **Date:** 2026-10-30

## Context

ADR 0003 made the handle the only place that moves the panel. Users found the 18 × 12 pt target too small and complained they couldn't drag the panel.

## Decision

- A drag anywhere on the panel moves it. A drag on the strip starts after 3 pt of movement, so a still click still opens the menu.
- The handle stays and still shows while the pointer is inside the panel, as a sign the panel can move.
- The rotate arrow is gone. The handle sits in a 12 pt band along the top edge (the right edge in the horizontal panel). While the pointer is on the band, that border lights up, and a click on it flips the layout.
- The "Horizontal panel" toggle and AppKit's drag-by-background staying off are unchanged from ADR 0003.

## Consequences

- Moving the panel no longer needs a precise target.
- A click that moves more than 3 pt drags the panel instead of opening the menu.
- Flipping the layout has a larger target than the arrow had, and the lit border shows it before the click.
