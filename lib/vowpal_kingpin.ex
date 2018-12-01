defmodule VowpalKingpin do
  alias :mnesia, as: Mnesia
  require VowpalFleet

  @type features :: list(VowpalFleet.Types.namespace())

  def start(model_id, explore) do
    Mnesia.create_schema([{:model_id, node()}])
    Mnesia.start()
    Mnesia.create_table(VowpalKingpin, attributes: [:session_id, :state, :created_at])

    VowpalFleet.start_worker(model_id, node(), %{
      :autosave => 300_000,
      :args => [
        "--random_seed",
        "123",
        "--cb_explore",
        "#{explore}",
        "--cover",
        "3",
        "--num_children",
        "1"
      ]
    })
  end

  def fetch_session(sid) do
    s = Mnesia.dirty_read({VowpalKingpin, sid})

    if s == [] do
      %{}
    else
      {_, _, state, _} = Enum.at(s, 0)
      state
    end
  end

  def now() do
    :os.system_time(:millisecond)
  end

  def fetch_model_from_session(s, model_id, features) do
    # features => [{country_en...}], arms => {probability, true/false chosen not chosen},{probability, false}
    m = Map.get(s, model_id, %{:features => [], :arms => []})

    if features == [] do
      m
    else
      # what if the features changed? make new pull or use the previous one
      Map.merge(m, %{:features => features})
    end
  end

  def rand() do
    :rand.uniform()
  end

  def predict(sid, model_id, features) do
    s = fetch_session(sid)
    model = fetch_model_from_session(s, model_id, features)
    pred = VowpalFleet.predict(model_id, features)

    arms =
      pred
      |> Enum.map(fn prob ->
        # FIXME
        if rand() > 0.5 do
          {prob, true}
        else
          {prob, false}
        end
      end)

    model = Map.merge(model, %{:arms => arms})
    s = Map.merge(s, %{model_id => model})
    Mnesia.dirty_write({VowpalKingpin, sid, s, now()})
    s
  end

  def track(sid, model_id) do
    track(sid, model_id, 0, 1)
  end

  def track(sid, model_id, cost_chosen, cost_not_chosen) do
    s = fetch_session(sid)
    model = fetch_model_from_session(s, model_id, [])

    actions_to_train =
      Map.get(model, :arms, [])
      |> Stream.with_index()
      |> Enum.map(fn {{prob, chosen}, idx} ->
        cost =
          case chosen do
            true ->
              cost_chosen

            false ->
              cost_not_chosen
          end

        {idx + 1, cost, prob}
      end)

    if actions_to_train != [] do
      VowpalFleet.train(model_id, actions_to_train, Map.get(model, :features))
    end
  end
end
