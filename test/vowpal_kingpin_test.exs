defmodule VowpalKingpinTest do
  use ExUnit.Case
  doctest VowpalKingpin

  test "greets the world" do
    VowpalKingpin.start(:bandit, 3)

    for _ <- 0..10 do
      IO.inspect(
        VowpalKingpin.predict(:session_id_5, :bandit, 2, [{"ctx", [1, 2, 3]}], [
          {5, [{"ns", [1, 2, 3]}]},
          {6, [{"ns", [1, 2, 3]}]},
          {7, [{"ns", [1, 2, 3]}]}
        ])
      )

      IO.inspect(VowpalKingpin.timeout(9_543_739_670))
      IO.inspect(VowpalKingpin.track(:session_id_5, :bandit, [6]))
    end
  end
end
