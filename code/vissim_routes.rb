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

class Route  
  attr_reader :links,:connectors,:decisions
  # a route is a list of links which are followed by using
  # the given connectors
  def initialize links,connectors
    @links,@connectors = links,connectors
    @decisions = @connectors.map{|conn| conn.dec} - [nil]
  end
  def length; @links.length; end
  def start; @links.first; end
  def exit; @links.last; end
  # returns a space-separated string of the connector-link-connector... sequence
  # for use in the vissim OVER format in route decisions
  def to_vissim
    str = ''
    for i in (1...length-1)
      conn = @connectors[i-1]
      link = @links[i]
      str += "#{conn.number} #{link.number} "
    end
    str += connectors.last.number.to_s # last connector, omit the link (implicit = exit link)
  end
  def to_dpstring
    decisions.join(' > ')
  end
  def to_s
    "#{start} > ... (#{length-2}) > #{exit}"
  end  
  def <=>(other)
    length <=> other.length
  end
end

# now have both the connectors and links

def discover start, exits, links = [start], connectors = [], &callback
  for adj,conn in start.adjacent
    # avoid loops by checking if the path contain this link
    # or the link is closed to ordinary vehicle types
    next if links.include? adj or conn.closed_to_any? Cars_and_trucks
    # assume there exist a valid route using this connector to reach adj_link;
    # if this is not true, nothing is returned anyhow.
    if exits.include? adj
      # found an exit link for this path
      yield Route.new(links + [adj], connectors + [conn]) 
    else
      # copy the path to avoid backreferences among routes
      discover adj, exits, links + [adj], connectors + [conn], &callback # look further
    end
  end
end

def prune_identical routes
  # arterial optimization: prune "identical" routes ie same start and end
  
  exiting_at = {}
  routes.map{|r| r.exit}.uniq.each do |exit_link|
    exiting_at[exit_link] = routes.find_all{|r| r.exit == exit_link}
  end
    
  routes_to_remove = []
  for start_link in routes.map{|r| r.start}.uniq
    #puts "Eliminating route duplicates starting at #{start_link}... "
    for r1 in routes.find_all{|r| r.start == start_link}
      next if routes_to_remove.include? r1
      duplicates = exiting_at[r1.exit].find_all{|r2| r2 != r1 and r2.start == start_link}
      routes_to_remove += duplicates
    end
  end
  
  #puts "Eliminated #{routes_to_remove.length} of #{routes.length} routes"
  
  routes - routes_to_remove
end

def find_routes start,dest  
  routes = []
  #puts "Finding routes from #{start} to #{dest}"
  discover(start,[dest]) do |r|
    routes << r
  end
  prune_identical routes
end

# finds all full ie. start-to-end routes
# in the given vissim network
def get_full_routes(vissim)
  
  routes = []
  for start in vissim.input_links    
    #count = routes.length
    #print "Finding routes from #{start}... "
    discover(start, vissim.exit_links) do |route|
      routes << route
    end
    #puts "found #{routes.length - count} routes"
  end
  
  #puts "Completed route enumeration, found #{routes.length} routes in total"
  
  prune_identical routes
end

if __FILE__ == $0
  # 48131026
  vissim = Vissim.new(Default_network)
  routes = get_full_routes vissim
  #puts routes
  puts "Found #{routes.length} routes"
  
  for route in routes    
    route_numbers = route.connectors.map{|l|l.number}
    puts route.to_vissim if [11253].all?{|n| route_numbers.include? n}
  end
  
end
