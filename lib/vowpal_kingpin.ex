defmodule Session do
  # XXX: this seems weird, not sure if i should just define structs or keep it like that
  # but couldnt find how to properly type structs

  @type features() :: list(VowpalFleet.Type.namespace())
  @type probability :: float()
  @type expire_stamp :: integer() | float()
  @type position :: integer()
  @type cost :: integer()
  @type arm_id :: any() | integer()
  @type pull :: {arm_id(), probability(), position(), features()}
  @type round :: {list(pull()), expire_stamp(), cost(), features()}
  @type session :: {String.t(), %{atom() => round()}}

  def generate_id do
    # FIXME: use timeuuid so it fits nicely in cassandra
    random_number = :rand.uniform()
    "#{random_number}"
  end

  def new() do
    {generate_id(), %{}}
  end

  @spec new_round(Session.features()) :: Session.round()
  def new_round(common_features) do
    new_round(:os.system_time(:millisecond) / 1000 + 60, common_features)
  end

  @spec new_round(Session.expire_stamp(), Session.features()) :: Session.round()
  def new_round(expire_stamp, common_features) do
    {[], expire_stamp, 0, common_features}
  end

  @spec add_pull_to_round(Session.round(), Session.pull()) :: Session.round()
  def add_pull_to_round(r, pull) do
    {pulls, expire_at, cost, features} = r
    {pulls ++ [pull], expire_at, cost, features}
  end

  @spec add_round_to_session(Session.session(), atom(), Session.round()) :: Session.session()
  def add_round_to_session(session, model_id, round) do
    {id, rounds} = session
    updated = Map.put(rounds, model_id, round)
    {id, updated}
  end

  @spec expiring(Session.session(), integer()) :: list(Session.round())
  def expiring(session, delta \\ 0) do
    {id, rounds} = session
    now = :os.system_time(:millisecond) / 1000 - delta

    updated =
      rounds
      |> Enum.filter(fn {_, {_, expiring, _, _}} ->
        expiring < now
      end)

    updated
  end

  @spec expire(Session.session(), integer()) :: Session.session()
  def expire(session, delta \\ 0) do
    {id, rounds} = session
    now = :os.system_time(:millisecond) / 1000 - delta

    updated =
      rounds
      |> Enum.filter(fn {_, {_, expiring, _, _}} ->
        expiring >= now
      end)
      |> Map.new()

    {id, updated}
  end
end

defmodule VowpalKingpin do
  def session do
    :world
  end
end
