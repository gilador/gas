# Extended panel mode — Design Spec

**Date:** 2026-10-15
**Builds on:** `2026-07-18-desktop-usage-panel-design.md`

## Goal
The floating panel has one strip per provider. Each strip holds a single bar that layers the session (5h) and weekly usage, with one number for the limit that blocks first. This stays the default because it takes the least space.

Some users want to read the two limits apart. A new **Extended** mode looks the same as the compact one, but the single layered bar becomes **two bars side by side**: session and weekly.

## Behavior
- **Setting:** a toggle in Settings → Display, "Separate bars", under "Show remaining". Both Display settings are toggles. Off by default. Stored in `@AppStorage("panelExtended")`. The panel switches at once.
- **Same strip as compact:** icon, the one headline percent (the limit that blocks first), the bars, the age. The vertical panel stays 44 pt wide; the two 8 pt bars sit 4 pt apart.
- **Orientation is separate.** The flip pill still switches vertical and horizontal. In the horizontal panel the pair is turned 90° clockwise like the compact bar, so session is on top and weekly below.
- **Bars:** session on the left, weekly on the right. Each is filled green, orange or red by its own severity, like the compact front layer. The per-model pointer (`weekly_scoped`) sits on the outer side of the weekly bar. Each bar has its own tooltip. A small letter names each bar: "h" under the session bar and "w" under the weekly bar (to the left of each bar in the horizontal panel, where the bars are turned one by one so the letters stay upright).
- **Weekly-only plans (Codex):** when a provider reports no session limit, it shows **one** bar, the weekly one, the same as the compact strip. No empty slot. The same holds for a provider that reports only a session limit.
- **Unchanged:** the alert triangle, the age, the status glass for stale, signed-out and error states, the tooltip, the update dot, the flip pill, tap to open the menu.

## Weekly-only data
`OpenAIUsageMapper` names the limits by position: `primary_window` becomes `session` and `secondary_window` becomes `weekly_all`. A plan with only a weekly window may report it as the primary window, and gas would then call it "session" with the label "Weekly". The mapper must decide by window length: a window of one day or more is `weekly_all`, a shorter one is `session`. When the length is missing, or both windows would get the same id, the position rule stays.

`UsageSnapshot` gets `sessionLimit`, `weeklyLimit` and `scopedLimit`, so the views stop matching ids themselves.

## Out of scope
- Showing more than session and weekly (for example a second per-model bar).
- A shortcut for the new mode on the panel itself.
