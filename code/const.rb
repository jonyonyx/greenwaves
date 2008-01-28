# 
# To change this template, choose Tools | Templates
# and open the template in the editor.
 
require 'csv'

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
end

class Link < VissimElem
  attr_reader :direction,:has_buses,:connectors,:adjacent
  def initialize number,name,direction,rel_proportion = 0.0, bus_input = 'N'
    super 'LINK',number,name,rel_proportion
    @direction = direction
    @has_buses = bus_input == 'Y' # are buses inserted on this link?
    @adjacent = [] # list of links, which can be reached from self
  end
  def add adj_link
    raise "Link was nil #{to_s}" unless adj_link
    @adjacent << adj_link
  end
  # is this link an exit (from the network) link?
  def exit?; @adjacent.empty?; end
  def to_s
    str = super.to_s
    str += ' ' + format('%f', proportion) if @prop > 0
    str += ' ' + @direction if @direction
    str
  end
end
class Composition < VissimElem
  def initialize number,name,rel_proportion
    super 'COMPOSITION',number,name,rel_proportion
  end
end
class VissimFun
  def VissimFun.get_links area_name
    links = []
    Csvtable.enumerate("#{Vissim_dir}#{area_name}_input_links.csv") do |row|
      links << Link.new(
        row['number'].to_i, 
        row['name'], 
        row['direction'], 
        row['rel_flow'].to_f, 
        row['bus_input'])
    end
    links
  end
end

if $0 == __FILE__ 
  puts VissimFun.get_links('herlev')
end