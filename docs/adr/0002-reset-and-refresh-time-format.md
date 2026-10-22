# 0002. Reset and refresh times read as wall-clock times and countdowns

- **Status:** Accepted
- **Date:** 2026-10-22

## Context

The menu showed when a limit resets as a relative time ("Resets in 6 days"), and the next refresh as a clock time ("Next refresh 9:43"). Both were the wrong way round for how they are used:

- A reset is planned around. "In 6 days" doesn't say whether that's Friday morning or Friday night, and it changes meaning as the days pass.
- A refresh is waited for. "9:43" makes the reader do the subtraction.

## Decision

**Resets** show the wall-clock moment, made in `ResetTime.text` (UsageCore):

- Later today: "Resets at 4pm"
- In the next 6 days: "Resets on Friday at 2am"
- 7 or more days away: "Resets on Oct 30 at 2am", because the weekday alone would be ambiguous
- Times are 12-hour with lowercase am/pm, minutes only when not zero ("4:30pm"), rounded to the nearest minute, with English names whatever the system locale, because the app is in English.

An ⓘ icon after the reset line shows the exact time left on hover ("6 days, 3 hours and 12 minutes left", `ResetTime.remaining`), for when the relative time matters.

**The next refresh** is a live countdown: "Next refresh in 15 mins" (`RefreshCountdown.text`). It counts whole minutes rounded up, so it never shows seconds ("34 s" reads "in 1 min"), and uses hours past 60 minutes ("in 1 hr 5 mins"). The view redraws every second so the minute changes on time; the text itself changes once a minute. It appears once, in the menu footer next to the last update ("Updated 43s ago · Next refresh in 15 mins"), not under each provider, because one shared timer refreshes every provider; the soonest provider's refresh is shown. (Claude can refresh later, because gas waits at least 4.5 minutes between Claude requests.)

## Consequences

- The formatting is in UsageCore with unit tests, not inline `Date.formatted` calls in views.
- English-only output: localizing gas later means replacing these formatters, not just adding strings.
- "Resets at 4pm" can stay on screen briefly after 4pm, until the next refresh brings the new reset time. This was accepted to keep the views simple.
- Seconds are never shown for refreshes, so the countdown can read "in 1 min" for up to a minute.
- Hover hints (the ⓘ time left, and "Try again in 42 seconds" on the disabled refresh button) are drawn inside the menu (`HoverHint`), not as tooltips or popovers. A tooltip never appeared because the line redraws every second, and a popover is its own window, so opening it ended the hover and it closed at once.
