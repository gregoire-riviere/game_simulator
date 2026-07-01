defmodule Poker.ProfileTest do
  use ExUnit.Case, async: true

  test "generates complete NL2 profiles with neutral memory" do
    profiles = Poker.Profile.generate(5)

    assert length(profiles) == 5

    Enum.each(profiles, fn profile ->
      assert profile.archetype in [:calling_station, :limp_caller, :fit_or_fold, :nit_weak, :tag, :lag, :spewy_aggro]
      assert profile.vpip in 10..70
      assert profile.pfr in 2..50
      assert profile.pfr <= profile.vpip
      assert profile.three_bet in 0..22
      assert profile.aggression >= 0.0 and profile.aggression <= 1.0
      assert profile.fold_to_cbet >= 0.0 and profile.fold_to_cbet <= 1.0
      assert profile.showdown_curiosity >= 0.0 and profile.showdown_curiosity <= 1.0
      assert profile.memory.current_tilt == 0.0
    end)
  end

  test "generates distinct names for a standard table" do
    names = Poker.Profile.generate(5) |> Enum.map(& &1.name)

    assert length(Enum.uniq(names)) == 5
  end
end
