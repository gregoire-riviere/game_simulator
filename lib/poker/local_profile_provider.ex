defmodule Poker.LocalProfileProvider do
  @moduledoc """
  Fournisseur V1 sans réseau ni coût API.
  """

  @behaviour Poker.ProfileProvider

  @impl true
  def generate(count), do: Poker.Profile.generate(count)
end
