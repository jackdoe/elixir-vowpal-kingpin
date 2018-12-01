defmodule VowpalKingpin do
  alias :mnesia, as: Mnesia
  require VowpalFleet
  require Logger
  @type features :: list(VowpalFleet.Types.namespace())

  def start_mnesia(nodes) do
    # FIXME: use config
    Logger.debug("creating mnesia schema")
    Mnesia.create_schema(nodes)
    Mnesia.start()
    Mnesia.create_table(VowpalKingpin, attributes: [:session_id, :state, :created_at])
  end

  def start(model_id, explore, mnesia_nodes \\ [node()]) do
    start_mnesia(mnesia_nodes)

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
    # features => [{country_en...}], actions => {probability, true/false chosen not chosen},{probability, false}
    m = Map.get(s, model_id, %{:features => [], :actions => []})

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

  def choose_many(actions) do
    base = 1 / length(actions)

    actions
    |> Enum.map(fn {action_id, prob} ->
      if rand() < prob do
        {action_id, prob + base, true}
      else
        {action_id, prob + base, false}
      end
    end)
  end

  def choose(actions) do
    choose(actions, 1)
  end

  def choose(actions, attempts) do
    actions = choose_many(actions)
    only_chosen = actions |> Enum.filter(fn {_, _, is_chosen} -> is_chosen end)

    if length(only_chosen) == 0 do
      Logger.debug("couldnt choose any action from #{actions}, attempt #{attempts}")
      choose(actions, attempts + 1)
    else
      {chosen_action_id, chosen_prob, _} = Enum.at(only_chosen, 0)
      {chosen_action_id, chosen_prob}
    end
  end

  def predict(sid, model_id, features) do
    s = fetch_session(sid)
    model = fetch_model_from_session(s, model_id, features)
    pred = VowpalFleet.predict(model_id, features)

    actions =
      pred
      |> Stream.with_index()
      |> Enum.shuffle()
      |> Enum.map(fn {prob, idx} ->
        {idx + 1, prob}
      end)

    {chosen_action_id, chosen_prob} = choose(actions)

    actions =
      actions
      |> Enum.map(fn {action_id, prob} ->
        if action_id == chosen_action_id do
          {action_id, chosen_prob, true}
        else
          {action_id, prob, false}
        end
      end)

    model = Map.merge(model, %{:actions => actions})
    s = Map.merge(s, %{model_id => model})
    Mnesia.dirty_write({VowpalKingpin, sid, s, now()})

    {chosen_action_id, actions}
  end

  def track(sid, model_id) do
    track(sid, model_id, 0, 1)
  end

  def track(sid, model_id, cost_chosen, cost_not_chosen) do
    s = fetch_session(sid)
    model = fetch_model_from_session(s, model_id, [])

    # FIXME prob is actual prob = 1/n_actions
    actions_to_train =
      Map.get(model, :actions, [])
      |> Enum.map(fn {action_id, prob, chosen} ->
        cost =
          case chosen do
            true ->
              cost_chosen

            false ->
              cost_not_chosen
          end

        {action_id, cost, prob}
      end)

    if actions_to_train != [] do
      VowpalFleet.train(model_id, actions_to_train, Map.get(model, :features))
    end
  end
end
