# 
# collect results from vissim results .mdb file

require 'const'
require 'vissim'
require 'vissim_routes'
require 'win32ole'

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
  
  def initialize vissim
    @vissim = vissim
  end
  
  # columns of the vissim results database to the
  # names *we* want to use!
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
  
  def extract_results name, resdir
    
    for row in exec_query(NODEEVALSQL, "#{CSPREFIX}#{File.join(resdir,'results.mdb')};")
    
      # find the traveltime entry in order to gain additional insight
      node = @vissim.node_map[row['NODE']]
      fromnum, tonum = row['FROMLINK'], row['TOLINK']
      fromlink = @vissim.links_map[fromnum]
      tolink = @vissim.links_map[tonum]
      
      raise "From link #{fromnum} not found!" if fromlink.nil?
      raise "To link #{tonum} not found!" if fromlink.nil?
      
      results = {}
      COLS_TO_HEADERS.each{|k,h| results[k] = row[k]}
      
      self << NodeEvaluation.new(name, node, fromlink, tolink, row['TSTART'], row['TEND'], results)
    end
  end
  def to_xls xlsfile = "#{Base_dir}results\\results.xls"
        
    insect_info = exec_query "SELECT Name, Number FROM [intersections$]"          
    
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
      routes = find_routes(from, to)
      raise "No route found from #{from} to #{to}!" if routes.empty?
      raise "Multiple routes found from #{from} to #{to}!" if routes.length > 1
      
      route = routes.first
      
      # extract the decisions which are traversed first and last on this route
      decision = route.decisions.first
      
      intersection = insect_info.find{|r| r['Number'] == decision.intersection}['Name']
            
      # 'arterial' traffic exits in either end of the arterial
      traffic_type = if ['N','S'].include?(decision.from) and decision.turning_motion == 'T'
        'Arterial'
      else
        'Crossing'
      end
      
      node = nodeeval.node
      
      rows << [node.number, 
        nodeeval.testname, 
        intersection, 
        decision.from, 
        decision.turning_motion, 
        traffic_type, 
        nodeeval.tstart,
        nodeeval.tend,
        *COLS_TO_HEADERS.map{|k,h| nodeeval.results[k]}]
    end
    
    to_xls rows, 'data', xlsfile
  end
end

if __FILE__ == $0
  vissimnet = Vissim.new(Default_network)
  results = NodeEvals.new(vissimnet)
  results.extract_results 'test simulation', Vissim_dir
  results.to_xls
end
