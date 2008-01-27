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
  def Csvtable.enumerate csvfile
    reader = CSV.open(csvfile,'r',';')
    header = reader.shift.map{|title| title.downcase}
    
    reader.each do |row|
      row_map = {}
      row.each_with_index{|e,i| row_map[header[i]] = e}
      yield row_map
    end
    
    reader.close
  end
end

if $0 == __FILE__ 
  #tbl = Csvtable.new "#{Vissim_dir}compositions.csv"
  #puts tbl.header.inspect
  #puts tbl.inspect
  
  Csvtable.enumerate("#{Vissim_dir}herlev_input_links.csv") do |row|
    puts row['number']
  end
end