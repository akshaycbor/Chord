# Reads arguments from cmd and passes them to Gossip module
{numNodes, numRequests, failure_chance} = List.to_tuple(System.argv)
Chord.main(String.to_integer(numNodes), String.to_integer(numRequests), String.to_integer(failure_chance))