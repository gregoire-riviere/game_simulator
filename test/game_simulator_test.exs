defmodule GameSimulatorTest do
  use ExUnit.Case
  doctest GameSimulator

  test "greets the world" do
    assert GameSimulator.hello() == :world
  end
end
