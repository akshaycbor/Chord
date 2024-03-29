defmodule ChordNode do
    use GenServer

    def init(%{m: m} = state) do
        n = 160 - m
        << chordId :: size(m), _ :: size(n) >> = :crypto.hash(:sha, inspect(self()))
        state = Map.put(state, :myId, chordId)
        state = Map.put(state, :succList, [])
        {:ok, state}
    end
    
    def handle_call( :get_successor, _, %{succ: succ} = state ) do
        {:reply, succ, state}
    end
    def handle_call( :get_predecessor, _, %{pred: pred} = state ) do
        {:reply, pred, state}
    end

    def handle_call( :get_successor_list, _, %{succ: succ, succList: succList} = state ) do
        succList = if (succList == []), do: [succ], else: succList
        Map.put(state, :succList, succList)
        {:reply, succList, state}
    end

    def handle_call( {:closest_preceding_node, id}, _, %{finger_table: finger_table, myId: myId} = state ) do
        preceding_node = Enum.reduce( Enum.reverse(finger_table), nil, fn(x, acc) -> 
            xid = x |> elem(0)
            acc = 
                if(acc == nil) do
                    if( x_between_a_and_b?(xid, myId, id) ) do
                        x
                    end
                else
                    acc
                end
            acc
        end)

        preceding_node = if (preceding_node==nil), do: {myId, self()}, else: preceding_node
        {:reply, preceding_node, state}
    end

    def handle_call( {:find_successor, id}, _, %{succ: succ, succList: succList, myId: myId} = state ) do
        requestedNode = find_successor(id, succ, succList, myId)
        {:reply, requestedNode, state}
    end

    def find_successor(id, succ, succList, myId) do 

        succ = if succ |> elem(1) |> Process.alive?, do: succ, else: get_next_alive_successor(succList)
        succId = succ |> elem(0)

        requestedNode = 
        if( (id > myId && id <= succId) || (myId > succId && (id > myId || id <= succId)) ) do
            succ
        else
            x = succ |> elem(1) |> GenServer.call( {:closest_preceding_node, id} )
            if x |> elem(1) |> Process.alive? do
                x |> elem(1) |> GenServer.call( {:find_successor, id} )
            else
                succ
            end
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

    def handle_cast( {:create}, %{myId: myId} = state ) do
        succ = {myId, self()}
        state = Map.put(state, :succ, succ)

        schedule_work({:fix_fingers, 0})
        schedule_work({:stabilize})
        schedule_work({:check_predecessor})
        
        {:noreply, state}
    end

    def handle_cast( {:join, n}, %{myId: myId} = state ) do
        pred = nil
        succ = n |> elem(1) |> GenServer.call( {:find_successor, myId} )
        state = Map.put(state, :succ, succ)
        state = Map.put(state, :pred, pred)

        schedule_work({:fix_fingers, 0})
        schedule_work({:stabilize})
        schedule_work({:check_predecessor})

        {:noreply, state}
    end

    def handle_cast( {:add_finger_tables, finger_table}, state ) do
        state = Map.put(state, :finger_table, finger_table)
        {:noreply, state}
    end

    def handle_cast( {:search_key, {key, hops}}, %{succ: succ, succList: succList, finger_table: finger_table, myId: myId} = state ) do
        search_key({key, hops}, succ, succList, finger_table, myId)
        {:noreply, state}
    end

    def handle_cast({:add_key, {_, hops}}, %{myId: myId} = state) do
        
        [{_,{existing_hops,done}}] = :ets.lookup(:average_hops, myId)
        :ets.insert(:average_hops, {myId, {existing_hops++[hops],done}})

        {:noreply, state}
    end

    # Stabalization Loop functions
    def  handle_cast( {:notify, {nodeId, node}}, %{pred: pred, myId: myId} = state) do
        state = 
        if(pred == nil) do
            Map.put(state, :pred, {nodeId, node})
        else
            predId = pred |> elem(0)
            if( (nodeId < myId && predId < nodeId) || (myId < predId && (nodeId>predId || nodeId<myId)) ) do
                Map.put(state, :pred, {nodeId, node})
            else
                state
            end
        end

        {:noreply, state}
    end

    def handle_info( {:fix_fingers, next}, %{succ: succ, succList: succList, finger_table: finger_table, myId: myId, m: m} = state) do
        
        state = 
        try do
            finger_table = 
        finger_table = 
            finger_table = 
                if(length(finger_table) >= m) do
                    nextId = rem( trunc(myId + :math.pow(2, next)), trunc(:math.pow(2, m)) )
                    List.replace_at( finger_table, next, find_successor(nextId, succ, succList, myId) )
                else
                    nextId = rem( trunc(myId + :math.pow(2, next)), trunc(:math.pow(2, m)) )
                    List.insert_at( finger_table, next, find_successor(nextId, succ, succList, myId) )
                end
            Map.put(state, :finger_table, finger_table)
        catch
            :exit, _ -> state
        end
        next = next + 1
        next = if (next>m-1), do: 0, else: next
        schedule_work({:fix_fingers, next})

        {:noreply, state}
    end
    
    def handle_info( {:stabilize}, %{succ: succ,succList: succList, myId: myId, r: r} = state) do

        succ = if (succ |> elem(1) |> Process.alive?), do: succ, else: get_next_alive_successor(succList)
        pred =
        try do
            succ |> elem(1) |> GenServer.call(:get_predecessor)
        catch
            :exit, _ -> {myId, self()}
        end 
        
        predId = if (pred == nil), do: myId, else: pred |> elem(0)
        succ = if (succ |> elem(1) |> Process.alive?), do: succ, else: get_next_alive_successor(succList)
        succId = succ |> elem(0)
        state = 
        if( (predId > myId && predId < succId) || (myId > succId && (predId > myId || predId < succId)) ) do
            Map.put(state, :succ, pred)
        else
            state
        end
        succ = state.succ
        succ |> elem(1) |> GenServer.cast( {:notify, {myId, self()}} )
        
        newSuccList = 
            try do
                newSuccList = succ |> elem(1) |> GenServer.call(:get_successor_list) |> List.insert_at(0, succ)
                if(length(newSuccList)>r) do
                    Enum.take(newSuccList, r)
                else
                    newSuccList
                end
            catch
                :exit, _ -> succList
            end

        state = Map.put(state, :succList, newSuccList)    
        schedule_work({:stabilize})
        {:noreply, state}
    end

    def handle_info( {:check_predecessor}, %{pred: pred} = state) do
        state = 
        if(pred != nil) do
            if pred |> elem(1) |> Process.alive? do
                state
            else
                Map.put(state, :pred, nil)
            end
        else
            state
        end
        schedule_work({:check_predecessor})
        {:noreply, state}
    end

    @doc """
    Search Request Loop - For benchmarking
    """
    def handle_info( {:start_search_requests, numRequests, failure_chance},
                 %{succ: succ, succList: succList, finger_table: finger_table, myId: myId, m: m} = state ) do

        # Adding Failure chance of 0.5%
        [{_,{hops,_}}] = :ets.lookup(:average_hops,myId)
        if(:rand.uniform(1000) <= failure_chance*10 && hops == []) do
            [{_,{hops,_}}] = :ets.lookup(:average_hops,myId)
            :ets.insert(:average_hops,{myId, {hops,nil}})
            Process.exit(self(), :normal)
        end

        key = :math.pow(2, m) |> trunc |> :rand.uniform

        search_key({key, 0}, succ, succList, finger_table, myId)
        if(numRequests>1) do
            schedule_search_requests(numRequests-1, failure_chance)
        else
            [{_,{hops,_}}] = :ets.lookup(:average_hops,myId)
            :ets.insert(:average_hops,{myId, {hops,true}})
        end


        {:noreply, state}
    end


    defp search_key({key, hops}, succ, succList, finger_table, myId) do
        next = Enum.reduce(finger_table, {-1}, fn(x, acc) -> 
            if elem(acc,0) < elem(x,0) && elem(x,0) <= key, do: x, else: acc
        end)

        succ = if (succ |> elem(1) |> Process.alive?), do: succ, else: get_next_alive_successor(succList)
        succId = succ |> elem(0)

        if( (myId < key && key <= succId) || (myId > succId && (key > myId || key <= succId)) ) do
            succ |> elem(1) |> GenServer.cast( {:add_key, {key, hops+1}} )
        else
            if(next=={-1}) do
                succ |> elem(1) |> GenServer.cast( {:search_key, {key, hops+1}} )
            else
                next |> elem(1) |> GenServer.cast( {:search_key, {key, hops+1}} )
            end
        end
    end

    defp get_next_alive_successor(succList) do
        Enum.reduce(succList, nil, fn(x, acc) -> 
            if (acc == nil && (x |> elem(1) |> Process.alive?)) do
                x
            else
                acc
            end
        end)
    end

    # Checks if x lies between a & b including checking for the wraparound
    defp x_between_a_and_b?(x, a, b) do
        (a < x && x < b) || (a > b && (x > a || x < b)) 
    end

    defp schedule_work(msg) do
        Process.send_after(self(), msg, 1000)
    end

    defp schedule_search_requests(numRequests, failure_chance) do
        IO.puts("Search Loop Started")
        Process.send_after(self(), {:start_search_requests, numRequests, failure_chance}, 2000)
    end
end