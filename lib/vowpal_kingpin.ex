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
    Mnesia.add_table_index(VowpalKingpin, :created_at)
  end

  def start(model_id, explore, mnesia_nodes \\ [node()]) do
    # Application.ensure_all_started(:logger)
    # Application.ensure_all_started(:vowpal_fleet)

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

  def get_session_key(sid, model_id) do
    "#{sid}_#{model_id}"
  end

  def delete_session(sid, model_id) do
    s = Mnesia.dirty_read({VowpalKingpin, get_session_key(sid, model_id)})
  end

  def fetch_session(sid, model_id, features) do
    s = Mnesia.dirty_read({VowpalKingpin, get_session_key(sid, model_id)})

    if s == [] do
      %{:features => features, :actions => [], :model => model_id, :now => now()}
    else
      {_, _, state, _} = Enum.at(s, 0)

      if features == [] do
        Map.merge(state, %{:features => features})
      else
        state
      end
    end
  end

  def now() do
    :os.system_time(:millisecond)
  end

  def rand() do
    :rand.uniform()
  end

  def choose_many(actions) do
    base = 1 / length(actions)

    actions
    |> Enum.map(fn {action_id, prob, _} ->
      if rand() < prob do
        {action_id, min(prob + base, 1), true}
      else
        {action_id, min(prob + base, 1), false}
      end
    end)
  end

  def choose(actions, n) do
    choose(actions, length(actions), n, [])
  end

  def choose(actions, total, n, chosen) do
    if n <= 0 do
      chosen
    else
      only_non_chosen = actions |> Enum.filter(fn {_, _, is_chosen} -> !is_chosen end)
      possible = choose_many(only_non_chosen)
      choose(only_non_chosen, total, n - length(possible), chosen ++ possible)
    end
  end

  def predict(sid, model_id, n, features) do
    s = fetch_session(sid, model_id, features)
    pred = VowpalFleet.predict(model_id, features)

    actions =
      pred
      |> Stream.with_index()
      |> Enum.shuffle()
      |> Enum.map(fn {prob, idx} ->
        {idx + 1, prob, false}
      end)

    chosen =
      choose(actions, n)
      |> Enum.take(n)
      |> Enum.map(fn {action_id, prob, _} -> {action_id, prob} end)
      |> Map.new()

    actions =
      actions
      |> Enum.map(fn {action_id, prob, _} ->
        chosen_prob = Map.get(chosen, action_id, 0)

        if chosen_prob > 0 do
          {action_id, chosen_prob, true}
        else
          {action_id, prob, false}
        end
      end)

    s = Map.merge(s, %{:actions => actions})
    Mnesia.dirty_write({VowpalKingpin, get_session_key(sid, model_id), s, now()})

    {chosen, s}
  end

  def track(sid, model_id, clicked_action_id) do
    track(sid, model_id, clicked_action_id, 100)
  end

  # lets say we have click/convertion on one of the actions
  def track(sid, model_id, clicked_action_id, cost_not_clicked) do
    s = fetch_session(sid, model_id, [])

    actions_to_train =
      Map.get(s, :actions, [])
      |> Enum.map(fn {action_id, prob, chosen} ->
        cost =
          case chosen do
            true ->
              if action_id == clicked_action_id do
                0
              else
                cost_not_clicked
              end

            false ->
              0
          end

        {action_id, cost, prob}
      end)

    if actions_to_train != [] do
      VowpalFleet.train(model_id, actions_to_train, Map.get(s, :features))
      delete_session(sid, model_id)
    end
  end

  # expire all sessions with epoch before specified one, and attribute cost to all chosen (non clicked) actions
  def timeout(epoch) do
    Mnesia.transaction(fn ->
      IO.inspect(
        Mnesia.select(VowpalKingpin, [
          {{Session, :"$1", :"$2", :"$3"}, [{:>, :"$3", epoch}], [:"$$"]}
        ])
      )
    end)
  end
end
