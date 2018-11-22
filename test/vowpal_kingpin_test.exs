defmodule VowpalKingpinTest do
  use ExUnit.Case
  doctest VowpalKingpin

  test "greets the world" do
    IO.inspect(Session.new())
    s = Session.new()

    r = Session.new_round([{:namespace, [1, 2, 3]}])

    IO.inspect(r)

    r = Session.add_pull_to_round(r, {5, 3, 0, [{:namespace, [4, 6]}]})
    r = Session.add_pull_to_round(r, {6, 3, 0, [{:namespace, [4, 6]}]})

    s = Session.add_round_to_session(s, :model, r)
    IO.inspect(s)
    IO.inspect(Session.expiring(s))
  end
end
