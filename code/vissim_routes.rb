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

def discover link, path=Dictionary[link,nil], &callback
  for adj_link,conn in link.adjacent
    # avoid loops by checking if the path contain this link
    next if path.has_key?(adj_link) 
    
    # assume there exist a valid route using this connector to reach adj_link;
    # if this is not true, nothing is returned anyhow.
    if adj_link.exit?
      # found an exit link for this path
      yield Route.new(path.merge(adj_link => conn)) 
    else
      # copy the path to avoid backreferences among routes
      discover(adj_link,path.merge(adj_link => conn),&callback) # look further
    end
  end
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

if $0 == __FILE__ 

  puts "BEGIN"
  
  vissim = Vissim.new("#{Vissim_dir}tilpasset_model.inp")
  
  routes = get_routes(vissim,nil)
  
  busroutes = routes.find_all{|r| not (r.exit.buses & r.start.buses).empty?}
  
  puts "Found #{routes.length} routes and #{busroutes.length} busroutes"
  for route in busroutes
    puts "#{route.start.buses.join(' ')} on #{route.start} to #{route.exit} #{route.exit.buses.join(' ')}"
  end
  
  exit(0)

  routes = get_routes(vissim,'Herlev')
  
  # generate a routing decision for each link
  output_string = ''
  last_input = nil
  last_comp = nil
  i = 1
  # sort by input (start) link number and then traffic composition
  # of exit (end) link

  for input in routes.map{|r|r.start}.uniq # collect the set of starting links
    # make a new decision point for each vehicle class of the input
    # which is also a vehicle class at the exit link
  
    # find all routes starting at input, sorted by traffic type and then length
    for route in routes.find_all{|r| r.start == input}.sort{|r1,r2| r1.exit.traffic_composition == r2.exit.traffic_composition ? r1 <=> r2 : r1.exit.traffic_composition <=> r2.exit.traffic_composition}
      exit = route.exit
      exit_classes = exit.vehicle_classes
      
      # find the best composition between input and exit vehicle classes
      common_classes = input.vehicle_classes & exit_classes
      
      comp = find_composition(common_classes)
    
      puts "Generating '#{comp_to_s(comp)}' route from #{input} to #{exit}" if last_input
    
      unless input == last_input and comp == last_comp
        #puts "Generated #{j-1} '#{comp_to_s(last_comp)}' routes from #{last_input}" if last_input
        j = 1 # new decision point, reset route choice counter
    
        last_input = input        
        last_comp = comp
        # make a new route decision point when a new starting location
        # or traffic composition for the route (exit link) is found.
        # first make sure only the appropriate vehicles take this route
        # by inspecting the vehicle types of the exit link
        output_string += "ROUTING_DECISION #{i} NAME \"'#{comp_to_s(comp)}' from #{input}\" LABEL  0.00 0.00\n"
        # AT must be AFTER the input point
        # link inputs are always defined in the end of the link
        output_string += "     LINK #{input.number} AT 50.000\n"
        output_string += "     TIME FROM 0.0 UNTIL 99999.0\n"
        output_string += "     NODE 0\n"
        output_string += "      VEHICLE_CLASSES #{comp}\n"
        # routing decisions have one or more routes to choose from
        i += 1 # move to next routing decision index
      end
  
      output_string += "     ROUTE     #{j}  DESTINATION LINK #{route.exit.number}  AT   50.000\n"
      output_string += "     FRACTION 1\n"
      output_string += "     OVER #{route.to_vissim}\n"
      j += 1
    
    end
  end

  Clipboard.set_data output_string
  puts "Please find the Routing Decisions on your clipboard."

  puts "END"
end