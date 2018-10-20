defmodule ChordNode do
    use GenServer

    def init(%{m: m} = state) do
        n = 160 - m
        << chordId :: size(m), _ :: size(n) >> = :crypto.hash(:sha, inspect(self()))
        state = Map.put(state, :myId, chordId)
        {:ok, state}
    end
    
    def handle_call( :get_successor, _, %{succ: succ} = state ) do
        {:reply, succ, state}
    end
    def handle_call( :get_predecessor, _, %{pred: pred} = state ) do
        {:reply, pred, state}
    end

    def handle_call( {:find_successor, id}, _, %{succ: succ, finger_table: finger_table, myId: myId} = state ) do
        requestedNode = find_successor(id, succ, finger_table, myId)
        {:reply, requestedNode, state}
    end

    def find_successor(id, succ, finger_table, myId) do
        succId = succ |> elem(0)
        requestedNode = 
        if( (id > myId && id < succId) || (myId > succId && (id > myId || id < succId)) ) do
            succ
        else
            closest_preceding_node(id, finger_table, myId) |> elem(1) |> GenServer.call({:find_successor, id})
        end
        requestedNode
    end

    def handle_cast( {:add_successor, successor}, state ) do
        state = Map.put(state, :succ, successor)
        {:noreply, state}
    end
    def handle_cast( {:add_predecessor, predecessor}, state ) do
        state = Map.put(state, :pred, predecessor)
        {:noreply, state}
    end

    def handle_cast( {:add_finger_tables, finger_table}, state ) do
        state = Map.put(state, :finger_table, finger_table)
        {:noreply, state}
    end

    def handle_cast( {:add_file, file}, %{m: m} = state ) do
        n = 160 - m
        << fileId :: size(m), _ :: size(n) >> = :crypto.hash(:sha, file)
        IO.inspect(fileId)
        self() |> GenServer.cast( {:add_hashed_file, {fileId, file}} )
        {:noreply, state}
    end

    def handle_cast( {:add_hashed_file, {fileId, file}}, %{succ: succ, finger_table: finger_table, myId: myId} = state ) do
        
        next = Enum.reduce(finger_table, {-1}, fn(x, acc) -> 
            if elem(acc,0) < elem(x,0) && elem(x,0) <= fileId, do: x, else: acc
        end)

        if(myId < fileId && ( elem(succ, 0) >= fileId || (elem(succ, 0) < fileId && myId > elem(succ, 0))) ) do
            succ |> elem(1) |> GenServer.cast( {:put_file, {fileId, file}} )
        else 
            if(next=={-1}) do
                succ |> elem(1) |> GenServer.cast( {:add_hashed_file, {fileId, file}} )
            else
                next |> elem(1) |> GenServer.cast( {:add_hashed_file, {fileId, file}} )
            end
        end
        {:noreply, state}
    end

    def handle_cast({:put_file, file}, %{files: files} = state) do
        state = Map.put(state, :files, [file|files])
        {:noreply, state}
    end

    def handle_cast( {:search_file, file}, %{m: m} = state) do
        n = 160 - m
        << fileId :: size(m), _ :: size(n) >> = :crypto.hash(:sha, file)
        self() |> GenServer.cast( {:search_hashed_file, {fileId, file}} )
        {:noreply, state}
    end

    def handle_cast( {:search_hashed_file, {fileId, file}}, %{succ: succ, finger_table: finger_table, files: files} = state ) do
        
        if Enum.member?(files, {fileId, file}) do
            IO.puts("Found  the sucka")
        else
            next = Enum.reduce(finger_table, {-1}, fn(x, acc) -> 
                if elem(acc,0) < elem(x,0) && elem(x,0) <= fileId, do: x, else: acc
            end)
    
            if(next=={-1}) do
                succ |> elem(1) |> GenServer.cast( {:search_hashed_file, {fileId, file}} )
            else
                next |> elem(1) |> GenServer.cast( {:search_hashed_file, {fileId, file}} )
            end
        end
        {:noreply, state}
    end

    # Stabalization Loop functions
    def  handle_cast( {:notify, {nodeId, node}}, %{pred: pred, myId: myId} = state) do
        state = 
        if(pred == nil) do
            Map.put(state, :pred, {nodeId, node})
        else
            predId = pred |> elem(1)
            if( (nodeId < myId && predId < nodeId) || (myId < predId && (nodeId>predId || nodeId<myId)) ) do
                Map.put(state, :pred, {nodeId, node})
            else
                state
            end
        end

        {:noreply, state}
    end

    def handle_info( {:fix_fingers, next}, %{succ: succ, finger_table: finger_table, myId: myId, m: m} = state) do
        next = next + 1
        next = if (next>m-1), do: 0, else: next
        List.replace_at( finger_table, next, find_successor(myId + :math.pow(2, next), succ, finger_table, myId) )

        schedule_work({:fix_fingers, next})

        {:noreply, state}
    end
    
    def handle_info( {:stabilize}, %{succ: succ, myId: myId} = state) do
        IO.puts("Started!")
        IO.inspect(self())
        pred = succ |> elem(1) |> GenServer.call(:get_predecessor)
        predId = pred |> elem(0)
        succId = succ |> elem(0)
        state = 
        if( (predId > myId && predId < succId) || (myId > succId && (predId > myId || predId < succId)) ) do
            Map.put(state, :succ, pred)
        else
            state
        end
        succ = state.succ
        succ |> elem(1) |> GenServer.cast( {:notify, {myId, self()}} )
        IO.puts("All Done!")
        schedule_work({:stabilize})
        {:noreply, state}
    end

    def handle_info( {:check_predecessor}, %{pred: pred} = state) do
        state = 
            if pred |> elem(1) |> Process.alive? do
                state
            else
                Map.put(state, :pred, nil)
            end
        {:noreply, state}
    end

    defp schedule_work(msg) do
        Process.send_after(self(), msg, 2000)
    end

    defp closest_preceding_node(id, finger_table, myId) do
        preceding_node = Enum.reduce( Enum.reverse(finger_table), nil, fn(x, acc) -> 
            xid = x |> elem(0)
            acc = 
                if(acc == nil) do
                    if( (myId < xid && xid < id) || (myId > id && (xid > myId || xid < id)) ) do
                        x
                    end
                else
                    acc
                end
            acc
        end)

        preceding_node = if (preceding_node==nil), do: {myId, self()}, else: preceding_node
        preceding_node
    end
end