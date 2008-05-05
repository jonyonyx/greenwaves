##
# Classes which describe the physical vissim network
# 

require 'vissim_elem'

class RoadSegment < VissimElem  
  attr_reader :lanes,:closed_to
  def closed_to_any?(veh_types)
    return false unless @closed_to # nil => no closures
    not (@closed_to & veh_types).empty?
  end
end
class Connector < RoadSegment
  attr_reader :from,:to
  attr_accessor :dec # nil unless this conn is a decision (to turn)
  def <=>(c2)
    @intersection == c2.intersection ? @from_direction <=> c2.from_direction : @intersection <=> c2.intersection
  end
end
class Link < RoadSegment
  attr_reader :from_point,:to_point,:link_type,:adjacent,:predecessors,:lanes,:length
  attr_accessor :is_bus_input
  def initialize number
    super(number)
    @adjacent = {}
    @predecessors = []
  end
  def calculate_length; @from_point.distance(@to_point); end
  def adjacent_links; @adjacent.keys; end
  # connects self to link by connector
  # note there may be multiple connectors to the same link
  def add_successor link, conn
    connector_list = @adjacent[link] || []
    connector_list << conn
    @adjacent[link] = connector_list
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
  attr_reader :from,:intersection,:decisions
  def initialize from,intersection
    @from,@intersection = from,intersection
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
  def link
    
    raise "Decision point #{@from}#{@intersection} has no decisions!" if @decisions.empty?
    
    connectors = []    
    ObjectSpace.each_object(Connector) {|c| connectors << c if (c.closed_to & Cars_and_trucks).empty?}
    
    dec_pred_links = {}
    
    for dec in @decisions      
      pred_links = []
      dec_pred_links[dec] = pred_links
      # go backwards collecting predecessor links, assuming only one route
      # from the common origin link to the position of each decision
      conn = dec.connector
      begin
        pred_link = conn.from
        break if pred_links.include? pred_link # avoid loops
        pred_links << pred_link
        conn = connectors.find{|c| c.to == pred_link}
      end while conn and not conn.dec
    end
    
    # take the found links in reverse order so as to find the earlist possible
    # link to place the decision upon
    all_pred_links = dec_pred_links.values.flatten.uniq#.reverse
    link_candidates = all_pred_links.find_all{|pred_link| @decisions.all?{|dec| dec_pred_links[dec].include? pred_link}}    
        
    l = link_candidates.first
    
    unless l
      str = ""
      for dec,links in dec_pred_links
        puts "#{dec}: #{links ? links.join(' ') : '(none)'}"
      end
      raise "No common links found: #{str}"
    end
    l
    
  end
  def to_s
    "Decision point #{@from}#{@intersection}, decisions: #{@decisions.join(' ')}"
  end
end
class Decision
  attr_reader :from,:intersection,:turning_motion,:successors,:connector,:fractions, :weight
  class Interval
    attr_reader :tstart, :tend
    def hash; @tstart.hash + @tend.hash; end
    def eql?(other); @tstart == other.tstart and @tend == other.tend; end
    def to_vissim; "FROM #{@tstart} UNTIL #{@tend}"; end
    def to_s
      "#{@tstart} to #{@tend}"
    end
    def <=>(i2)
      @tstart <=> i2.tstart
    end
  end
  class Fraction
    attr_reader :interval, :veh_type, :quantity
    def <=>(f2)
      @interval <=> f2.interval
    end
    def to_s
      "Fraction from #{@interval} = #{quantity} #{@veh_type}"
    end
    def to_vissim
      "FRACTION #{@quantity}"
    end
  end
  def initialize
    # the numbered option for this turning motion, when altertives for the
    # same turning motion exist
    @successors = []
    @fractions = []
  end
  def time_intervals
    @fractions.map{|f| f.interval}
  end
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
  # a decision is an input if it has no predecessors
  # input decisions are assigned flow
  def input?
    ObjectSpace.each_object(Decision) do |dec|
      return false if dec.successors.include?(self)
    end
    true
  end
  def to_s
    "#{@from}#{@intersection}#{@turning_motion}#{@weight ? @weight : ''}"
  end
end