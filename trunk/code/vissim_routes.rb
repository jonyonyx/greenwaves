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

# a route is a list of links which are followed by using
# the given connectors
class Vissim
  class Route
    attr_reader :road_segments,:decisions
    def initialize(road_segments)
      @road_segments = road_segments
      @decisions = @road_segments.find_all{|rs| rs.instance_of?(Decision)}
    end
    def mark_arterial from_direction
      @road_segments.each{|rs| rs.update(:arterial_from => from_direction)}
    end
    # Calculates the length from the beginning of the first road segment
    # to the end of the last road segment.
    def length; @road_segments.map{|rs| rs.length}.sum; end
    def start; @road_segments.first; end
    def exit; @road_segments.last; end
    # returns a space-separated string of the connector-link-connector... sequence
    # for use in the vissim OVER format in route decisions
    def to_vissim; @road_segments[1..-1].map{|rs|rs.number}.join(' '); end
    def to_s; "#{start} > ... (#{@road_segments.size-2}) > #{exit}"; end  
    def <=>(other); @road_segments.size <=> other.road_segments.size; end
  end
  def discover start, exits, road_segments = [], &on_route_found
    return if not start.allows_private_vehicles?
    return if road_segments.include?(start) # avoid loops
    # check if start is the road segment we search for
    on_route_found.call(Route.new(road_segments + [start])) if exits.include?(start)
    if start.is_a?(Connector)
      # you can only search on by going to the connected link
      discover(start.to_link, exits, road_segments + [start], &on_route_found)
    else
      # start is a link and has zero or more outgoing connectors 
      start.outgoing_connectors.each do |conn|
        discover(conn, exits, road_segments + [start], &on_route_found)
      end
    end
  end
  # arterial optimization: prune "identical" routes ie same start and end 
  def prune_identical routes  
    exiting_at = {}
    routes.map{|r| r.exit}.uniq.each do |exit_link|
      exiting_at[exit_link] = routes.find_all{|r| r.exit == exit_link}
    end
    
    routes_to_remove = []
    for start_link in routes.map{|r| r.start}.uniq
      # Eliminating route duplicates starting at start_link... 
      for r1 in routes.find_all{|r| r.start == start_link}
        next if routes_to_remove.include? r1
        duplicates = exiting_at[r1.exit].find_all{|r2| r2 != r1 and r2.start == start_link}
        routes_to_remove << duplicates
      end
    end
  
    routes - routes_to_remove
  end

  def find_routes start,dest  
    routes = []
    discover(start,[dest].flatten) do |r|
      routes << r
    end
    routes
  end

  # finds all full ie. start-to-end routes
  # in the given vissim network
  def get_full_routes  
    routes = []
    for start in input_links
      discover(start, exit_links) do |route|
        routes << route
      end
    end
  
    #prune_identical routes
    routes
  end
end

if __FILE__ == $0
  require 'vissim'
  vissim = Vissim.new
  #require 'profile'
  routes = vissim.get_full_routes
  puts "Found #{routes.length} routes"
  
  #  for route in routes.find_all{|r|  r.exit.number == 5}
  #    puts "#{route} over #{route.decisions.join(', ')}"
  #  end  
end
