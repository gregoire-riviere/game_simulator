defmodule Poker.LocalProfileProvider do
  @behaviour Poker.ProfileProvider

  @impl true
  def generate(count), do: Poker.Profile.generate(count)
end
