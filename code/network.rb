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

# A list of vehicle fractions for time intervals.
class Fractions < Array
  def filter interval,vehtype
    Fractions.new(find_all{|f|f.interval == interval and f.veh_type == vehtype})
  end
  def self.sum fractions
    if fractions.instance_of?(Fractions)
      fractions.sum
    else
      fractions.map{|f|f.quantity}.sum      
    end
  end
  def sum
    map{|f|f.quantity}.sum
  end
end
# A decision is a connector, which, whenever taken, has a deciding effect
# on the final route of the motorist
class Decision < Connector
  attr_reader :from_direction,:intersection,:turning_motion,:fractions,:weight,
    :decide_from_direction, :decide_at_intersection
  def initialize(number)
    super(number)
    # the numbered option for this turning motion, when altertives for the
    # same turning motion exist
    @fractions = Fractions.new
  end
  def decid
    "#{@from_direction}#{@intersection}#{@turning_motion}"
  end
  # use the in vissim defined drop link or find the furthest away
  # link which does not split into several roads
  def drop_link
    return @drop_link if @drop_link
    to_link = @to_link
    
    # continue along the road (to_link and further down) as long as
    # no choices must be made between roads
    # (method: more connectors may connect a road to the same downstream road)
    while to_link.outgoing_connectors.map{|conn|conn.to_link}.uniq.size == 1
      to_link = to_link.outgoing_connectors.first.to_link
    end
    @drop_link = to_link
  end
  def foreign_decision?
    @from_direction != @decide_from_direction or @intersection != @decide_at_intersection
  end
  def disable_route?
    @name =~ /no-route/
  end
  def decide_at
    "#{@decide_from_direction}#{@decide_at_intersection}"
  end
  def original_approach
    "#{@from_direction}#{@intersection}"    
  end
  def time_intervals; @fractions.map{|f| f.interval}; end
  def add_fraction(interval, vehtype, quantity)
    raise "Fractions at #{to_s} for #{vehtype} from #{interval} already exist!" if @fractions.any?{|f| f.interval == interval and f.veh_type == vehtype}
    
    @fractions << Fraction.new(interval, vehtype, quantity)
  end
  def <=>(d2)
    @intersection == d2.intersection ? 
      (@from_direction == d2.from_direction ? @turning_motion <=> d2.turning_motion : @from_direction <=> d2.from_direction) : 
      @intersection <=> d2.intersection
  end
  # helper-classes for Decision
  class Interval
    attr_reader :tstart, :tend
    def initialize tstart,tend
      @tstart,@tend = tstart,tend    
    end
    def shift!(seconds)
      @tstart += seconds
      @tend += seconds
    end
    def copy
      Interval.new(@tstart,@tend)
    end
    def resolution_in_minutes
      (@tend-@tstart)/60
    end
    def hash
      @tstart.hash + @tend.hash
    end
    def eql?(other)
      self == other
    end
    def ==(other)
      @tstart == other.tstart and @tend == other.tend
    end
    def to_vissim(tbegin); "FROM #{@tstart - tbegin} UNTIL #{@tend - tbegin}"; end
    def to_s; "#{@tstart.to_hm} to #{@tend.to_hm}"; end
    def <=>(i2); @tstart <=> i2.tstart; end
  end
  class Fraction
    attr_reader :interval, :veh_type, :quantity
    def initialize interval, veh_type, quantity
      @interval, @veh_type, @quantity = interval, veh_type, quantity
    end
    def copy
      Fraction.new(@interval.copy,@veh_type,@quantity)
    end
    def adjust(amount)
      @quantity += amount
      @quantity = 0.0 if @quantity < 0
    end
    def set(value)
      @quantity = value
    end
    def <=>(f2); @interval <=> f2.interval; end
    def to_s; "Fraction from #{@interval} = #{@quantity} #{@veh_type}"; end
    def to_vissim; "FRACTION #{@quantity}";end
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
class DecisionPoint < Array
  attr_reader :from_direction,:intersection,:decisions
  def initialize from,intersection
    @from_direction,@intersection = from,intersection
    @link = nil
  end
  
  # retrieve a combined set of time intervals
  # for the flows defined on all decisions in this 
  # decision point.
  # note that the decisions might not have flows in the same
  # time intervals
  def time_intervals(program,insert_repeat_interval = true)
    intervals = map{|d|d.time_intervals}.flatten.uniq.find_all{|i|program.interval === i.tstart}
    if program.repeat_first_interval and insert_repeat_interval
      firstinterval = intervals.min.copy
      firstinterval.shift!(-program.resolution*60)
      intervals << firstinterval
    end
    intervals
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
    raise "Decision point #{@from_direction}#{@intersection} has no decisions!" if empty?
    
    drop_links = map{|dec|dec.drop_link}
    
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
      not all?{|dec|routes.any?{|route|route.decisions.include?(dec)}}
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
