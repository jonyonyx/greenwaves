##
# Classes which describe the physical vissim network
# 

require 'vissim_elem'

class Link < VissimElem
  attr_reader :from,:link_type,:adjacent,:lanes
  def initialize number,attributes    
    super
    update attributes
    
    # map from adjacent links, which can be reached from self, 
    # to the used connector
    @adjacent = {}
  end
  def update attributes
    super
    @from = attributes['FROM']
    @has_trucks = attributes['HAS_TRUCKS'] == 'Y' # are trucks inserted on this link?
    @link_type = attributes['TYPE']
    @lanes = attributes['LANES'].to_i
  end
  def adjacent_links; @adjacent.keys; end
  # connects self to given adjacent link by given connector
  def add adj_link,conn
    raise "Link was nil #{to_s}" unless adj_link
    raise "Connector was nil #{to_s}" unless conn
    @adjacent[adj_link] = conn
  end
  # is this link an exit (from the network) link?
  def exit?; @link_type == 'OUT' or @adjacent.empty?; end
  def input?
    return true if @link_type == 'IN'
    # look for links, which have self on the adjacent list
    # if none are found, this is an input link
    ObjectSpace.each_object(Link) do |link|
      return false if link.adjacent_links.include?(self)
    end
    true
  end
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
    
    connectors = []    
    ObjectSpace.each_object(Connector) {|c| connectors << c}
    
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
    
    #link_candidates.first
    # rule of thumb: links with more lanes are likely to be "true" sections of road
    link_candidates.min{|l1,l2| l1.lanes <=> l2.lanes} 
  end
  def add decision
    @decisions << decision
  end  
  def check_prob_assigned
    for veh_type in @decisions.map{|dec| dec.p.keys}.flatten.uniq
      sum = @decisions.map{|dec| dec.p[veh_type]}.sum
      raise "Warning: the sum of turning probabilities for #{veh_type} at decision point #{@from}#{@intersection} was #{sum}! 
           Maybe you forgot to mark a connector?" if (sum-1.0).abs > 0.01
    end
  end
  def to_s
    str = "Decision point #{@from}#{@intersection}:"
    for dec in @decisions
      successors = dec.successors
      str += "\n\t#{dec.turning_motion} #{format('split: %02f',dec.p)}, successors: #{successors.empty? ? '(none)' : successors.join(' ')}"
    end
    str
  end
end
class Decision
  attr_reader :from,:intersection,:turning_motion,:flow,:successors,:connector,
    :p # probability of reaching this decision per vehicle type
  def initialize from,intersection,turning_motion, connector
    @from,@intersection,@turning_motion = from,intersection,turning_motion    
    @connector = connector
    @p = Hash.new(0.0)
    @flow = 0.0
    @successors = []
  end
  def <=>(d2)
    @intersection == d2.intersection ? 
    (@from == d2.from ? @turning_motion <=> d2.turning_motion : @from <=> d2.from) : 
    @intersection <=> d2.intersection
  end
  # assigns flow to this decision
  # from dec which is the predecessor decision supplying flow to this decision
  def assign dec
    @flow += dec.flow * @p
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
    "#{@intersection}#{@from}#{@turning_motion}"
  end
end
class Connector < VissimElem
  attr_reader :from,:to,:lanes,:dec
  def initialize number,name,from,to,lanes
    super number,'NAME' => name
    @from,@to,@lanes = from,to,lanes
    if name =~ /([NSEW])(\d+)([LTR])/
      # only one connector object represents each physical connector
      @dec = Decision.new($1,$2.to_i,$3,self)
    end
  end
  def <=>(c2)
    @intersection == c2.intersection ? @from_direction <=> c2.from_direction : @intersection <=> c2.intersection
  end
end