defmodule Poker.UtilsTest do
  use ExUnit.Case, async: true

  test "generates distinct 24-character hash identifiers" do
    first = Poker.Utils.unique_id()
    second = Poker.Utils.unique_id()

    assert is_binary(first) and byte_size(first) == 24
    assert first =~ ~r/^[0-9a-f]{24}$/
    assert first != second
  end
end
