defmodule MrWhite.WordsTest do
  use ExUnit.Case, async: true

  test "contains a large and valid local library" do
    pairs = MrWhite.Words.all()

    assert length(pairs) >= 300
    assert {"seau", "bassin"} in pairs
    assert {"train", "bus"} in pairs
    assert {"lampe", "bougie"} in pairs
    assert Enum.all?(pairs, fn {civil, spy} -> civil != "" and spy != "" and civil != spy end)
  end
end
