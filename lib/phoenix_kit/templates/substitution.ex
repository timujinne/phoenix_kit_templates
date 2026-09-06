defmodule PhoenixKit.Templates.Substitution do
  @moduledoc """
  `{{variable}}` substitution.

  The syntax matches what the database-backed email templates used, so content
  exported from those rows carries over unchanged. Surrounding whitespace is
  allowed: `{{user_email}}` and `{{ user_email }}` are the same placeholder.

  ## Unbound placeholders are left alone

  A placeholder with no matching variable is emitted **verbatim**, not blanked.
  Both are wrong, but a visible `{{user_emial}}` announces the typo in a preview
  or a test, while a silent empty string reads as finished copy and ships. The
  renderer never raises over one — a message with a flawed placeholder must
  still send — so callers that want it to be an error ask `missing/2` up front.
  """

  @placeholder ~r/\{\{\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*\}\}/

  @typedoc "Variables to interpolate. Keys may be atoms or strings."
  @type variables :: %{optional(atom() | String.t()) => term()}

  @doc """
  The placeholder names appearing in `content`, in order, without duplicates.

      iex> PhoenixKit.Templates.Substitution.variables("Hi {{name}}, {{ name }} again")
      ["name"]
  """
  @spec variables(String.t() | nil) :: [String.t()]
  def variables(content) when is_binary(content) do
    @placeholder
    |> Regex.scan(content, capture: :all_but_first)
    |> List.flatten()
    |> Enum.uniq()
  end

  def variables(_content), do: []

  @doc """
  Replaces every bound placeholder in `content`.

      iex> PhoenixKit.Templates.Substitution.substitute("Hi {{name}}", %{name: "Ada"})
      "Hi Ada"

      iex> PhoenixKit.Templates.Substitution.substitute("Hi {{name}}", %{})
      "Hi {{name}}"
  """
  @spec substitute(String.t() | nil, variables()) :: String.t() | nil
  def substitute(nil, _variables), do: nil

  def substitute(content, variables) when is_binary(content) do
    bound = normalize(variables)

    Regex.replace(@placeholder, content, fn placeholder, name ->
      case Map.fetch(bound, name) do
        {:ok, value} -> to_string(value)
        :error -> placeholder
      end
    end)
  end

  @doc """
  Placeholder names in `content` that `variables` does not bind.

  Empty means every placeholder will be filled.

      iex> PhoenixKit.Templates.Substitution.missing("{{a}} {{b}}", %{a: 1})
      ["b"]
  """
  @spec missing(String.t() | nil, variables()) :: [String.t()]
  def missing(content, variables) do
    bound = normalize(variables)
    content |> variables() |> Enum.reject(&Map.has_key?(bound, &1))
  end

  # Atom and string keys are both accepted so a caller can write %{user_email: …}
  # while content exported from the old templates keeps its "user_email" keys.
  defp normalize(variables) when is_map(variables) do
    Map.new(variables, fn {key, value} -> {to_string(key), value} end)
  end

  defp normalize(_variables), do: %{}
end
