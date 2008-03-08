# 
# To change this template, choose Tools | Templates
# and open the template in the editor.

require 'Win32API'
require 'dbi'
require 'win32/clipboard' 
include Win32
require 'facets'

Base_dir = 'D:\\greenwaves\\'
Herlev_dir = Base_dir + 'data\\DOGS Herlev 2007\\'
Glostrup_dir = Base_dir + 'data\\DOGS Glostrup 2007\\'
Vissim_dir = Base_dir + 'Vissim\\o3_roskildevej-herlevsygehus\\'
Time_fmt = '%02d:%02d:00'
Res = 15 # resolution in minutes of inputs
RED,YELLOW,GREEN,AMBER = 'R','Y','G','A'
MINOR = 'Minor'
MAJOR = 'Major'
NONE = 'None'
DOGS_TIME = 10
Type_map = {'Cars' => 1001, 'Trucks' => 1002, 'Buses' => 1003}
  
DATAFILE = "../data/data.xls"
CS = "DBI:ADO:Provider=Microsoft.Jet.OLEDB.4.0;Data Source=#{DATAFILE};Extended Properties=\"Excel 8.0;HDR=Yes;IMEX=1\";"

def to_clipboard str, print = false
  puts str if print
  Clipboard.set_data str
  puts "String data has been copied to your clipboard."
end

class Route  
  # a route is a list of links which are followed by using
  # the given connectors
  def initialize path # ordered hash (facets/dictionary) of link to connector
    raise "Minimal route has a start and exit link, received #{path.inspect}!" if path.length < 2
    @seq = path
  end
  def length; @seq.length; end
  def start; links.first; end
  def exit; links.last; end
  # return a list of connectors used respecting the link order
  # skipping the connector of the start link, which is known to be nil
  def connectors
    @seq.values[1..-1]
  end
  def links
    @seq.keys
  end
  def include? link
    @seq.has_key? link
  end
  # returns a space-separated string of the connector-link-connector... sequence
  # for use in the vissim OVER format in route decisions
  def to_vissim
    str = ''
    for link in links[1..-2]
      conn = @seq[link]
      str += "#{conn.number if conn} #{link.number} "
    end
    str += connectors.last.number.to_s # last connector, omit the link (implicit = exit link)
  end
  def decisions
    connectors.map{|conn| conn.dec} - [nil]
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
class VissimElem
  attr_reader :number,:name  
  def initialize number,attributes
    @number = number
    update attributes
  end
  def update attributes
    @name = attributes['NAME']
  end
  def type; self.class.to_s; end
  def to_s
    "#{type} #{@number} '#{@name}'"
  end
  def hash; @number + type.hash; end
  def eql?(other); self.class == other.class and @number == other.number; end
end
class Stage < VissimElem
  attr_reader :groups
  def initialize number, groups
    super number,{}
    @groups = groups
  end
  def to_s
    @number.to_s
  end
  def priority
    group_priorities = @groups.map{|grp| grp.priority}.uniq
    raise "Warning: mixed group priorities in same stage #{@groups.map{|grp| "#{grp.name} => #{grp.priority}"}}" if group_priorities.length > 1
    group_priorities.first 
  end
