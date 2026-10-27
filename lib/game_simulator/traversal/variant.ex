defmodule GameSimulator.Traversal.Variant do
  @moduledoc "Server-generated forest layout, independent of the approved relief generator."

  def valid?(variant, seed) do
    is_binary(variant) and valid_flags?(variant) and
      (seed == nil or (is_binary(seed) and byte_size(seed) <= 320 and String.length(seed) <= 80)) and
      (not String.contains?(variant, "forests") or (is_binary(seed) and seed != ""))
  end

  def valid_flags?(variant) do
    flags = String.split(variant, "+")
    (flags == ["classic"] or (flags != [] and Enum.uniq(flags) == flags and Enum.all?(flags, &(&1 in ["extended", "forests", "bridge"]))))
  end

  def forests(variant, seed), do: forests(variant, seed, 10)
  def forests(variant, seed, size) do
    flags = String.split(variant, "+")
    if "forests" in flags, do: forest_layout(seed, size, "bridge" in flags), else: []
  end

  def forest_layout(seed, size, bridge \\ false) do
    opposite = size - 2
    anchors = for r <- 1..div(size - 1, 2), c <- 1..(size - 3),
      {r, c} < {opposite - r, opposite - c},
      abs(r - (opposite - r)) >= 2 or abs(c - (opposite - c)) >= 2,
      not bridge or (div(size, 2) not in r..(r + 1) and div(size, 2) not in (opposite - r)..(opposite - r + 1)),
      do: {r, c}
    index = rem(:binary.decode_unsigned(:crypto.hash(:sha256, seed)), length(anchors))
    {row, col} = Enum.at(anchors, index)
    for {r, c} <- [{row, col}, {opposite - row, opposite - col}], dr <- 0..1, dc <- 0..1,
      do: %{row: r + dr, col: c + dc}
  end
end
