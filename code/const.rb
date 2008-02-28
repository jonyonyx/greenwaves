# 
# To change this template, choose Tools | Templates
# and open the template in the editor.
 
require 'csv'
require 'Win32API'
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

##
# Wrapper for csv data files
class Csvtable < Array
  attr_reader :header
  def initialize csvfile
    reader = CSV.open(csvfile,'r',';')
    @header = reader.shift
    
    reader.each{|row| self << row}
    
    reader.close
  end
  def self.enumerate csvfile
    reader = CSV.open(csvfile,'r',';')
    header = reader.shift
    
    reader.each do |row|
      row_map = {} # NB: case sensitive
      row.each_with_index{|e,i| row_map[header[i]] = e.to_s}
      yield row_map
    end
    
    reader.close
  end
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
    return AMBER if (@red_end+1..@red_end+1+@tred_amber) === cycle_sec
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
  attr_reader :direction,:has_buses,:has_trucks,:link_type,:rel_inflow,:adjacent
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
    @direction = attributes['DIRECTION']
    @has_buses = attributes['HAS_BUSES'] == 'Y' # are buses inserted on this link?
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
  def exit?; @link_type == 'EXIT' or @adjacent.empty?; end
  def input?
    return true if @link_type == 'INPUT'
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
    if has_buses
      if has_trucks
        1 # buses and trucks
      else
        3 # buses, no trucks
      end
    else
      if has_trucks
        # trucks, no buses
        2
      else
        # no buses, no trucks
        1001
      end
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
class Decision
  attr_reader :from,:intersection,:turning_motion,:traversed_by_routes  
  attr_accessor :p # probability of reaching this decision
  def initialize from,intersection,turning_motion
    @from,@intersection,@turning_motion = from,intersection,turning_motion    
    @p = 0.0
  end
  def <=>(dp2)
    @intersection == dp2.intersection ? 
    (@from == dp2.from ? @turning_motion <=> dp2.turning_motion : @from <=> dp2.from) : 
    @intersection <=> dp2.intersection
  end
  def to_s
    "#{@intersection}#{@from}#{@turning_motion}"
  end
  def traversed_by routes
    @traversed_by_routes = routes
  end
  def traversed_by? route
    return false unless @traversed_by_routes
    @traversed_by_routes.include? route
  end
end
class Connector < VissimElem
  attr_reader :from,:to,:lanes,:dec
  def initialize number,name,from,to,lanes
    super number,'NAME' => name
    @from,@to,@lanes = from,to,lanes
    if name =~ /([NSEW])(\d+)([LTR])/
      @dec = Decision.new($1,$2.to_i,$3)
    end
  end
  def <=>(c2)
    @intersection == c2.intersection ? @from_direction <=> c2.from_direction : @intersection <=> c2.intersection
  end
end
def get_links area_name, type_filter = nil    
  type_filter = type_filter.downcase if type_filter
    
  links_map = {}
  ObjectSpace.each_object(Link) do |link|
    links_map[link.number] = link
  end
    
  links = []
  Csvtable.enumerate("#{Vissim_dir}#{area_name}_links.csv") do |row|     
    number = row['NUMBER'].to_i
            
    if links_map.has_key?(number)
      # enrich the existing object with data from the csv file
      link = links_map[number]
      link.update row
      links << link
    else
      next if type_filter and not row['TYPE'].downcase == type_filter
      links << Link.new(number,row)
    end
  end
  links
end
def comp_to_s(comp)
  case comp
  when 1
    'Cars, buses, trucks'
  when 2
    'Cars, trucks'
  when 3    
    'Cars, buses'
  when 1001
    'Cars only'
  when 1002
    'Trucks only'
  when 1003
    'Buses only'
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

if $0 == __FILE__ 
  h = {}
  puts h.methods
end