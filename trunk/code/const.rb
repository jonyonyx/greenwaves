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
    header = reader.shift.map{|col_name| col_name.downcase}
    
    reader.each do |row|
      row_map = {}
      row.each_with_index{|e,i| row_map[header[i]] = e}
      yield row_map
    end
    
    reader.close
  end
end
    
class VissimElem
  attr_reader :type,:number,:name
  
  # total proportion request by all elems of each type
  @@total_prop = Hash.new(0.0) 
  def initialize type,number,name,prop
    @type,@number,@name,@prop = type,number,name,prop
    @@total_prop[@type] = @@total_prop[@type] + prop
  end
  def proportion
    @prop / @@total_prop[@type]
  end
  def to_s
    "#{@type} #{@number} '#{@name}'"
  end
  def hash; @number; end
  def eql?(other)
    other.number == @number
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
class Link < VissimElem
  attr_reader :direction,:has_buses,:adjacent
  def initialize number,name,direction,rel_proportion = 0.0, bus_input = 'N',exit = false
    super 'LINK',number,name,rel_proportion
    @direction = direction
    @has_buses = bus_input == 'Y' # are buses inserted on this link?
    # map from adjacent links, which can be reached from self, 
    # to the used connector
    @adjacent = {}
    @exit = exit
  end
  def adjacent_links; @adjacent.keys; end
  # connects self to given adjacent link by given connector
  def add adj_link,conn
    raise "Link was nil #{to_s}" unless adj_link
    raise "Connector was nil #{to_s}" unless conn
    @adjacent[adj_link] = conn
  end
  # is this link an exit (from the network) link?
  def exit?; @exit; end
  def input?
    # look for links, which have self on the adjacent list
    # if none are found, this is an input link
    ObjectSpace.each_object(Link) do |link|
      return false if link.adjacent_links.include?(self)
    end
    true
  end
  def to_s
    str = super.to_s
    str += ' ' + format('%f', proportion) if @prop > 0
    str += ' ' + @direction if @direction
    str
  end
end
class Connector
  attr_reader :number,:from,:to,:lanes
  def initialize number,from,to,lanes
    @number,@from,@to,@lanes = number,from,to,lanes
  end
end
class Composition < VissimElem
  def initialize number,name,rel_proportion
    super 'COMPOSITION',number,name,rel_proportion
  end
end
class VissimFun
  def VissimFun.get_links area_name
    
    links_map = {}
    ObjectSpace.each_object(Link) do |link|
      links_map[link.number] = link
    end
    
    links = []
    Csvtable.enumerate("#{Vissim_dir}#{area_name}_links.csv") do |row|     
      num = row['number'].to_i
      if links_map.has_key?(num)
        links << links_map[num]
      else
        links << Link.new(
          num, 
          row['name'], 
          row['direction'], 
          row['rel_flow'].to_f, 
          row['bus_input'],
          row['input'] == 'Y')
      end
    end
    links
  end
end

if $0 == __FILE__ 
  puts VissimFun.get_links('herlev')
end