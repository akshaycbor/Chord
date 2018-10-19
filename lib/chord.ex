defmodule Chord do
  @moduledoc """
  Documentation for Chord.
  """

  def main(numNodes, numRequests) do

    m = 12
    n = 160 - m
    chordNodes = Enum.map( 1..numNodes, fn(_) ->
        {:ok, pid} = GenServer.start_link(ChordNode, {[nil, nil], [], [], m})
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

    chordNodes
  end

  def sendmsg(chordNodes, msg) do
    randomNode = Enum.random(chordNodes)
    IO.inspect(randomNode)
    randomNode |> elem(1) |> GenServer.cast({:add_file, msg})
  end

end
