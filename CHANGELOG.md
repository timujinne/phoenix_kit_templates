# Changelog

## 0.1.2 - 2026-09-16

### Fixed

- **Invalid input no longer creates cache entries.** `Overrides.read/4` checks
  the name, part and locale before it touches `:persistent_term`. A malformed
  locale now shares the `nil` locale's cache entry, and an invalid name or
  unknown part returns `nil` without caching anything. Before, each of these
  added a permanent key, and every new key copies the whole table.
- `Overrides.read/4` now raises on a bare string root instead of quietly finding
  no overrides. The old behaviour also cached a key that made a later
  `reset_cache/1` crash. `render/4` treats `paths: nil` as `[]`.
- The hexdocs source links now point at the `v<version>` tag instead of a ref
  that doesn't exist.
- The README and moduledoc example called `gettext("Hi %{email}, …")` without
  bindings, which raises. It now uses a `{{user_email}}` placeholder.

### Changed

- Locales can have up to three subtags and lose one at a time on fallback:
  `zh-Hant-TW` → `zh-Hant` → `zh` → locale-less. Before, any locale with more
  than one subtag skipped straight to the locale-less file.
- `render/4` and `missing_variables/4` now share one resolution function, so the
  check always sees the same content the render sends.

## 0.1.1 - 2026-09-06

### Documentation

- **Made the on-disk layout unmissable.** A template's `name` is a *directory*,
  not a filename — the one thing the 0.1.0 docs never actually stated, and the
  first thing anyone writing an override needs to know. Every doc now leads with
  it and carries a worked tree: `PhoenixKit.Templates` for the conceptual model
  and the full resolution order, `PhoenixKit.Templates.Overrides` for the lookup
  rules, and the README for practical use.
- Recorded why there is no `slug` and no `display_name`: `name` is validated as
  `[a-z0-9][a-z0-9_\-]*` precisely because it is a path segment, so it is
  slug-shaped by necessity and a second identifier would address nothing.
- Folded the duplicated part/extension listing into one table, keyed by which
  channel reads each part.

No code changes; `0.1.0` and `0.1.1` are functionally identical.

## 0.1.0 - 2026-09-06

Initial release.

- `PhoenixKit.Templates.render/4` resolves a named template per part — host
  override for the recipient's locale, then base language, then locale-less,
  then the caller's default — and substitutes `{{variables}}`. Parts resolve
  independently, so a host overriding only `html` keeps the package's
  translated `subject` and `text`.
- `PhoenixKit.Templates.missing_variables/4` reports unbound placeholders per
  part, for a test or a preview screen. `render/4` itself never raises over one:
  a message with a flawed line still beats a message that never arrives.
- `PhoenixKit.Templates.Overrides` reads host override files at runtime and
  caches them in `:persistent_term`, the absence of a file included. `name` and
  `locale` are validated before being joined onto a root.
- No runtime dependencies, deliberately: `phoenix_kit` depends on this package,
  so anything pulled in here lands upstream of the entire tree.