end
class SignalController < VissimElem
  attr_reader :controller_type,:cycle_time,:offset,:groups,:program
  def initialize number, attributes
    super
    update attributes
    @groups = {}
  end
  def update attributes
    super
    @controller_type = attributes['TYPE']
    @cycle_time = attributes['CYCLE_TIME'].to_f
    @offset = attributes['OFFSET'].to_f
    @program = attributes['PROGRAM']
  end
  def add group
    @groups[group.number] = group
  end
  def interstage_active?(cycle_sec)
    # all-red phases are considered interstage
    return true if @groups.values.all?{|grp| grp.color(cycle_sec) == RED}
    
    # check for ordinary interstages
    @groups.values.any?{|grp| [YELLOW,AMBER].include? grp.color(cycle_sec)}
  end
  def stages
    last_stage = nil
    last_interstage = nil
    stagear = []
    for t in (1..@cycle_time)
      if interstage_active?(t)
        if last_interstage
          last_interstage = last_interstage.succ unless stagear.last == last_interstage
        else
          last_interstage = 'a'
        end
        stagear << last_interstage
      else
        # check if any colors have changed
        #        unless last_stage
        #          last_stage = Stage.new(1,@groups.values.find_all{|grp| grp.active_seconds === t})
        #        end
        if @groups.values.all?{|grp| grp.color(t) == grp.color(t-1)}
          stagear << last_stage
        else
          last_stage = Stage.new(last_stage ? last_stage.number+1 : 1,@groups.values.find_all{|grp| grp.active_seconds === t})
          stagear << last_stage
        end
      end
    end
    stagear
  end
  def to_s
    str = super + "\n"    
    for grpnum in @groups.keys.sort
      str += "   #{@groups[grpnum]}\n"
    end
    str
  end
end
class SignalGroup < VissimElem
  attr_reader :red_end,:green_end,:tred_amber,:tamber,:heads,:priority
  def initialize(number,attributes)
    super
    update attributes
    @heads = [] # signal heads in this group
  end
  def update attributes
    super
    @red_end = attributes['RED_END'].to_i
    @green_end = attributes['GREEN_END'].to_i
    @tred_amber = attributes['TRED_AMBER'].to_i
    @tamber = attributes['TAMBER'].to_i
    @priority = attributes['PRIORITY']
  end
  def add head
    @heads << head
  end
  def color(cycle_sec)
    return GREEN if active_seconds === cycle_sec
    return AMBER if (@red_end+1..@red_end+@tred_amber) === cycle_sec
    return YELLOW if (@green_end..@green_end+@tamber) === cycle_sec
    return RED
  end
  def active_seconds
    green_start = @red_end + @tred_amber + 1
    if green_start < green_end
      (green_start..green_end)
    else
      # (green_end+1..green_start) defines the red time
      (1..green_end) # todo: handle the case of green time which wraps around
    end
  end
  def to_s
    super #format("%s\t%d %d %d %d",super,@red_end,@green_end,@tred_amber, @tamber)
  end
end
class SignalHead < VissimElem
  attr_reader :position_link,:lane
  def initialize number, attributes
    super
    update attributes
  end
  def update attributes
    super
    @position_link = attributes['POSITION LINK'].to_i
    @lane = attributes['LANE'].to_i
  end
end
class Link < VissimElem
  attr_reader :from,:has_trucks,:link_type,:rel_inflow,:adjacent
  # total proportion request by all elems of each type
  @@total_inflow = 0.0
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
        
    # subtract the old contribution, if defined
    @@total_inflow -= @rel_inflow if @rel_inflow
    @rel_inflow = attributes['REL_INFLOW'] ? attributes['REL_INFLOW'].to_i : 0.0
    @@total_inflow += @rel_inflow
  end
  def proportion
    @rel_inflow / @@total_inflow
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
  def traffic_composition
    # choose a composition (all links have cars!)
    # please refer to the -- Traffic Compositions: -- section
    # in the .inp file for the numbers
    # note: make sure there is a 1:1 correspondance between
    # traffic compositions and vehicle classes (poor data design by ptv)
    
    if has_trucks
      # trucks, no buses
      2
    else
      # no buses, no trucks
      1001
    end
  end
  def vehicle_classes
    # see note in method traffic_composition
    case traffic_composition
    when 1
      [1001,1002,1003]
    when 2
      [1001,1002]
    when 3
      [1001,1003]
    else
      [1001]
    end
  end
  def to_s
    str = super
    #str += ' ' + format('%f', proportion) if @rel_inflow > 0.0
    str += ' ' + @direction if @direction
    #str += ' ' + vehicle_classes.inspect
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
    
    #puts "in link, decisions: #{@decisions.join(' ')}"
    
    connectors = []    
    ObjectSpace.each_object(Connector) {|c| connectors << c}
    
    dec_pred_links = {}
    
    if "#{@from}#{@intersection}" == "S3"
      puts "halløj!"
    end
    
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
    
