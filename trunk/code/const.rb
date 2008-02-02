# 
# To change this template, choose Tools | Templates
# and open the template in the editor.
 
require 'csv'
require 'Win32API'
require 'win32/clipboard' 
include Win32

Base_dir = 'D:\\greenwaves\\'
Herlev_dir = Base_dir + 'data\\DOGS Herlev 2007\\'
Glostrup_dir = Base_dir + 'data\\DOGS Glostrup 2007\\'
Vissim_dir = Base_dir + 'Vissim\\o3_roskildevej-herlevsygehus\\'
Res = 15 # resolution in minutes of inputs

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
  def initialize path # array of link- and connector tuples
    raise "Minimal route has a start and exit link, received #{path.inspect}!" if path.length < 2
    @seq = path
  end
  def length; @seq.length; end
  def start; @seq[0][0]; end
  def exit; @seq[-1][0]; end
  # return a list of connectors used respecting the link order
  # skipping the connector of the start link, which is known to be nil
  def connectors
    @seq[1..-1].map{|link,by_conn| by_conn}
  end
  def links
    @seq.map{|link,by_conn| link}
  end
  def include? link
    links.include? link
  end
  # returns a space-separated string of the connector-link-connector... sequence
  # for use in the vissim OVER format in route decisions
  def to_vissim
    str = ''
    for link,conn in @seq[1..-2]
      str += "#{conn.number} #{link.number} "
    end
    str += @seq[-1][1].number.to_s # last connector, omit the link (implicit = exit link)
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
class SignalController < VissimElem
  attr_reader :controller_type,:cycle_time,:offset,:groups
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
  end
  def add group
    @groups[group.number] = group
  end
end
class SignalGroup < VissimElem
  attr_reader :red_end,:green_end,:tred_amber,:tamber,:heads
  def initialize(number,attributes)
    super
    update attributes
    @heads = [] # signal heads in this group
  end
  def update attributes
    super
    @red_end = attributes['RED_END'].to_f
    @green_end = attributes['GREEN_END'].to_f
    @tred_amber = attributes['TRED_AMBER'].to_f
    @tamber = attributes['TAMBER'].to_f
  end
  def add head
    @heads << head
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
  def to_s
    str = super
    str += ' ' + format('%f', proportion) if @rel_inflow > 0.0
    str += ' ' + @direction if @direction
    str
  end
end
class Connector < VissimElem
  attr_reader :from,:to,:lanes
  def initialize number,name,from,to,lanes
    super number,'NAME' => name
    @from,@to,@lanes = from,to,lanes
  end
end
class VissimFun
  def VissimFun.get_links area_name, type_filter = nil
    
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
end

if $0 == __FILE__ 
  puts VissimFun.get_links('herlev')
end