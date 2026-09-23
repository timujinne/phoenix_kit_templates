# PR #1 — Escape HTML substitution by default, with a `{{{raw}}}` opt-out

**Author:** timujinne · **Merged:** 2026-09-23 (`7096c87`) · **Reviewer:** Claude
**Released as:** 0.2.0

## Summary

`render/4` now HTML-escapes bound `{{variable}}` values in the `html` part.
`{{{variable}}}` substitutes raw in every part. Both forms are matched by one
left-to-right regex pass. This closes the "NOT FIXED — HTML part substitutes
variables unescaped" finding from the 2026-09-16 library review.

The core logic is correct. I checked the regex by hand against every row of
the moduledoc's boundary table. `raw == ""` reliably tells the two branches
apart, because `Regex.replace/3` passes `""` for a group that did not match.
Options are validated even when `content` is `nil`. Every boundary case is
tested both bound and unbound. The findings below are about release hygiene
and one small simplification.

## Findings

### BUG - MEDIUM — docs pointed at a CHANGELOG upgrade note that did not exist (fixed)

The README, the `render/4` doc and the `Templates` moduledoc all say "see the
CHANGELOG for the full upgrade note", and they describe the change as 0.2.0.
The PR added no CHANGELOG entry, and `mix.exs` was still at `0.1.2`. If this
had been published as-is, a host upgrading into a breaking change would have
followed the docs to a note that isn't there.

Fix: bumped to 0.2.0 and added a CHANGELOG entry with a **Breaking** section.
It covers two things a host has to act on:
- rename markup-carrying placeholders to `{{{var}}}`
- stop pre-escaping values it used to escape itself, or they are now escaped
  twice

It also records the parser change the PR's own review note calls out:
`{{{x}}}` in `subject`/`text` used to render `{V}` and now renders `V`.

### IMPROVEMENT - LOW — escaping ran five chained `String.replace` passes (fixed)

The old version was correct only because `&` came first. Its comment even had
to explain that order. It is now a single `String.replace/3` with a list
pattern and a replacement function. The value is scanned once, so the order of
the replacements no longer matters. Added a test that checks every occurrence
is escaped, with multibyte text between the occurrences.

### NOTE — core is not affected until it opts in

`phoenix_kit` pins `~> 0.1.0`, which cannot resolve 0.2.0. So nothing changes
for existing hosts until core raises the pin. That is the right outcome for a
breaking change. Raising the pin is a deliberate core change, and it should be
paired with a check that no core default `html` part depends on raw
substitution. None does today: core's auth emails are text-only.

### NOTE — the database path does not escape (not in scope)

When `PhoenixKit.Email.Content.resolve/5` finds a database template, it
renders through `phoenix_kit_emails`' own `{{var}}` substitution, which still
does not escape. So the same variable is escaped on the file/default path and
raw on the database path. The fix belongs in `phoenix_kit_emails`, not here.

### NITPICK — `variables/1` re-runs a second regex per match (left)

`variables/1` pulls the whole match, then extracts the name with a second
regex. The comment explains why: `:re` drops a trailing group that did not
match. The alternatives, such as named captures or trimming braces, are no
simpler. Left as it is.

## Gate

`mix format`, `compile --warnings-as-errors`, `deps.unlock --check-unused`,
`credo --strict`, `dialyzer`: clean. Tests: 6 doctests, 76 tests, 0 failures.
