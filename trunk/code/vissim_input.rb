##
# Load an .csv file containing accumulated detections for some period.
# Output strings, which define input in consecutive periods in the Vissim format eg:

#INPUT 1
#     NAME "" LABEL  0.00 0.00
#     LINK 25060309 Q 1000.000 COMPOSITION 1001
#     TIME FROM 0.0 UNTIL 2000.0

require 'csv'
require 'dbi'

Acc_xls = 'D:\greenwaves\data\DOGS Herlev 2007\aggr.xls'

CS = "DBI:ADO:Provider=Microsoft.Jet.OLEDB.4.0;Data Source=#{Acc_xls};Extended Properties=\"Excel 8.0;HDR=Yes;IMEX=1\";"

puts "BEGIN"

DBI.connect(CS) do |dbh|
  sth = dbh.execute(
        "SELECT Time,AVG(Detected) FROM [data] 
         WHERE DoW IN ('Mon','Tue','Wed','Thu','Fri')
         GROUP BY Time")
  sth.each do |row|
    puts row.inspect
  end
  sth.finish
end

puts "END"