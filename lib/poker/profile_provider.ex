defmodule Poker.ProfileProvider do
  @moduledoc """
  Contrat de génération de profils.

  La V1 utilise un générateur local ; une implémentation LLM pourra être branchée
  plus tard sans modifier la table ni la logique de jeu.
  """

  @callback generate(pos_integer()) :: [map()]
end
