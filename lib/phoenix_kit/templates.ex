defmodule PhoenixKit.Templates do
  @moduledoc """
  Renders a named message template for a recipient.

  One renderer for every channel — email, push, Telegram, SMS, the in-app inbox
  — so localized, customizable message content is built the same way everywhere
  instead of once per channel.

  ## The two layers

  A template has a **default**, shipped by the package that sends the message,
  and an optional **override**, shipped by the host application.

  The caller supplies the default already localized. That split is what keeps
  this package a leaf: translation belongs to the sending package's Gettext
  backend, and reaching for one here would mean depending on it.

      PhoenixKit.Templates.render(
        "new_login_alert",
        %{subject: gettext("New login to your account"), text: gettext("Hi %{email}, …")},
        %{"ip_address" => ip},
        locale: "uk",
        paths: [Application.app_dir(:my_app, "priv/phoenix_kit_templates")]
      )

  Resolution, per part and independently:

      1. host override · recipient locale     (text.uk.txt)
      2. host override · base language        (text.en.txt from "en-GB")
      3. host override · locale-less          (text.txt)
      4. the default the caller passed in     (already localized via Gettext)

  Independence matters: a host that overrides only `html` keeps the package's
  translated `subject` and `text` rather than having to restate them.

  ## Why the default is not a file

  A shipped default expressed as one file per locale forks the same sentence
  seven ways and drifts. Expressed as a Gettext call it rides the extraction and
  translation pipeline the sending package already runs, and ships translated.
  Files are how a *host* overrides — a host writes one or two languages, not
  seven — and how chrome-bearing HTML gets authored. See the design doc.

  ## Parts

  `subject`, `text` and `html`, named for what they are rather than for email:
  push uses subject-as-title plus text, Telegram and SMS use text alone, the
  in-app inbox uses text. `html` is genuinely optional — core's own auth emails
  ship text-only, so a template with no `html` is the normal case.
  """

  alias PhoenixKit.Templates.Overrides
  alias PhoenixKit.Templates.Substitution

  @typedoc "Rendered content, ready for a channel to deliver."
  @type rendered :: %{subject: String.t() | nil, text: String.t() | nil, html: String.t() | nil}

  @typedoc "Package-shipped content, already localized by the caller."
  @type defaults :: %{optional(Overrides.part()) => String.t() | nil}

  @doc """
  Renders `name` into `%{subject:, text:, html:}`.

  ## Options

    * `:locale` — the recipient's locale, dialect included (`"en-GB"`). `nil`
      selects only locale-less overrides.
    * `:paths` — host override roots, tried in order. Defaults to `[]`, which
      means the caller's defaults are used verbatim.

  Unbound `{{placeholders}}` survive into the output rather than blanking or
  raising; see `PhoenixKit.Templates.Substitution`.
  """
  @spec render(String.t(), defaults(), Substitution.variables(), keyword()) :: rendered()
  def render(name, defaults, variables \\ %{}, opts \\ []) when is_binary(name) do
    locale = Keyword.get(opts, :locale)
    paths = Keyword.get(opts, :paths, [])

    Map.new(Overrides.parts(), fn part ->
      content = Overrides.read(paths, name, part, locale) || Map.get(defaults, part)
      {part, Substitution.substitute(content, variables)}
    end)
  end

  @doc """
  Placeholder names that `render/4` would leave unbound, keyed by part.

  Parts that would render cleanly are omitted, so an empty map means the render
  is fully bound. Intended for a test or a preview screen — `render/4` itself
  never fails over a bad placeholder, because a message with one flawed line is
  still better than a message that never arrives.
  """
  @spec missing_variables(String.t(), defaults(), Substitution.variables(), keyword()) ::
          %{optional(Overrides.part()) => [String.t()]}
  def missing_variables(name, defaults, variables \\ %{}, opts \\ []) when is_binary(name) do
    locale = Keyword.get(opts, :locale)
    paths = Keyword.get(opts, :paths, [])

    Overrides.parts()
    |> Enum.reduce(%{}, fn part, acc ->
      content = Overrides.read(paths, name, part, locale) || Map.get(defaults, part)

      case Substitution.missing(content, variables) do
        [] -> acc
        names -> Map.put(acc, part, names)
      end
    end)
  end
end
