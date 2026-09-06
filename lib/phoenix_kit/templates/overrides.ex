defmodule PhoenixKit.Templates.Overrides do
  @moduledoc """
  Locates a host application's override file for one part of one template.

  A host customizes a message by dropping a file into its own repo, where it is
  version-controlled and reviewable, instead of editing a database row through
  an admin UI. Nothing here writes; an override is only ever read.

  ## Layout

      <root>/<name>/<part>.<locale>.<ext>
      <root>/<name>/<part>.<ext>

  `subject` and `text` are `.txt`; `html` is `.html`. A root is typically
  `Application.app_dir(:my_app, "priv/phoenix_kit_templates")`, but this module
  takes roots as an argument and reads no configuration of its own — it must not
  know which application is using it.

  Lookup runs most- to least-specific, and stops at the first file that exists:

      text.en-GB.txt   →   text.en.txt   →   text.txt

  so a host that only cares about one language writes `text.txt` and is done,
  while one that translates its overrides gets dialect precision. Roots are
  tried in order, so an earlier root shadows a later one.

  ## Runtime, not compile time

  Overrides live in the *host* application, which is compiled separately from
  this package — there is no point in this package's compilation at which they
  could be read. So they are read at runtime and cached in `:persistent_term`,
  including the *absence* of a file, since a missing override is the common case
  and would otherwise cost a `File.stat` on every send. Files cannot change
  without a deploy; `reset_cache/0` exists for tests and dev reloads.

  ## Path safety

  `name` and `locale` are matched against strict patterns before they are ever
  joined onto a root. They are literals at every current call site, but this
  module turns a name into a filesystem read, and that is not a boundary to
  leave to the caller's good behaviour — `../../../etc/passwd` resolves to no
  override rather than to a file.
  """

  @parts %{subject: "txt", text: "txt", html: "html"}

  @name_pattern ~r/\A[a-z0-9][a-z0-9_\-]*\z/
  @locale_pattern ~r/\A[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})?\z/

  @typedoc "Which part of a template to look for."
  @type part :: :subject | :text | :html

  @doc "The parts an override file can supply."
  @spec parts() :: [part()]
  def parts, do: Map.keys(@parts)

  @doc """
  The contents of the best-matching override file, or `nil` when there is none.

  `locale` may be `nil`, which skips straight to the locale-less candidate.
  """
  @spec read([Path.t()], String.t(), part(), String.t() | nil) :: String.t() | nil
  def read(roots, name, part, locale) do
    key = {__MODULE__, roots, name, part, locale}

    case :persistent_term.get(key, :miss) do
      :miss ->
        content = lookup(roots, name, part, locale)
        :persistent_term.put(key, content)
        content

      cached ->
        cached
    end
  end

  @doc """
  Drops cached override lookups.

  Only tests and dev reloads need this: a deploy starts a fresh VM.

  Pass a list of roots to clear only the entries that consulted them. That
  scoping is what lets an async test clear its own `tmp_dir` without erasing a
  concurrently-running one's cache — and it is the honest shape anyway, since a
  dev reload usually means one application's files changed, not all of them.
  """
  @spec reset_cache([Path.t()] | :all) :: :ok
  def reset_cache(roots \\ :all) do
    for {{__MODULE__, cached_roots, _name, _part, _locale} = key, _value} <-
          :persistent_term.get(),
        roots == :all or Enum.any?(cached_roots, &(&1 in roots)) do
      :persistent_term.erase(key)
    end

    :ok
  end

  defp lookup(roots, name, part, locale) when is_list(roots) do
    with true <- Map.has_key?(@parts, part),
         true <- Regex.match?(@name_pattern, to_string(name)) do
      roots
      |> Enum.flat_map(&candidates(&1, name, part, locale))
      |> Enum.find_value(&read_file/1)
    else
      false -> nil
    end
  end

  defp lookup(_roots, _name, _part, _locale), do: nil

  defp candidates(root, name, part, locale) do
    extension = Map.fetch!(@parts, part)

    locale
    |> locale_suffixes()
    |> Enum.map(fn
      nil -> Path.join([root, name, "#{part}.#{extension}"])
      suffix -> Path.join([root, name, "#{part}.#{suffix}.#{extension}"])
    end)
  end

  # "en-GB" is tried, then "en", then the locale-less file. An unparseable
  # locale contributes no candidates of its own rather than being interpolated
  # into a path.
  defp locale_suffixes(locale) when is_binary(locale) do
    if Regex.match?(@locale_pattern, locale) do
      case String.split(locale, "-") do
        [base] -> [base, nil]
        [base | _dialect] -> [locale, base, nil]
      end
    else
      [nil]
    end
  end

  defp locale_suffixes(_locale), do: [nil]

  defp read_file(path) do
    case File.read(path) do
      {:ok, content} -> content
      {:error, _reason} -> nil
    end
  end
end