#    for dec,pred_links in dec_pred_links
#      puts "#{dec}: #{pred_links.join(', ')}"
#    end
    all_pred_links = dec_pred_links.values.flatten.uniq
    all_pred_links.find{|pred_link| @decisions.all?{|dec| dec_pred_links[dec].include? pred_link}}    
    
  end
  def add decision
    @decisions << decision
  end  
  def check_prob_assigned
    sum = @decisions.map{|dec| dec.p}.sum
    raise "Warning: the sum of turning probabilities for decision point #{@from}#{@intersection} was #{sum}! 
           Maybe you forgot to mark a connector?" if (sum-1.0).abs > 0.01
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
  attr_reader :from,:intersection,:turning_motion,:flow,:successors,:connector
  attr_accessor :p # probability of reaching this decision
  def initialize from,intersection,turning_motion, connector
    @from,@intersection,@turning_motion = from,intersection,turning_motion    
    @connector = connector
    @p = 0.0
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
  @@decision_map = {}
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
def exec_query sql, conn_str = CS
  DBI.connect(conn_str) do |dbh|  
    return dbh.select_all(sql)
  end
end
def get_links area_name, type_filter = nil    
  type_filter = type_filter.downcase if type_filter
    
  links_map = {}
  ObjectSpace.each_object(Link) do |link|
    links_map[link.number] = link
  end
    
  links = []
  
  sql = "SELECT 
          NUMBER, 
          NAME, 
          [FROM], 
          TYPE
        FROM [links$] As LINKS
        #{area_name ? "WHERE Area = '#{area_name}'" : ''}"
  
  for row in exec_query sql
    number = row['NUMBER'].to_i    
            
    if links_map.has_key?(number)
      # enrich the existing object with data from the database
      link = links_map[number]
      link.update row
    else
      next if type_filter and not row['TYPE'].downcase == type_filter
      link = Link.new(number,row)
    end
    links << link
  end
  links
end
def comp_to_s(comp)
  case comp
  when 2
    'Cars, trucks'
  when 1003
    'Buses'
  end
end
def find_composition(veh_classes)
  case veh_classes.length
  when 1
    1001 # just cars (all routes have cars)
  when 2
    if veh_classes.include? 1002
      2 # cars and trucks
    else
      3 # cars and buses
    end
  when 3
    1 # all vehicle classes - there are only 3
  end
end

class Numeric
  def square ; self * self ; end
end

class Array
  def sum ; self.inject(0){|a,x|x+a} ; end
  def mean ; self.sum.to_f/self.size ; end
  def median
    case self.size % 2
    when 0 then self.sort[self.size/2-1,2].mean
    when 1 then self.sort[self.size/2].to_f
    end if self.size > 0
  end
  # not quite correct version of quantile
  def quantile p
    i = (size*p).ceil - 1
    #puts i
    sort[i]
  end
  def histogram ; self.sort.inject({}){|a,x|a[x]=a[x].to_i+1;a} ; end
  def mode
    map = self.histogram
    max = map.values.max
    map.keys.select{|x|map[x]==max}
  end
  def squares ; self.inject(0){|a,x|x.square+a} ; end
  def variance ; self.squares.to_f/self.size - self.mean.square; end
  def deviation ; Math::sqrt( self.variance ) ; end
  def permute ; self.dup.permute! ; end
  def permute!
    (1...self.size).each do |i| ; j=rand(i+1)
      self[i],self[j] = self[j],self[i] if i!=j
    end;self
  end
  def sample n=1 ; (0...n).collect{ self[rand(self.size)] } ; end
end

if $0 == __FILE__ 
  a=%w{34 29 26 32 35 38 31 34 30 29 32 31}.collect{|x|x.to_i}
  puts a.bins(4).inspect
end