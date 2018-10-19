defmodule ChordNode do
    use GenServer

    def init(state) do
        {:ok, state}
    end
    
    def handle_cast( {:add_successor, successor}, {[pred, _], finger_table, files, m} ) do
        {:noreply, { [pred, successor], finger_table, files, m }}
    end
    def handle_cast( {:add_predecessor, predecessor}, {[_, succ], finger_table, files, m} ) do
        {:noreply, { [predecessor, succ], finger_table, files, m }}
    end

    def handle_cast( {:add_finger_tables, finger_table}, {neighbours, _, files, m} ) do
        {:noreply, { neighbours, finger_table, files, m }}
    end

    def handle_cast( {:add_file, file}, {neighbours, finger_table, files, m} ) do
        n = 160 - m
        << fileId :: size(m), _ :: size(n) >> = :crypto.hash(:sha, file)
        IO.inspect(fileId)
        self() |> GenServer.cast( {:add_hashed_file, {fileId, file}} )
        {:noreply, { neighbours, finger_table, files, m }}
    end

    def handle_cast( {:add_hashed_file, {fileId, file}}, {[pred, succ], finger_table, files, m} ) do
        
        next = Enum.reduce(finger_table, {-1}, fn(x, acc) -> 
            if elem(acc,0) < elem(x,0) && elem(x,0) <= fileId, do: x, else: acc
        end)

        n = 160 - m
        << myId :: size(m), _ :: size(n) >> = :crypto.hash(:sha, inspect(self()))
        if(myId < fileId && ( elem(succ, 0) >= fileId || (elem(succ, 0) < fileId && myId > elem(succ, 0))) ) do
            succ |> elem(1) |> GenServer.cast( {:put_file, {fileId, file}} )
        else 
            if(next==-1) do
                succ |> elem(1) |> GenServer.cast( {:add_hashed_file, {fileId, file}} )
            else
                next |> elem(1) |> GenServer.cast( {:add_hashed_file, {fileId, file}} )
            end
        end
        {:noreply, {[pred, succ], finger_table, files, m}}
    end

    def handle_cast({:put_file, file}, {neighbours, ft, files, m}) do
        {:noreply, {neighbours, ft, [file | files], m}}
    end

    def handle_cast( {:search_hashed_file, {fileId, file}}, {[pred, succ], finger_table, files, m} ) do
        
        if Enum.member?(files, {fileId, file}) do
            IO.puts("Found  the sucka")
        end
        next = Enum.reduce(finger_table, {-1}, fn(x, acc) -> 
            if elem(acc,0) < elem(x,0) && elem(x,0) <= fileId, do: x, else: acc
        end)

        if(next==-1) do
            succ |> elem(1) |> GenServer.cast( {:add_hashed_file, {fileId, file}} )
        else
            next |> elem(1) |> GenServer.cast( {:add_hashed_file, {fileId, file}} )
        end
        {:noreply, {[pred, succ], finger_table, files, m}}
    end

end