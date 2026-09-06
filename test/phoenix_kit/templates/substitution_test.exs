defmodule PhoenixKit.Templates.SubstitutionTest do
  use ExUnit.Case, async: true

  alias PhoenixKit.Templates.Substitution

  doctest PhoenixKit.Templates.Substitution

  describe "variables/1" do
    test "collects each placeholder once, in order of first appearance" do
      assert Substitution.variables("{{b}} {{a}} {{ b }}") == ["b", "a"]
    end

    test "ignores text that only looks like a placeholder" do
      for content <- ["{{ }}", "{{1abc}}", "{{a-b}}", "{single}", "{{unclosed"] do
        assert Substitution.variables(content) == [], "expected no match in #{inspect(content)}"
      end
    end

    test "handles absent content" do
      assert Substitution.variables(nil) == []
    end
  end

  describe "substitute/2" do
    test "accepts atom and string keys alike" do
      # Callers write %{user_email: …}; content exported from the old database
      # templates carries "user_email" keys. Both have to work.
      assert Substitution.substitute("{{a}}/{{b}}", %{"b" => 2, a: 1}) == "1/2"
    end

    test "tolerates whitespace inside the braces" do
      assert Substitution.substitute("{{ name }}", %{name: "Ada"}) == "Ada"
    end

    test "stringifies non-binary values" do
      assert Substitution.substitute("{{n}} {{ok}}", %{n: 42, ok: true}) == "42 true"
    end

    test "leaves an unbound placeholder visible rather than blanking it" do
      # A silent empty string reads as finished copy and ships; a visible
      # {{user_emial}} announces the typo in a preview or a test.
      assert Substitution.substitute("Hi {{user_emial}}", %{user_email: "a@b.c"}) ==
               "Hi {{user_emial}}"
    end

    test "substitutes every occurrence of a repeated placeholder" do
      assert Substitution.substitute("{{a}}-{{a}}", %{a: "x"}) == "x-x"
    end

    test "passes absent content through" do
      assert Substitution.substitute(nil, %{a: 1}) == nil
    end

    test "does not re-scan a substituted value for placeholders" do
      # Otherwise a value carrying braces could inject a second round.
      assert Substitution.substitute("{{a}}", %{a: "{{b}}", b: "boom"}) == "{{b}}"
    end
  end

  describe "missing/2" do
    test "names only the unbound placeholders" do
      assert Substitution.missing("{{a}} {{b}} {{c}}", %{a: 1, c: 3}) == ["b"]
    end

    test "is empty when the render would be fully bound" do
      assert Substitution.missing("{{a}}", %{a: 1}) == []
      assert Substitution.missing("no placeholders", %{}) == []
      assert Substitution.missing(nil, %{}) == []
    end
  end
end
