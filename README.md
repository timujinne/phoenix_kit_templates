# phoenix_kit_templates

Locale-aware rendering for outbound message content — email, push, Telegram,
SMS, the in-app inbox. One renderer for every channel, so localized and
customizable copy is built the same way everywhere instead of once per channel.

```elixir
PhoenixKit.Templates.render(
  "new_login_alert",
  %{subject: gettext("New login to your account"), text: gettext("Hi %{email}, …")},
  %{"ip_address" => ip},
  locale: "uk",
  paths: [Application.app_dir(:my_app, "priv/phoenix_kit_templates")]
)
#=> %{subject: "…", text: "…", html: nil}
```

## Two layers

A template has a **default**, shipped by the package that sends the message,
and an optional **override**, shipped by the host application.

The caller passes the default in *already localized*. That split is the whole
design: translation belongs to the sending package's Gettext backend, and
reaching for one here would make this package depend on it. A shipped default
expressed as one file per locale would fork the same sentence seven ways and
drift; expressed as a Gettext call it rides the extraction and translation
pipeline that package already runs.

Files are how a **host** overrides — a host writes one or two languages, not
seven — and how chrome-bearing HTML gets authored.

Resolution runs per part, independently:

```
1. host override · recipient locale     text.en-GB.txt
2. host override · base language        text.en.txt
3. host override · locale-less          text.txt
4. the default the caller passed in
```

Independence matters: a host that overrides only `html` keeps the package's
translated `subject` and `text` rather than having to restate them.

## Override layout

**The template's name is a directory, not a filename.** Files inside it are
named for the part they supply, optionally carrying a locale:

```
priv/phoenix_kit_templates/     <- a root, passed as :paths
└── new_login_alert/            <- the template NAME (a directory)
    ├── subject.txt             <- <part>.<ext>
    ├── subject.de.txt          <- <part>.<locale>.<ext>
    ├── text.txt
    ├── text.de.txt
    └── html.html
```

Parts are named for what they are rather than for email, because every channel
reads the same three:

| part | file | read by |
|---|---|---|
| `subject` | `subject[.locale].txt` | email subject line, push title |
| `text` | `text[.locale].txt` | email body, push body, Telegram, SMS, in-app inbox |
| `html` | `html[.locale].html` | email only — optional |

Given that tree, a German recipient resolves to `subject.de.txt` + `text.de.txt`;
an Italian one falls through to `subject.txt` + `text.txt`. A host that wrote
only `text.txt` still gets the package's translated subject in every language —
parts are looked up independently.

A directory rather than flat files because one template is up to three parts
times however many locales a host translates. Flat, they would interleave with
every other template's files and you would be reading filename prefixes to tell
them apart; grouped, a template is one folder to copy, diff or delete.

`html` is genuinely optional, not nominally so: a text-only template is the
normal case. Core's own auth emails ship without one — short transactional
messages where plain text wins on the merits (no image blocking, no dark-mode
breakage, no client-specific CSS, better deliverability).

Overrides live in the host application, which compiles separately from this
package — so they are read at runtime and cached in `:persistent_term`, the
absence of a file included.

### The name is the slug

There is no separate slug, and no `display_name`. `name` is validated as
`[a-z0-9][a-z0-9_\-]*` — slug-shaped by construction, because it is a directory
name on disk and has to be safe to join onto a path.

The database schema this replaces carried both, for a reason that no longer
exists: `name` identified the template while `slug` addressed the admin
editor's routes (`…/templates/:slug`), and `display_name` labelled its list
view. With no editor and no routes, a second identifier addresses nothing. A
human-readable label, if one is ever wanted, is a Gettext call in the sending
package rather than a stored column — the same place its subject and body
already live.

## Placeholders

`{{variable}}`, with optional inner whitespace, matching the syntax the
database-backed email templates used so exported content carries over unchanged.
Atom and string keys are both accepted.

An **unbound placeholder is left verbatim**, not blanked, and never raises. Both
are wrong, but a visible `{{user_emial}}` announces the typo in a preview or a
test, while a silent empty string reads as finished copy and ships — and a
message with one flawed line still beats a message that never arrives. Callers
that want it to be an error ask `missing_variables/4` up front.

## No runtime dependencies

Deliberate: `phoenix_kit` depends on this package, so anything pulled in here
lands upstream of the entire tree.

## License

MIT
