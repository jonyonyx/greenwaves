##
# Classes which describe the physical vissim network
# 

require 'vissim_elem'

class Link < VissimElem
  attr_reader :from,:link_type,:adjacent,:predecessors,:lanes,:length
  attr_accessor :is_bus_input
  def initialize number,attributes    
    super
    update attributes
    
    # map from adjacent links, which can be reached from self, 
    # to the used connector
    @adjacent = {}
    @predecessors = []
  end
  def update opts
    super
    @from = opts['FROM']
    @link_type = opts['TYPE']
    @lanes ||= opts['LANES']
    @length ||= opts['LENGTH']
  end
  def adjacent_links; @adjacent.keys; end
  # connects self to given adjacent link by given connector
  def add proximtype, link, conn
    case proximtype
    when :successor
      @adjacent[link] = conn
    when :predecessor      
      @predecessors << link
    end
  end
  # is this link an exit (from the network) link?
  def exit?; @adjacent.empty?; end
  def input?; @link_type == 'IN'; end
  def to_s
    str = super
    str += ' ' + @direction if @direction
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
    
    #puts "#{@from}#{@intersection}: #{link_candidates.join(' ')}" if link_candidates.length > 1
    
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
  def add decision
    @decisions << decision
  end  
  def check_prob_assigned
    for veh_type in @decisions.map{|dec| dec.p.keys}.flatten.uniq
      sum = @decisions.map{|dec| dec.p[veh_type]}.sum
      raise "The sum of turning probabilities for #{veh_type} at decision point #{@from}#{@intersection} was #{sum}! 
           Maybe you forgot to mark a connector?" if (sum-1.0).abs > 0.01
    end
  end
  def to_s
    str = "Decision point #{@from}#{@intersection}:"
    for dec in @decisions
      successors = dec.successors
      str += "\n\t#{dec.turning_motion}, successors: #{successors.empty? ? '(none)' : successors.join(' ')}"
    end
    str
  end
end
class Decision
  attr_reader :from,:intersection,:turning_motion,:successors,:connector,
    :p # probability of reaching this decision per vehicle type
  def initialize from,intersection,turning_motion, connector
    @from,@intersection,@turning_motion = from,intersection,turning_motion    
    @connector = connector
    @p = Hash.new(0.0)
    @successors = []
  end
  def <=>(d2)
    @intersection == d2.intersection ? 
    (@from == d2.from ? @turning_motion <=> d2.turning_motion : @from <=> d2.from) : 
    @intersection <=> d2.intersection
  end
  def add_succ dec
    raise "Warning: nil successors are not allowed" unless dec
    @successors << dec unless @successors.include?(dec)
  end
  # a decision is an input if it has no predecessors
  # input decisions are assigned flow
  def input?
    ObjectSpace.each_object(Decision) do |dec|
      return false if dec.successors.include?(self)
    end
    return true
  end
  def to_s
    "#{@from}#{@intersection}#{@turning_motion}"
  end
end
class Connector < VissimElem
  attr_reader :from,:to,:lanes,:dec,:closed_to
  def initialize number,name,from,to,lanes,closed_to
    super number,'NAME' => name
    @from,@to,@lanes,@closed_to = from,to,lanes,closed_to
    if name =~ /([NSEW])(\d+)([LTR])/
      # only one connector object represents each physical connector
      @dec = Decision.new($1,$2.to_i,$3,self)
    end
  end
  def closed_to_any? veh_types
    not (@closed_to & veh_types).empty?
  end
  def <=>(c2)
    @intersection == c2.intersection ? @from_direction <=> c2.from_direction : @intersection <=> c2.intersection
  end
end