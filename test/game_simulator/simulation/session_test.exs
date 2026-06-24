defmodule GameSimulator.Simulation.SessionTest do
  use ExUnit.Case, async: true

  alias GameSimulator.Simulation.{Bot, PlayerMemory, PlayerProfile, Session, TableSpec}

  test "builds simple decoupled simulation structs" do
    profile = %PlayerProfile{vpip: 0.32, call_too_wide: 0.2}
    memory = %PlayerMemory{current_tilt: 0.4, lost_buyins: 1}
    bot = %Bot{id: :alice, name: "Alice", stack: 120, profile: profile, memory: memory}
    table = %TableSpec{name: "6-max", starting_stack: 100}
    session = %Session{id: "session-1", table: table, bots: [bot]}

    assert session.table.big_blind == 1
    assert hd(session.bots).stack == 120
    assert hd(session.bots).profile.call_too_wide == 0.2
    assert hd(session.bots).memory.lost_buyins == 1
  end
end
