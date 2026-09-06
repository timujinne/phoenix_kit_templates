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

```
<root>/<name>/<part>.<locale>.<ext>
<root>/<name>/<part>.<ext>
```

`subject` and `text` are `.txt`; `html` is `.html`. Overrides live in the host
application, which compiles separately from this package — so they are read at
runtime and cached in `:persistent_term`, the absence of a file included.

## Parts

`subject`, `text` and `html`, named for what they are rather than for email:
push uses subject-as-title plus text, Telegram and SMS use text alone, the inbox
uses text. `html` is genuinely optional — a text-only template is the normal
case, not a stub.

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
