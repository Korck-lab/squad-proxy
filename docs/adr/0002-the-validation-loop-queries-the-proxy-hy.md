# ADR-0002: The validation loop 'queries the proxy hypothesis', but the proxy is ...

- Status: proposed
- Date: 2026-06-30

## Context
Raised during spec: The validation loop 'queries the proxy hypothesis', but the proxy is a session-scoped agent reachable only via SendMessage under the one-proxy-per-session invariant. Whether validate pings the live session proxy or spawns an ephemeral evaluation agent briefed with the candidate identity is unspecified and could be read as conflicting with the single-proxy invariant.

## Decision
Pin the mechanism: have proxyme-validate spawn a distinct, throwaway evaluation agent (not named 'proxy', not flag-registered) briefed with the candidate identity, so the held-out scoring never touches or duplicates the session's live proxy.

## Consequences
(to be assessed on acceptance)

## Alternatives
(to be enumerated on acceptance)
