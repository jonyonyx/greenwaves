##
# Load an .csv file containing accumulated detections for some period.
# Output strings, which define input in consecutive periods in the Vissim format (see below)


require 'csv'
require 'dbi'
require 'Win32API'
require 'win32/clipboard' 
include Win32

Acc_xls = 'D:\greenwaves\data\DOGS Herlev 2007\aggr.xls'
CS = "DBI:ADO:Provider=Microsoft.Jet.OLEDB.4.0;Data Source=#{Acc_xls};Extended Properties=\"Excel 8.0;HDR=Yes;IMEX=1\";"

Input_factor = 5

puts "BEGIN"
  
# Load the file containing input link definitions
  
reader = CSV.open('..\Vissim\o3_roskildevej-herlevsygehus\herlev_input_links.csv','r',';')
header = reader.shift
  
class Link
  attr_reader :number,:name,:direction
  @@total_flow = 0.0
  def initialize number,name,direction,rel_flow
    @number,@name,@direction,@rel_flow = number,name,direction,rel_flow
    @@total_flow = @@total_flow + rel_flow
  end
  def is_major?
    # for both herlev and glostrup the major road
    # has traffic in north- and southgoing directions
    ['N','S'].include? @direction
  end
  def percentage
    @rel_flow / @@total_flow
  end
  def to_s
    "#{@number} #{@direction} #{format('%f', percentage)} #{@name}"
  end
end
  
Links = []
  
for row in reader
  Links << Link.new(row[0].to_i,row[1],row[2],row[3].to_f)
end
 
# print the links ordered by direction
for link in Links.sort{|l1,l2| l1.direction <=> l2.direction}
  puts link
end

# fetch historical traffic input data in 15m granularity
DBI.connect(CS) do |dbh|  
  Input_rows = dbh.select_all "SELECT HOUR(Time) AS H, MINUTE(Time) AS M, AVG(Detected) AS Q FROM [data] 
         WHERE DoW IN ('Mon','Tue','Wed','Thu','Fri') AND
               Time BETWEEN \#1899/12/30 07:00:00\# AND \#1899/12/30 08:00:00\#
         GROUP BY Time"  
end
  
Time_fmt = '%02d:%02d:00'
  
# FORMAT EXAMPLE:
  
#INPUT 1
#     NAME "" LABEL  0.00 0.00
#     LINK 25060309 Q 1000.000 COMPOSITION 1001
#     TIME FROM 0.0 UNTIL 2000.0
  
elapsed = 0.0 # simulation seconds
step = 15*60

input_num = 1
output_string = ''
# iterate over the detected data by period...
Input_rows[1..-1].each_with_index do |row,n|
  input_begin_time = format(Time_fmt,Input_rows[n]['H'],Input_rows[n]['M'])
  input_end_time = format(Time_fmt,row['H'],row['M'])
  
  #... for each link generate input in this period
  for link in Links
    
    flow = row['Q']    
    link_contrib = flow * link.percentage * Input_factor
    
    output_string = output_string +  "\nINPUT #{input_num}\n" +
      "      NAME \"From #{input_begin_time} to #{input_end_time}\" LABEL  0.00 0.00\n" +
      "      LINK #{link.number} Q #{link_contrib} COMPOSITION 1001\n" +
      "      TIME FROM #{elapsed} UNTIL #{elapsed+step}"
    input_num = input_num + 1
  end
  elapsed = elapsed + step
end

Clipboard.set_data output_string

puts "Link Input Data has been placed on the clipboard"

puts "END"