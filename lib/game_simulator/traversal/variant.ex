defmodule GameSimulator.Traversal.Variant do
  @moduledoc "Server-generated forest layout, independent of the approved relief generator."

  def valid?(variant, seed) do
    variant in ["classic", "forests"] and
      (seed == nil or (is_binary(seed) and byte_size(seed) <= 320 and String.length(seed) <= 80)) and
      (variant == "classic" or (is_binary(seed) and seed != ""))
  end

  def forests("classic", _seed), do: []
  def forests("forests", seed) do
    # Interior anchors avoid both starting rows and exit edges. Rotation maps a
    # 2x2 anchor (r,c) to (8-r,8-c); keep only disjoint pairs, once each.
    anchors = for r <- 1..4, c <- 1..7,
      {r, c} < {8 - r, 8 - c},
      abs(r - (8 - r)) >= 2 or abs(c - (8 - c)) >= 2,
      do: {r, c}
    index = rem(:binary.decode_unsigned(:crypto.hash(:sha256, seed)), length(anchors))
    {row, col} = Enum.at(anchors, index)
    for {r, c} <- [{row, col}, {8 - row, 8 - col}], dr <- 0..1, dc <- 0..1,
      do: %{row: r + dr, col: c + dc}
  end
end
