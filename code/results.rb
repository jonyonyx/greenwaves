# 
# collect results from vissim results .mdb file

require 'const'
require 'vissim'
require 'vissim_routes'

class TravelTimeResult
  attr_reader :testname, :tt, :value
  def initialize name, tt, value
    @testname = name
    @tt = tt
    @value = value
  end
  def <=>(ttres)
    (@tt == ttres.tt) ? (@testname <=> ttres.testname) : (@tt <=> ttres.tt)
  end
end
class TravelTimeResults < Array
  def extract_results name, vissim

    ttsql = 'SELECT TOP 10 [No_], AVG(Trav) FROM TRAVELTIMES GROUP BY [No_]'
    
    for row in exec_query(ttsql, CSRESDB)
      ttnum = row[0]
    
      # find the traveltime entry in order to gain additional insight
      tt = vissim.tt_map[ttnum]
    
      self << TravelTimeResult.new(name, tt, row[1].to_i)
    end
  end
  def print vissim #csvfile = "#{Base_dir}results\\#{@name}.csv"
    insect_info = exec_query "SELECT Name, Number FROM [intersections$]"
    routes = get_full_routes(vissim, vissim.input_links + vissim.links.find_all{|l| l.is_bus_input})
    
    for tt in map{|res| res.tt}.uniq.sort
      for ttres in find_all{|res| res.tt == tt}.sort
        tt = ttres.tt
        value = ttres.value
        testname = ttres.testname
        # find the traveltime entry in order to gain additional insight
        from, to = tt.from, tt.to
        route = routes.find{|r| r.start == from and r.exit == to}
        
        raise "No route found from #{from} to #{to}!" if route.nil?
    
        # extract the decisions which are traversed first and last on this route
        firstdec = route.decisions.first
        lastdec = route.decisions.last
        
        fromis = insect_info.find{|r| r['Number'] == firstdec.intersection}['Name']
        tois = insect_info.find{|r| r['Number'] == lastdec.intersection}['Name']
        puts "#{tt} in '#{testname}': #{value}"
      
      end
    end
  end
end

def link_desc link
  "#{link.number}#{link.name ? " #{link.name}" : ''}"
end


if __FILE__ == $0
  vissim = Vissim.new(Default_network)
  results = TravelTimeResults.new
  results.extract_results 'test', vissim
  results.extract_results 'test2', vissim
  puts "entering print"
  results.print vissim
end