# 0001. Record architecture decisions

- **Status:** Accepted
- **Date:** 2026-10-22

## Context

gas is built by people and coding agents. Specs in `docs/superpowers/specs/` describe what a feature does, and plans describe how it is built. Neither records *why* a choice was made over the alternatives, so a later change can undo a deliberate decision without knowing it.

## Decision

Record each decision that shapes how gas looks or works, or that would be easy to reverse by accident, as an ADR in `docs/adr/`, using [`template.md`](template.md).

## Consequences

- A change that reverses a decision has an ADR to read first, and adds a new one.
- A small extra step when a decision is made. Routine changes don't need an ADR.
