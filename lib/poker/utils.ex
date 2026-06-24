defmodule Poker.Utils do
  @moduledoc """
  Petits utilitaires sans logique de règles poker.
  """

  def unique_id do
    timestamp = System.system_time(:millisecond)
    sequence = System.unique_integer([:positive, :monotonic])
    random = :crypto.strong_rand_bytes(32)

    # Le hash masque les composants internes tout en gardant un identifiant compact à exposer.
    :sha256
    |> :crypto.hash([Integer.to_string(timestamp), Integer.to_string(sequence), random])
    |> Base.encode16(case: :lower)
    |> binary_part(0, 24)
  end
end
