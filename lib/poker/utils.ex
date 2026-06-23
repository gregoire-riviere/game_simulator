defmodule Poker.Utils do
  def unique_id do
    timestamp = System.system_time(:millisecond)
    sequence = System.unique_integer([:positive, :monotonic])
    random = :crypto.strong_rand_bytes(32)

    # The hash makes timestamp, sequence and entropy safe to expose as a compact id.
    :sha256
    |> :crypto.hash([Integer.to_string(timestamp), Integer.to_string(sequence), random])
    |> Base.encode16(case: :lower)
    |> binary_part(0, 24)
  end
end
