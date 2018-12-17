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

  def start(model_id, bootstrap, mnesia_nodes \\ [node()]) do
    # Application.ensure_all_started(:logger)
    # Application.ensure_all_started(:vowpal_fleet)
    start_mnesia(mnesia_nodes)

    VowpalFleet.start_worker(model_id, node(), %{
      :autosave => 300_000,
      :args => [
        "--random_seed",
        "123",
        "-b",
        "21",
        "--bootstrap",
        "#{bootstrap}",
        "-q",
        "ci",
        "--loss_function",
        "logistic",
        "--link",
        "logistic",
        "--ftrl",
        "--save_resume"
      ]
    })
  end

  def get_session_key(sid, model_id) do
    "#{sid}_#{model_id}"
  end

  def delete_session(sid, model_id) do
    Mnesia.dirty_delete({VowpalKingpin, get_session_key(sid, model_id)})
  end

  def fetch_session(sid, model_id, context, items) do
    s = Mnesia.dirty_read({VowpalKingpin, get_session_key(sid, model_id)})

    if s == [] do
      %{:context => context, :items => items, :model => model_id, :now => now()}
    else
      {_, _, state, _} = Enum.at(s, 0)
      state
    end
  end

  def now() do
    :os.system_time(:millisecond)
  end

  defp prefix_features(p, namespaces) do
    namespaces
    |> Enum.map(fn {name, features} ->
      f =
        features
        |> Enum.map(fn e ->
          case e do
            {name, value} ->
              {"#{p}_#{name}", value}

            name ->
              "#{p}_#{name}"
          end
        end)

      {name, f}
    end)
  end

  def predict(sid, model_id, limit, context, items) do
    s = fetch_session(sid, model_id, context, items)
    c = prefix_features("c", context)

    out =
      items
      |> Enum.map(fn %{id: id, features: features} ->
        score = VowpalFleet.predict(model_id, merge_features(c, {id, features}))
        {id, score}
      end)
      |> Enum.sort(fn {_, pa}, {_, pb} -> pa >= pb end)
      |> Enum.take(limit)

    Mnesia.dirty_write({VowpalKingpin, get_session_key(sid, model_id), s, now()})

    out
  end

  def merge_features(ctx, {id, features}) do
    ctx ++ prefix_features("i", [{"id", [id]}] ++ features)
  end

  def track(sid, model_id, clicked_actions) do
    s = Mnesia.dirty_read({VowpalKingpin, get_session_key(sid, model_id)})

    case s do
      {_, _, state, _} ->
        track_session(state, clicked_actions)
        delete_session(sid, model_id)

      [{_, _, state, _}] ->
        track_session(state, clicked_actions)
        delete_session(sid, model_id)

      [] ->
        nil
        # missing session, ignore
    end
  end

  defp track_session(%{:context => context, :items => items, :model => model_id}, clicked_actions) do
    clicked =
      if is_list(clicked_actions) do
        clicked_actions |> Enum.map(fn e -> {e, true} end) |> Map.new()
      else
        clicked_actions
      end

    c = prefix_features("c", context)

    v =
      items
      |> Enum.map(fn %{id: id, features: features} ->
        merged = merge_features(c, {id, features})

        if Map.has_key?(clicked, id) do
          VowpalFleet.train(model_id, 1, merged)
        else
          VowpalFleet.train(model_id, -1, merged)
        end
      end)
  end

  # expire all sessions with epoch before specified one, and attribute cost to all chosen (non clicked) actions
  def timeout(epoch) do
    Mnesia.transaction(fn ->
      expired =
        Mnesia.select(VowpalKingpin, [
          {{VowpalKingpin, :"$1", :"$2", :"$3"}, [{:<, :"$3", epoch}], [:"$$"]}
        ])

      expired
      |> Enum.each(fn {key, s, _} ->
        track_session(s, [])
        Mnesia.delete({VowpalKingpin, key})
      end)
    end)
  end
end
