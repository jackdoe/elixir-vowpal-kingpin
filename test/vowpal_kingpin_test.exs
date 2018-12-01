defmodule VowpalKingpinTest do
  use ExUnit.Case
  doctest VowpalKingpin

  test "greets the world" do
    VowpalKingpin.start(:bandit, 3)
    IO.inspect(VowpalKingpin.predict(:session_id_5, :bandit, [{"ns", [1, 2, 3]}]))
    IO.inspect(VowpalKingpin.track(:session_id_5, :bandit))
  end
end
