defmodule Chord do
  @moduledoc """
  Documentation for Chord.
  """

  def main(numNodes, numRequests, failure_chance) do

    m = numNodes |> :math.log2 |> :math.ceil |> trunc |> Kernel.+(2)
    n = 160 - m
    r = trunc(:math.log2(numNodes))
    
    chordNodes = Enum.map( 1..numNodes, fn(_) ->
        init_state = %{pred: nil, succ: nil, finger_table: [], files: [], m: m, r: r}
        {:ok, pid} = GenServer.start_link(ChordNode, init_state)
        << chordId :: size(m), _ :: size(n) >> = :crypto.hash(:sha, inspect(pid))
        { chordId , pid }
    end)

    chordNodes = chordNodes |> List.keysort(0) #Sort list of tuples by 0th element

    # Adding Neighbours
    Enum.map( 0..length(chordNodes)-1, fn(i) ->
        pred = if i == 0, do: Enum.at(chordNodes, length(chordNodes)-1), else: Enum.at(chordNodes, i-1)
        succ = Enum.at( chordNodes, rem(i+1, length(chordNodes)) )

        Enum.at(chordNodes, i) |> elem(1) |> GenServer.cast({:add_predecessor, pred})
        Enum.at(chordNodes, i) |> elem(1) |> GenServer.cast({:add_successor, succ})
    end)

    # Adding Finger Tables
    Enum.map(chordNodes, fn(x) ->
        finger_table = Enum.map(0..m-1, fn(i) ->
            t = rem( trunc(elem(x,0) + :math.pow(2, i)), trunc(:math.pow(2, m)) )
            Enum.reduce_while(chordNodes, Enum.at(chordNodes, 0), fn(x, acc) ->
                if elem(x,0) >= t, do: {:halt, x}, else: {:cont, acc}
            end)    
        end)

        x |> elem(1) |> GenServer.cast({:add_finger_tables, finger_table})
    end)

    # Initializing stabilization loops
    Enum.map(chordNodes, fn(x) ->
        x |> elem(1) |> Process.send_after({:stabilize}, elem(x,0))
        x |> elem(1) |> Process.send_after({:fix_fingers, 0}, elem(x,0))
        x |> elem(1) |> Process.send_after({:check_predecessor}, elem(x,0))
    end)
  
    :ets.new(:average_hops, [:set, :public, :named_table])
    Enum.each(chordNodes, fn(x) -> 
        :ets.insert(:average_hops, {x |> elem(0), {[], false}})
    end)

    Enum.map(chordNodes, fn(x) ->
        x |> elem(1) |> Process.send_after({:start_search_requests,numRequests, failure_chance}, 10000)
    end)

    checkConvergence(chordNodes, numNodes, numNodes*numRequests)
    
  end

  def checkConvergence(chordNodes, numNodes, totalRequests) do
    {hops, done, failed} = Enum.reduce(chordNodes, {[],true,0}, fn(x, {hops,done, failed})-> 
                    [{_,{node_hops,value}}] = :ets.lookup(:average_hops, x |> elem(0))
                    {value, failed} = if value == nil, do: {true, failed+1}, else: {value, failed}
                    {hops++node_hops,done && value, failed}
                end)
    
    if done do
        trim = trunc(10*totalRequests/100)
        hops = hops |> Enum.sort |> Enum.take(trim-totalRequests) |> Enum.take(totalRequests-2*trim)
        sum = Enum.reduce(hops, 0, fn(x, acc) -> acc+x end)
        IO.puts("Average Hops:#{sum/(totalRequests-2*trim)}, % of Nodes Failed:#{(failed/numNodes)*100}")
        Process.exit(self(),:kill)
    else
        :timer.sleep(1000)
        checkConvergence(chordNodes, numNodes, totalRequests)
    end
  end


  def createAndJoin(x, m) do

    init_state = %{pred: nil, succ: nil, finger_table: [], files: [], m: m}
    {:ok, pid} = GenServer.start_link(ChordNode, init_state)

    pid |> GenServer.cast( {:join, x} )
  end

end
