# Extended panel mode — Plan

Spec: `docs/superpowers/specs/2026-10-15-extended-panel-design.md`

1. **Mapper by window length** (`UsageCore`, test first): weekly-only primary window maps to `weekly_all`; a short window maps to `session`; missing length or a clash keeps the positional ids.
2. **Snapshot accessors** (`UsageCore`, test first): `sessionLimit`, `weeklyLimit`, `scopedLimit` on `UsageSnapshot`.
3. **`ProviderStripItem`**: add an `extended` flag. Use the accessors in place of the id matching. In the extended mode, swap the layered bar for a pair of bars (turned for horizontal), with the one-bar case for a missing limit.
4. **`DesktopPanelView`**: read `panelExtended` and pass it down.
5. **`PreferencesView`**: an Extended toggle in the Display section, under the usage toggle, which turns from a Used / Remaining picker into a toggle too.
6. Run `swift test`, then build the app and check both modes in both orientations, with a Claude strip, a two-limit Codex strip and a weekly-only Codex strip.
