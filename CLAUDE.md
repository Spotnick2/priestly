# Claude Instructions

Read [AGENTS.md](AGENTS.md) for project-specific agent instructions.

## Consulting Codex

The shared `codex-consult` skill (user level) has the invocation and the gotchas. For this repo:

For Priestly specifically, good things to hand Codex: anything touching the secure buttons
(`PreClick`/`PostClick`, `RegisterForClicks`, attribute wiring), the aura cache and combat
secrecy in `BuffRem`/`API.ReadBuff`, an adapter in `PriestlyCompat.lua` (especially struct-vs-tuple
or a tri-state return), or a change to the `PriestlyDB` shape.

**Always hand it `docs/FOREVER-PROBE.md` and `AGENTS.md` alongside the diff.** Those findings are
measured on the live client, and a cold reviewer will otherwise argue from Classic-era or Retail
behaviour that does not hold here - that auras throw for the whole group in combat, that
account-wide SavedVariables never load, that the client's secure handler decides which mouse edge
acts. `C:/Projects/WoW/References/Forever/api/forever-api-<version>.<build>.md` (take the highest build) is the full measured API surface if a
question turns on whether something exists.
