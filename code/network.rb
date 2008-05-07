##
# Classes which describe the physical vissim network
# 

require 'vissim_elem'

class RoadSegment < VissimElem  
  attr_reader :lanes,:closed_to,
    :arterial_from # if set, indicates this road is part of the artery direction and from which direction
  def closed_to_any?(veh_types)
    #return false if @closed_to.nil?
    raise "Vehicle lanes closure was not defined for #{self}!" if @closed_to.nil?
    not (@closed_to & veh_types).empty?
  end
end
# Connectors establish a one-way connection from a link to another
class Connector < RoadSegment
  attr_reader :from_link,:to_link
end
# A decision is a connector, which, whenever taken, has a deciding effect
# on the final route of the motorist
class Decision < Connector
  attr_reader :from_direction,:intersection,:turning_motion,:fractions,:weight
  def initialize(number)
    super(number)
    # the numbered option for this turning motion, when altertives for the
    # same turning motion exist
    @fractions = []
  end
  def time_intervals; @fractions.map{|f| f.interval}; end
  def add_fraction(tstart, tend, vehtype, quantity)
    interval = Interval.new!(:tstart => tstart, :tend => tend)
    raise "Fractions at #{to_s} for #{vehtype} from #{interval} already exist!" if @fractions.any?{|f| f.interval == interval and f.veh_type == vehtype}
    @fractions << Fraction.new!(:interval => interval, :veh_type => vehtype, :quantity => quantity)
  end
  def <=>(d2)
    @intersection == d2.intersection ? 
      (@from == d2.from ? @turning_motion <=> d2.turning_motion : @from <=> d2.from) : 
      @intersection <=> d2.intersection
  end  
  # helper-classes for Decision
  class Interval
    attr_reader :tstart, :tend
    def hash; @tstart.hash + @tend.hash; end
    def eql?(other); @tstart == other.tstart and @tend == other.tend; end
    def to_vissim; "FROM #{@tstart} UNTIL #{@tend}"; end
    def to_s; "#{@tstart} to #{@tend}"; end
    def <=>(i2); @tstart <=> i2.tstart; end
  end
  class Fraction
    attr_reader :interval, :veh_type, :quantity
    def <=>(f2); @interval <=> f2.interval; end
    def to_s; "Fraction from #{@interval} = #{quantity} #{@veh_type}"; end
    def to_vissim; "FRACTION #{@quantity}";end
  end
end
class Link < RoadSegment
  attr_reader :from_point,:to_point,:link_type,:adjacent,:lanes,:length,:intersection_number,:from_direction
  attr_accessor :is_bus_input
  def initialize number
    super(number)
    @adjacent = Hash.new{|h,k| h[k] = []}
  end
  def calculate_length; @from_point.distance(@to_point); end
  def adjacent_links; @adjacent.keys; end
  # connects self to link by connector
  # note there may be multiple connectors to the same link
  def add_successor link, conn
    raise "#{self} cannot be adjacent to itself!" if link == self
    @adjacent[link] << conn
  end
  # is this link an exit (from the network) link?
  def exit?; @adjacent.empty?; end
  def input?; @link_type == 'IN'; end
  def to_s
    str = super
    str << "#{@direction}" if @direction
    str
  end
end
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
  # locates the common origin link for the decisions in this decision point
  # do this by finding a link from which there is a route to all decision 
  # destination links
  def link vissim
    
    # check if this decision point routes traffic directly from an input link
    # if so, place the decision point there
    input_link = vissim.links.find{|l| l.intersection_number == @intersection and l.from_direction == @from_direction}
    
    return input_link if input_link
    
    # otherwise, perform a backwards search for the best common starting point...    
    raise "Decision point #{@from}#{@intersection} has no decisions!" if @decisions.empty?
    
    dec_pred_links = {}
    
    for dec in @decisions      
      pred_links = []
      dec_pred_links[dec] = pred_links
      # go backwards collecting predecessor links, assuming only one route
      # from the common origin link to the position of each decision
      conn = dec
      begin
        pred_link = conn.from_link
        break if pred_links.include? pred_link # avoid loops
        pred_links << pred_link
        conn = vissim.connectors.find{|c| c.to_link == pred_link}
      end while conn and not conn.instance_of?(Decision)
    end
    
    # take the found links in reverse order so as to find the earlist possible
    # link to place the decision upon
    all_pred_links = dec_pred_links.values.flatten.uniq#.reverse
    link_candidates = all_pred_links.find_all{|pred_link| @decisions.all?{|dec| dec_pred_links[dec].include? pred_link}}    
        
    l = link_candidates.first
    
    unless l
      str = ""
      for dec,links in dec_pred_links
        str << "#{dec}: #{links ? links.join(' ') : '(none)'}\n"
      end
      raise "No common links found: #{str}"
    end
    l
    
  end
  def to_s
    "Decision point #{@from}#{@intersection}, decisions: #{@decisions.join(' ')}"
  end
end