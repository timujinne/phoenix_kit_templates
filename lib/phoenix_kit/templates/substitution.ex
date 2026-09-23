defmodule PhoenixKit.Templates.Substitution do
  @moduledoc """
  `{{variable}}` substitution, with an `{{{variable}}}` opt-out from escaping.

  The double-brace syntax matches what the database-backed email templates
  used, so content exported from those rows carries over unchanged.
  Surrounding whitespace is allowed: `{{user_email}}` and `{{ user_email }}`
  are the same placeholder.

  ## Escaping is per call, not per syntax

  `substitute/3` takes an `:escape` option (default `false`). When it is
  `true` — which `PhoenixKit.Templates.render/4` passes only for the `html`
  part — a `{{variable}}` value is HTML-escaped (`&` `<` `>` `"` `'`), the same
  set `Phoenix.HTML` escapes. This package has no runtime dependencies by
  design (see the README), so escaping is implemented here rather than by
  depending on `phoenix_html`. The value is always treated as data, never as
  markup to preserve: a value that already contains `&amp;` is escaped again,
  because a renderer cannot tell "already-escaped markup" from a customer name
  that happens to contain the literal text `&amp;`.

  `{{{variable}}}` (triple braces) is the escaping opt-out, for a variable that
  already holds rendered HTML — billing's `line_items_html` is the motivating
  case. It is **always substituted raw**, regardless of the `:escape` option,
  in every part. In `subject` and `text` — which are never escaped, being
  plain text — `{{{variable}}}` and `{{variable}}` are therefore identical:
  the triple-brace spelling exists so the same template content is valid
  pasted into any of the three parts, not because those parts have their own
  escaping to opt out of.

  `substitute/2` calls `substitute/3` with `escape: false`, i.e. plain
  semantics: neither syntax escapes. That is also what `subject` and `text`
  effectively get from `render/4`.

  ## Unbound placeholders are left alone, verbatim, in either syntax

  A placeholder with no matching variable is emitted **exactly as written** —
  including its own spelling of inner whitespace — not blanked. Both
  alternatives are wrong, but a visible `{{user_emial}}` announces the typo in
  a preview or a test, while a silent empty string reads as finished copy and
  ships. The renderer never raises over one — a message with a flawed
  placeholder must still send — so callers that want it to be an error ask
  `missing/2` up front.

  ## Parsing: one left-to-right pass, triple tried before double

  Both forms are matched by a single regular expression whose alternation
  tries the three-brace form first at every position. Regex alternation in
  Elixir (backed by PCRE) is leftmost-first, not leftmost-longest, which is
  exactly the ordering this needs: a naive *second* pass for `{{{raw}}}` after
  a first pass for `{{var}}` does not work, because the first pass matches the
  *inner* pair of a triple-brace placeholder and leaves a stray `{value}`
  behind. One ordered pass never sees that inner pair as a candidate on its
  own.

  Braces that do not complete a full double- or triple-brace placeholder are
  left as literal text — this is what keeps single `{`/`}` in legacy content,
  and CSS like `body { margin: 0 }` or `@media (…) { … }` inside an `html`
  part, untouched. A placeholder never spans a literal brace that is not part
  of it.

  Boundary cases, fixed by test (`substitution_test.exs`) and worth stating
  here because the "obvious" reading of a couple of them is wrong:

  | input | with `%{x: "V"}` | why |
  |---|---|---|
  | `{{{x}}}` | `V`, raw | plain triple-brace |
  | `{{{ x }}}` | `V`, raw | inner whitespace ignored, as with double braces |
  | `{{ x }}` | `V` (escaped if `escape: true`) | plain double-brace |
  | `{{{{x}}}}` | `{V}` | the two *outer* braces on each side are literal; the *inner* six form one triple-brace placeholder |
  | `{{{x}}` | `{V}` (escaped if `escape: true`) | only two closing braces exist, so the triple alternative can't complete; the engine retries as *double*-brace starting one character in, leaving the first `{` as a literal, matching `{{x}}` as an escapable placeholder |
  | `{{x}}}` | `V}` (escaped if `escape: true`) | mirror of the above: `{{x}}` matches as double-brace, the extra trailing `}` is literal |
  | `{ {{x}} }` | `{ V }` | single outer braces are never part of any placeholder — a placeholder always starts with two consecutive `{` |

  An unbound `x` in any of the rows above reproduces the input byte-for-byte:
  the "why" column still applies to which span is a placeholder, but a
  placeholder with no binding is emitted as its own matched text rather than
  substituted.
  """

  @placeholder ~r/
    \{\{\{\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*\}\}\}
    |
    \{\{\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*\}\}
  /x

  @name ~r/[a-zA-Z_][a-zA-Z0-9_]*/

  @typedoc "Variables to interpolate. Keys may be atoms or strings."
  @type variables :: %{optional(atom() | String.t()) => term()}

  @doc """
  The placeholder names appearing in `content`, in order, without duplicates.

  Recognizes both `{{name}}` and `{{{name}}}` — the name from either syntax is
  `"name"`.

      iex> PhoenixKit.Templates.Substitution.variables("Hi {{name}}, {{{name}}} again")
      ["name"]
  """
  @spec variables(String.t() | nil) :: [String.t()]
  def variables(content) when is_binary(content) do
    # Not `capture: :all_but_first`: the underlying `:re` capture vector omits
    # a *trailing* group that did not participate, rather than reporting "".
    # The double-brace alternative holds the second, higher-numbered group
    # here, so a triple-brace match — where only the first group participates
    # — comes back as a one-element list, while a double-brace match comes
    # back as two. Pulling the whole match and re-extracting the name
    # sidesteps that asymmetry instead of relying on a fixed shape.
    @placeholder
    |> Regex.scan(content, capture: :first)
    |> Enum.map(fn [whole] -> Regex.run(@name, whole) |> hd() end)
    |> Enum.uniq()
  end

  def variables(_content), do: []

  @doc """
  Replaces every bound placeholder in `content` with plain semantics: neither
  `{{name}}` nor `{{{name}}}` is escaped. Equivalent to `substitute/3` with
  `escape: false`.

      iex> PhoenixKit.Templates.Substitution.substitute("Hi {{name}}", %{name: "Ada"})
      "Hi Ada"

      iex> PhoenixKit.Templates.Substitution.substitute("Hi {{name}}", %{})
      "Hi {{name}}"
  """
  @spec substitute(String.t() | nil, variables()) :: String.t() | nil
  def substitute(content, variables), do: substitute(content, variables, [])

  @doc """
  Replaces every bound placeholder in `content`.

  ## Options

    * `:escape` — when `true`, a bound `{{name}}` value is HTML-escaped
      (`&` `<` `>` `"` `'`, matching `Phoenix.HTML`). Defaults to `false`.
      `{{{name}}}` is never escaped, regardless of this option — it is the
      opt-out for a variable that already holds rendered HTML.

  ```
  iex> PhoenixKit.Templates.Substitution.substitute(
  ...>   "<p>{{name}}</p>",
  ...>   %{name: "<b>Ada</b>"},
  ...>   escape: true
  ...> )
  "<p>&lt;b&gt;Ada&lt;/b&gt;</p>"

  iex> PhoenixKit.Templates.Substitution.substitute(
  ...>   "<p>{{{name}}}</p>",
  ...>   %{name: "<b>Ada</b>"},
  ...>   escape: true
  ...> )
  "<p><b>Ada</b></p>"
  ```
  """
  @spec substitute(String.t() | nil, variables(), keyword()) :: String.t() | nil
  def substitute(nil, _variables, _opts), do: nil

  def substitute(content, variables, opts) when is_binary(content) do
    escape? = Keyword.get(opts, :escape, false)
    bound = normalize(variables)

    Regex.replace(@placeholder, content, &replace_match(&1, &2, &3, bound, escape?))
  end

  defp replace_match(whole, raw, escapable, bound, escape?) do
    case Map.fetch(bound, placeholder_name(raw, escapable)) do
      {:ok, value} -> render_value(value, escape? and raw == "")
      :error -> whole
    end
  end

  defp render_value(value, escape?) do
    value = to_string(value)
    if escape?, do: escape_html(value), else: value
  end

  @doc """
  Placeholder names in `content` that `variables` does not bind.

  Recognizes both `{{name}}` and `{{{name}}}`, like `variables/1`.

  Empty means every placeholder will be filled.

      iex> PhoenixKit.Templates.Substitution.missing("{{a}} {{{b}}}", %{a: 1})
      ["b"]
  """
  @spec missing(String.t() | nil, variables()) :: [String.t()]
  def missing(content, variables) do
    bound = normalize(variables)
    content |> variables() |> Enum.reject(&Map.has_key?(bound, &1))
  end

  # The alternation's non-matching branch captures as "", never nil, so a
  # plain equality check picks out whichever branch actually matched.
  defp placeholder_name(raw, _escapable) when raw != "", do: raw
  defp placeholder_name(_raw, escapable), do: escapable

  # No `phoenix_html` dependency, deliberately (see the moduledoc): this
  # package is a hard dependency of `phoenix_kit` core, so nothing here may
  # pull anything in. `&` first, so the entities this introduces are not
  # themselves re-escaped by the later replacements.
  defp escape_html(value) do
    value
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end

  # Atom and string keys are both accepted so a caller can write %{user_email: …}
  # while content exported from the old templates keeps its "user_email" keys.
  defp normalize(variables) when is_map(variables) do
    Map.new(variables, fn {key, value} -> {to_string(key), value} end)
  end

  defp normalize(_variables), do: %{}
end
