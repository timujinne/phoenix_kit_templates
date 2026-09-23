# Library review — 0.1.1 → 0.1.2

**Date:** 2026-09-16
**Scope:** the whole package as released in 0.1.1 (no PR), plus how
`phoenix_kit` core consumes it (`PhoenixKit.Email.Content`, `Mailer`,
`UserNotifier`) and billing's variables.

Gate at start: format, `compile --warnings-as-errors`, `credo --strict`,
dialyzer and 32 tests all clean. Every finding below is about behaviour, not lint.

## Findings

### BUG - MEDIUM — junk input minted permanent cache entries (fixed)

`Overrides.read/4` built its `:persistent_term` key from the raw arguments
*before* validating them. An invalid name, unknown part or malformed locale each
produced a lookup that was guaranteed to miss — and then cached that miss under
its own key. Persistent terms are never collected, and every new key copies the
whole table, so a stream of distinct junk locales (locale originates in user
data) grows the table and slows every later insertion.

Fix: validate name and part first and return `nil` without touching the cache;
normalize an unparseable locale to `nil` so it shares `nil`'s entry, which is
what it resolved to anyway. Test: `junk input cannot mint cache entries of its own`.

### BUG - MEDIUM — hexdocs "source" links pointed at a ref that does not exist (fixed)

`docs: [source_ref: @version]` resolves to `0.1.1`, but the tags are `v0.1.1`,
so every "View source" link on hexdocs 404'd. Now `"v#{@version}"`.

### BUG - LOW — a string root was silently accepted, then crashed `reset_cache/1` (fixed)

`read("priv/x", …)` fell through a catch-all to `nil` — hiding a caller bug as
"no overrides" — *and* cached that key with a binary in the roots slot, which
made a later `reset_cache(["…"])` raise `Protocol.UndefinedError` in
`Enum.any?/2`. `read/4` now guards `is_list(roots)`. `render/4` treats an
explicit `paths: nil` as `[]`, since `Keyword.get/3`'s default does not apply to
a present-but-nil key.

### BUG - LOW — README / moduledoc example would raise (fixed)

`gettext("Hi %{email}, …")` without bindings raises
`Gettext.MissingBindingsError`. The example now uses a `{{user_email}}`
placeholder and binds it, which is also the point of the package.

### IMPROVEMENT - LOW — multi-subtag locales fell all the way to locale-less (fixed)

The locale pattern allowed one subtag, so `zh-Hant-TW` was "unparseable" and
skipped even `zh`. It now accepts up to three subtags and drops one at a time:
`zh-Hant-TW` → `zh-Hant` → `zh` → locale-less. Capped at three so a long tag
cannot fan out into many `File.read`s.

### IMPROVEMENT - LOW — resolution duplicated between render and missing_variables (fixed)

Both functions carried their own copy of "override, else default". Extracted to
one private `resolve/4`, so the check can never inspect different content from
what the render sends.

### FIXED (0.2.0) — HTML part substitutes variables unescaped

`{{variable}}` values went into `html` verbatim. A value carrying markup — a
user name, a company name — became live HTML in the email. This matched the
database templates it replaces (`Template.substitute_string/2` does a plain
`String.replace`), so it was not a regression, but it was the wrong default.

Deliberately deferred to 0.2.0 rather than slipped into a patch: billing passes
a pre-rendered `line_items_html` variable that must stay raw, so escaping needed
an opt-out at the same time, and changing substitution semantics is a breaking
change for any exported override. No core template ships an `html` part today,
so exposure was limited to host-written overrides.

Fixed in `PhoenixKit.Templates.Substitution` (PR:
BeamLabEU/phoenix_kit_templates#1): `html` now HTML-escapes a bound
`{{variable}}` value; `{{{variable}}}` (triple braces) is the opt-out,
substituting raw in every part. `subject` and `text` are unaffected — never
escaped, and `{{{variable}}}` there is identical to `{{variable}}`. See the
README's "Placeholders" section and the `Substitution` moduledoc for the
parsing rules and boundary-case table.

### NOT FIXED — non-`String.Chars` values raise

`to_string/1` on a map or tuple variable raises inside `render/4`, which the
docs describe as never raising. That is a programmer error at the call site, and
the alternative (`inspect/1`) would ship `%{…}` into a customer's inbox; left
as-is.

## Gate after fixes

format, `compile --warnings-as-errors`, `credo --strict`, dialyzer, `mix docs`
(no warnings), 4 doctests + 35 tests — all clean.
