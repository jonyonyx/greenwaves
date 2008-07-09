class NodeEvaluation
  attr_reader :testname, :node, :results, :fromlink, :tolink, :tstart, :tend
  def initialize name, node, fromlink, tolink, tstart, tend, results
    @testname = name
    @node = node
    @fromlink, @tolink = fromlink, tolink
    @tstart, @tend = tstart, tend
    @results = results # hash of result types to their values
  end
  def <=>(othernodeeval)
    (@node == othernodeeval.node) ? (@testname <=> othernodeeval.testname) : (@node <=> othernodeeval.node)
  end
end

# A class for Data Collection Points
class CollectionPoint < VissimElem
  attr_reader :position_link, :lane, :at, :decision
end