defmodule Poker.ProfileProvider do
  @callback generate(pos_integer()) :: [map()]
end
