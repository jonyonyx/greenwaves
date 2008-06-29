# Classes which describe the physical vissim network

require 'vissim_elem'

class RoadSegment < VissimElem  
  attr_reader :lanes,:closed_to, :over_points,
    :arterial_from # if set, indicates this road is part of the artery 
  #direction and from where
  def closed_to_any?(veh_types)
    raise "Vehicle lanes closure was not defined for #{self}!" if @closed_to.nil?
    not (@closed_to & veh_types).empty?
  end
  def allows_private_vehicles?
    not closed_to_any?(Cars_and_trucks)
  end
  def length_over_points
    return 0.0 if @over_points.empty?
    (0...@over_points.size-1).map do |i|
      @over_points[i].distance(@over_points[i+1])
    end.sum
  end
end
# Connectors establish a one-way connection from a link to another
class Connector < RoadSegment
  attr_reader :from_link,:at_from_link,:to_link,:at_to_link
  def length
    # TODO: handle case when connector is not placed in the ends of from_link or to_link
    length_over_points 
  end
end
# A decision is a connector, which, whenever taken, has a deciding effect
# on the final route of the motorist
class Decision < Connector
  attr_reader :from_direction,:intersection,:turning_motion,:fractions,:weight,:drop_link,
    :decide_from_direction, :decide_at_intersection
  def initialize(number)
    super(number)
    # the numbered option for this turning motion, when altertives for the
    # same turning motion exist
    @fractions = []
  end
  def time_intervals; @fractions.map{|f| f.interval}; end
  def add_fraction(tstart,tend, vehtype, quantity)
    interval = Interval.new(tstart, tend)
    raise "Fractions at #{to_s} for #{vehtype} from #{interval} already exist!" if @fractions.any?{|f| f.interval == interval and f.veh_type == vehtype}
    
    @fractions << Fraction.new!(:interval => interval, :veh_type => vehtype, :quantity => quantity)
  end
  def <=>(d2)
    @intersection == d2.intersection ? 
      (@from_direction == d2.from_direction ? @turning_motion <=> d2.turning_motion : @from_direction <=> d2.from_direction) : 
      @intersection <=> d2.intersection
  end
end
class Link < RoadSegment
  attr_reader :from_point,:to_point,
    :link_type,:lanes,:length,
    :intersection_number,:from_direction,
    :outgoing_connectors
  attr_accessor :is_bus_input
  def initialize number
    super(number)
    @outgoing_connectors = [] # a list of outgoing connectors from this link
  end
  
  # is this link an exit (from the network) link?
  def exit?; @outgoing_connectors.empty?; end
  # input links can be detected but we need to be able to filter
  # them out
  def input?; @link_type == 'IN'; end
  # returns a list of decisions for which this link is the drop-off link
  def drop_for
    return @drop_for if @drop_for
    @drop_for = if @name =~ /drop (.+)/
      $1.split(',').map{|s|s.strip}
    else; []; end
  end
  def to_s
    str = super
    str << "#{@direction}" if @direction
    str
  end
end

# A decision point is point on a link where a decision
# must be made about which way to go from here ie. which
# of the possible decisions to take.
class DecisionPoint
  attr_reader :from_direction,:intersection,:decisions
  def initialize from,intersection
    @from_direction,@intersection = from,intersection
    @decisions = []
    @link = nil
  end
  
  # retrieve a combined set of time intervals
  # for the flows defined on all decisions in this 
  # decision point.
  # note that the decisions might not have flows in the same
  # time intervals
  def time_intervals
    @decisions.map{|d|d.time_intervals}.flatten.uniq
  end
  # Locates the common origin link for the decisions in this decision point.
  # Does this by finding a link from which there is a route to all decision 
  # destination links
  def link vissim
    return @link if @link # cache hit
    
    # check if this decision point routes traffic directly from an input link
    # if so, place the decision point there to assign the decision
    # as early as possible
    
    input_link = vissim.links.find do |l| 
      l.intersection_number == @intersection and l.from_direction == @from_direction
    end
    
    return @link = input_link if input_link
    
    # otherwise, perform a backwards search for the best common starting point...    
    raise "Decision point #{@from_direction}#{@intersection} has no decisions!" if @decisions.empty?
    
    drop_links = @decisions.map{|dec|dec.drop_link}
    
    # Looking for a link which has routes ending at all of the drop links    
    link_routes = {}
    (vissim.links - drop_links).each do |link|
      link_routes[link] = vissim.find_routes(link,drop_links)
    end
    
    # remove any link which is not connected to all drop links
    link_routes.delete_if do |link,routes|
      not drop_links.all?{|drop_link|routes.any?{|route|route.exit == drop_link}}
    end
    
    # remove any link which has routes that does not traverse one of the decisions
    link_routes.delete_if do |link,routes|
      not @decisions.all?{|dec|routes.any?{|route|route.decisions.include?(dec)}}
    end
    
    # We now have a number of candidates. We want the one closest 
    # to the decisions. Exploit that we *know* these links have routes to
    # all drop links.    
    shortest_route = link_routes.values.flatten.min
    @link = shortest_route.start
    
    @link || raise("No link found from which #{drop_links.join(', ')} can be reached")
  end
  def <=>(dp2)
    @intersection == dp2.intersection ? @from_direction <=> dp2.from_direction : @intersection <=> dp2.intersection
  end
  def to_s
    "Decision Point #{@from_direction}#{@intersection}: #{@decisions.join(', ')}"
  end
end
