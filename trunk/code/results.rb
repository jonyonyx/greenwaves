# collect results from vissim results .mdb file

require 'const'
require 'vissim'
require 'vissim_routes'

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
class NodeEvals < Array
  
  # NodeEvaluation requires a vissim network instance to obtain 
  # the node evaluation and combine results with the decisions, which are passed
  def initialize vissim = Vissim.new
    @vissim = vissim
  end
  
  # columns of the vissim results database to the
  # names *we* want to use! Note this is a 
  # array of tuples since we want to preserve the order
  COLS_TO_HEADERS = [
    ['avequeue', 'Average Queue'], 
    ['delay_2_', 'Car & Truck Delay'], 
    ['delay_1003_', 'Bus Delay']
  ]
  
  NODEEVALSQL = "SELECT 
              NODE,
              FROMLINK,
              TOLINK,
              TSTART,
              TEND,
              #{COLS_TO_HEADERS.map{|k,h| "AVG(#{k}) As #{k}"}.join(', ')}
            FROM NODEEVALUATION
            WHERE MOVEMENT <> 'All'
            GROUP BY NODE, FROMLINK, TOLINK, TSTART, TEND"
  
  # called after each vissim test has been repeated a number of times
  def extract_results testname, testdir
    
    for row in exec_query(NODEEVALSQL, "#{CSPREFIX}#{File.join(testdir,'results.mdb')};")
    
      # find the traveltime entry in order to gain additional insight
      node = @vissim.nodes.find{|n| n.number == row['NODE']}
      fromnum, tonum = row['FROMLINK'], row['TOLINK']
      fromlink = @vissim.link(fromnum) || raise("From link #{fromnum} not found!")
      tolink = @vissim.link(tonum) || raise("To link #{tonum} not found!")
      
      results = {}
      COLS_TO_HEADERS.each{|k,h| results[k] = row[k]}
      
      self << NodeEvaluation.new(testname, node, fromlink, tolink, row['TSTART'], row['TEND'], results)
    end
  end
  def to_a
        
    insect_info = DB["SELECT name, number FROM [intersections$]"].all
    
    rows = [['Node',
      'Test Name', 
      'Intersection', 
      'From', 
      'Motion', 
      'Traffic Type', 
      'Period Start', 
      'Period End',
      *COLS_TO_HEADERS.map{|k,h| h}]]
    
    for nodeeval in sort{|ne1, ne2| ne1.node <=> ne2.node}
      from, to = nodeeval.fromlink, nodeeval.tolink
      route = @vissim.find_route(from, to)
      
      # extract the decisions which are traversed first and last on this route
      decision = route.decisions.first || 
        raise("Expected a route from #{from} to #{to} traversing a decision, found: #{route.to_vissim}")
      
      intersection = insect_info.find{|r| r[:number] == decision.intersection}[:name]
            
      # 'arterial' traffic exits in either end of the arterial
      # 'minor road' traffic comes from the minor roads and cross or turn in on
      # the artery
      traffic_type = if ARTERY_DIRECTIONS.include?(decision.from_direction) and decision.turning_motion == 'T'
        'Arterial'
      else
        'Minor road'
      end
      
      node = nodeeval.node
      
      rows << [node.number, 
        nodeeval.testname, 
        intersection, 
        decision.from_direction, 
        decision.turning_motion, 
        traffic_type, 
        nodeeval.tstart,
        nodeeval.tend,
        *COLS_TO_HEADERS.map{|k,h| nodeeval.results[k]}]
    end
    
    rows
  end
end

if __FILE__ == $0
  vissimnet = Vissim.new(Default_network)
  results = NodeEvals.new(vissimnet)
  results.extract_results 'test simulation', Vissim_dir
  results.to_xls
end
