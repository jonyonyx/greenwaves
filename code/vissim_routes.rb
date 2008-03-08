##
# This file can enumerate the possible routes between
# a list of links and generate Vissim output. Useful for 
# generating relative flows.

# facts:
# - connectors always connect two links denoted the from- and to link
# - in a non-trivial network links are always connected to at least 1 connector
# - there exist a route from A to C if there exist a connector from A to B and 
#   from B to C. This can be determined by following the outgoing connectors
#   from A and then B until a connector, which ends in C, is found

require 'const'
require 'vissim'
require 'facets/dictionary'

# now have both the connectors and links

def discover start, dest = nil, path=Dictionary[start,nil], &callback
  for adj,conn in start.adjacent
    # avoid loops by checking if the path contain this link
    next if path.has_key?(adj) 
    
    # assume there exist a valid route using this connector to reach adj_link;
    # if this is not true, nothing is returned anyhow.
    if adj == dest or adj.exit?
      # found an exit link for this path
      yield Route.new(path.merge(adj => conn)) 
    else
      # copy the path to avoid backreferences among routes
      discover(adj, dest, path.merge(adj => conn),&callback) # look further
    end
  end
end


def prune_identical routes
  # arterial optimization: prune "identical" routes ie same start and end

  identical_routes = [] # the identical routes with fewer lanes to remove
  for i in (0...routes.length)
    for j in (0...routes.length)
      next if i == j
      r1 = routes[i]
      r2 = routes[j]
    
      if r1.start == r2.start and r1.exit == r2.exit
        # found identical route
        # the shortest one is always the best, since the other includes 
        # a rest stop so store the one to remove
        identical_routes << [r1,r2].max
      end
    
    end
  end
  #puts "Pruned #{identical_routes.length} of #{identical_routes.length + routes.length} routes because they had the same start and exit"
  routes - identical_routes  
end

def find_routes start,dest  
  routes = []
  puts "Finding routes from #{start} to #{dest}"
  discover(start,dest) do |r|
    routes << r if r.exit == dest # skip past routes with true exits
  end
  routes = prune_identical routes
  puts "Discovered #{routes.length} routes from #{start} to #{dest}"
  routes
end

def get_routes(vissim, area_name)

  area_links = get_links(area_name)

  input_links = area_links.find_all{|l| l.input? }
  exit_links = area_links.find_all{|l| l.exit? }

  exit_numbers = exit_links.map{|l| l.number}

  routes = []
  for link in input_links.map{|l| vissim.links_map[l.number]}.compact
    discover(link) do |route|
      routes << route if exit_numbers.include?(route.exit.number)
    end
  end
  prune_identical routes
end

class RoutingDecision
  attr_reader :input_link, :composition, :i
  @@count = 0
  def initialize input_link, composition, desc = nil
    @desc = desc
    @input_link = input_link
    @composition = composition
    @routes = []
    @@count += 1
    @i = @@count
  end
  def add_route route, fraction
    raise "Warning: starting link (#{route.start}) of route was different 
             from the input link of the routing decision(#{@input_link})!" unless route.start == @input_link
      
    @routes << {'ROUTE' => route, 'FRACTION' => fraction}
  end
  def <=> rd
    @i <=> rd.i
  end
  def to_vissim
    str = "ROUTING_DECISION #{@i} NAME \"#{@desc ? @desc : comp_to_s(@composition)} from #{@input_link}\" LABEL  0.00 0.00\n"
    # AT must be AFTER the input point
    # link inputs are always defined in the end of the link
    str += "     LINK #{@input_link.number} AT 5.000\n"
    str += "     TIME FROM 0.0 UNTIL 99999.0\n"
    str += "     NODE 0\n"
    str += "      VEHICLE_CLASSES #{@composition}\n"
        
    @routes.each_with_index do |route_info,j|
      route = route_info['ROUTE']
      str += "     ROUTE     #{j+1}  DESTINATION LINK #{route.exit.number}  AT   7.500\n"
      str += "     FRACTION #{route_info['FRACTION']}\n"
      str += "     OVER #{route.to_vissim}\n"
    end
    str
  end
  def to_s
    to_vissim
  end
end  

if $0 == __FILE__ 

  puts "BEGIN"
  
  vissim = Vissim.new("#{Vissim_dir}tilpasset_model.inp")
  
  routes = get_routes(vissim,nil)

  
  
  # generate a routing decision for each link
  # sort by input (start) link number and then traffic composition
  # of exit (end) link
  decisions = []
  
  routingdec = nil
  
  input_links = routes.map{|r|r.start}.uniq # collect the set of starting links
  
  for input in input_links
    # make a new decision point for each vehicle class of the input
    # which is also a vehicle class at the exit link
  
    # find all routes starting at input, sorted by traffic type and then length
    for route in routes.find_all{|r| r.start == input}.sort{|r1,r2| r1.exit.traffic_composition == r2.exit.traffic_composition ? r1 <=> r2 : r1.exit.traffic_composition <=> r2.exit.traffic_composition}
      exit = route.exit
      exit_classes = exit.vehicle_classes
      
      # find the best composition between input and exit vehicle classes
      common_classes = input.vehicle_classes & exit_classes
      
      comp = find_composition(common_classes)
    
      #puts "Generating '#{comp_to_s(comp)}' route from #{input} to #{exit}"
    
      if routingdec.nil? or input != routingdec.input_link or comp != routingdec.composition        
        # make a new route decision point when a new starting location
        # or traffic composition for the route (exit link) is found.
        # first make sure only the appropriate vehicles take this route
        # by inspecting the vehicle types of the exit link
        # routing decisions have one or more routes to choose from
        
        routingdec = RoutingDecision.new(input, comp)
        decisions << routingdec
      end
      
      routingdec.add_route(route, 1) # TODO: calculate the proper fraction
    
    end
  end
  
  output_links = routes.map{|r|r.exit}.uniq # collect the set of exit links
  
  busplan = exec_query "SELECT BUS, [IN Link], [OUT Link] As OUT, Frequency As FREQ FROM [buses$]"
  businputs = busplan.map{|row| row['IN Link'].to_i}.uniq
  
  busroutemap = {}
  for input_num in businputs
    busroutemap[input_num] = busplan.find_all{|r| r['IN Link'].to_i == input_num}
  end
  
  for input_num,businfo in busroutemap
    input = input_links.find{|l| l.number == input_num}
    output_nums = businfo.map{|i| i['OUT'].to_i}
    outputs = output_links.find_all{|l| output_nums.include? l.number}
    
    busnames = businfo.map{|i| i['BUS']}
    
    routingdec = RoutingDecision.new(input, 1003, "Bus#{busnames.length > 1 ? 'es' : ''} #{busnames.join(', ')}")
    
    freq_sum = businfo.inject(0){|sum,i| sum + i['FREQ']}
    
    for output in outputs
      # find the route which connects this input and output link
      route = routes.find{|r| r.start == input and r.exit == output}
    
      busfreq = businfo.find{|i| i['OUT'].to_i == output.number}['FREQ']
      
      # 
      routingdec.add_route(route, busfreq / freq_sum) # 
    end
    decisions << routingdec
  end

  str = decisions.find_all{|dec| dec.composition != 1003}.map{|rd| rd.to_vissim}.join("\n")
  
  puts str

  Clipboard.set_data str
  puts "Please find the Routing Decisions on your clipboard."

  puts "END"
end