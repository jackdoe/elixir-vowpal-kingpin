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
    Mnesia.dirty_delete({VowpalKingpin, get_session_key(sid, model_id)})
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

  def choose(actions, n) do
    choose(actions, n, [])
  end

  def choose(actions, n, chosen) do
    # expects sorted list of actions, sorded by descending probability 
    if length(chosen) == n || length(actions) == 0 do
      chosen
    else
      r = rand()
      c = Enum.find(actions, Enum.at(actions, 0), fn {_, prob} -> prob >= r end)
      chosen = chosen ++ [c]

      actions =
        actions
        |> Enum.filter(fn x -> x != c end)

      choose(actions, n, chosen)
    end
  end

  def predict(sid, model_id, n, features) do
    s = fetch_session(sid, model_id, features)
    pred = VowpalFleet.predict(model_id, features)

    actions =
      pred
      |> Stream.with_index()
      |> Enum.sort(fn {_, pa}, {_, pb} -> pa >= pb end)
      |> Enum.map(fn {prob, idx} ->
        {idx + 1, prob}
      end)

    chosen =
      choose(actions, n)
      |> Enum.take(n)
      |> Enum.map(fn {action_id, prob} -> {action_id, prob} end)
      |> Map.new()

    actions =
      actions
      |> Enum.map(fn {action_id, prob} ->
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

  # XXX: what if user clicks to second item after coming back?
  # is that new pull or same as before
  # this does not hanle that very well
  def track(sid, model_id, clicked_action_id, cost_not_clicked) do
    s = fetch_session(sid, model_id, [])
    track_session(s, clicked_action_id, cost_not_clicked)
    delete_session(sid, model_id)
  end

  # lets say we have click/convertion on one of the actions
  # only send to vowpal actions that were possible
  defp track_session(s, clicked_action_id, cost_not_clicked) do
    # only send *possible* actions to vw
    actions_to_train =
      Map.get(s, :actions, [])
      |> Enum.filter(fn {_, _, chosen} -> chosen end)
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
      VowpalFleet.train(Map.get(s, :model), actions_to_train, Map.get(s, :features))
    end
  end

  # expire all sessions with epoch before specified one, and attribute cost to all chosen (non clicked) actions
  def timeout(epoch, cost_not_clicked) do
    expired =
      Mnesia.select(VowpalKingpin, [
        {{VowpalKingpin, :"$1", :"$2", :"$3"}, [{:<, :"$3", epoch}], [:"$$"]}
      ])

    Mnesia.transaction(fn ->
      expired
      |> Enum.each(fn {key, s, _} ->
        track_session(s, -1, cost_not_clicked)
        Mnesia.delete({VowpalKingpin, key})
      end)
    end)
  end
end
