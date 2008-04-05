# 
# collect results from vissim results .mdb file

require 'const'
require 'vissim'
require 'vissim_routes'

def link_desc link
  "#{link.number}#{link.name ? " #{link.name}" : ''}"
end

vissim = Vissim.new(Default_network)

routes = get_full_routes(vissim, vissim.input_links + vissim.links.find_all{|l| l.is_bus_input})

ttsql = 'SELECT TOP 10 [No_], SUM(Veh), AVG(Trav) FROM TRAVELTIMES GROUP BY [No_]'

File.open('c:\temp\test.csv','w') do |file|
  file << "Travel Time Number;Vehicles;Travel Time;From Link;To Link;First Decision;Last Decision\n"
  for row in exec_query(ttsql, CSRESDB)
    ttnum = row[0]
    
    # find the traveltime entry in order to gain additional insight
    tt = vissim.tt_map[ttnum]
    from, to = tt.from, tt.to
    route = routes.find{|r| r.start == from and r.exit == to}
        
    raise "No route found from #{from} to #{to}!" if route.nil?
    
    # extract the decisions which are traversed first and last on this route
    firstdec = route.decisions.first
    lastdec = route.decisions.last
    
    file << "#{ttnum};#{row[1]};#{row[2].round};"
    file << "#{link_desc(from)};#{link_desc(to)};#{firstdec};#{lastdec}\n"
  end
end