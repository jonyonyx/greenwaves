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
  # explore adjacent links first, starting with the ones
  # with the more lanes as they are more interesting in routes
  #start.adjacent.sort{|p1,p2| p1[0].lanes <=> p2[0].lanes}.reverse_each do |adj,conn|  
  
#  unless start.is_a?(Link) # TODO: Find out why Arrays are passed as start!
#    puts "Received non-Link object: '#{start}' class: #{start.class}!"    
#    start = start.first # assume this is an array!
#  end
  
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
        #identical_routes << [r1,r2].max
        if r1.length < r2.length
          identical_routes << r2
        elsif r1.length > r2.length
          identical_routes << r1
        else
          # find the links which are unique to the route
          # and
          r1_uniq_links = [r1.links - r2.links].flatten          
          r2_uniq_links = [r2.links - r1.links].flatten
          r1_lanes = r1_uniq_links.map{|l| l.lanes}.sum
          r2_lanes = r2_uniq_links.map{|l| l.lanes}.sum
          
          #puts "found identical routes but r1 lanes = #{r1_lanes}, r2 lanes =#{r2_lanes}" if r1_lanes != r2_lanes
          if r1_lanes > r2_lanes
            identical_routes << r2
          elsif r1_lanes < r2_lanes
            identical_routes << r1
          else
            # pick one of them, for now!
            # until something new breaks!!! arg :)
            identical_routes << r1
          end
        end
      end
    
    end
  end
  #puts "Pruned #{identical_routes.length} of #{identical_routes.length + routes.length} routes because they had the same start and exit"
  routes - identical_routes  
end

def find_routes start,dest  
  routes = []
  #puts "Finding routes from #{start} to #{dest}"
  discover(start,dest) do |r|
    routes << r if r.exit == dest # skip past routes with true exits
  end
  routes = prune_identical routes
  #puts "Discovered #{routes.length} routes from #{start} to #{dest}"
  routes
end

def get_routes(vissim)
  area_links = get_links

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
