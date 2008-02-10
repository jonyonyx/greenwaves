##
# Load an .csv file containing accumulated detections for some period.
# Output strings, which define input in consecutive periods in the Vissim format (see below)

require 'const'
require 'dbi'

Acc_xls = "#{Herlev_dir}aggr.xls"
CS = "DBI:ADO:Provider=Microsoft.Jet.OLEDB.4.0;Data Source=#{Acc_xls};Extended Properties=\"Excel 8.0;HDR=Yes;IMEX=1\";"

Input_factor = 1 # factor used to boost all input sizes

puts "BEGIN"
    
Links = VissimFun.get_links('herlev','input')

# fetch historical traffic input data in 15m granularity
DBI.connect(CS) do |dbh|  
  Input_rows = dbh.select_all "SELECT HOUR(Time) AS H, MINUTE(Time) AS M, AVG(Detected) AS Q FROM [data] 
         WHERE DoW IN ('Mon','Tue','Wed','Thu','Fri') AND
               Time BETWEEN \#1899/12/30 07:00:00\# AND \#1899/12/30 08:00:00\#
         GROUP BY Time"  
end

#puts Input_rows[0]['Q']
#exit(0)
  
Time_fmt = '%02d:%02d:00'
    
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
    # choose a composition (all links have cars!)
    
    # please refer to the -- Traffic Compositions: -- section
    # in the .inp file for the numbers
    if link.has_buses
      if link.has_trucks
        comp = 1 # buses and trucks
      else
        comp = 3 # buses, no trucks
      end
    else
      if link.has_trucks
        # trucks, no buses
        comp = 2
      else
        # no buses, no trucks
        comp = 1001
      end
    end
    
    flow = row['Q']    
    # link inputs in Vissim is defined in veh/h
    link_contrib = flow * (60/Res) * link.proportion * Input_factor
    
    output_string = output_string +  "INPUT #{input_num}\n" +
      "      NAME \"Direction #{link.direction} on #{link.name} (#{input_begin_time}-#{input_end_time})\" LABEL  0.00 0.00\n" +
      "      LINK #{link.number} Q #{link_contrib} COMPOSITION #{comp}\n" +
      "      TIME FROM #{elapsed} UNTIL #{elapsed+step}\n"
    input_num = input_num + 1
  end
  elapsed = elapsed + step
end

Clipboard.set_data output_string

puts "Link Input Data has been placed on your clipboard."

puts "END"