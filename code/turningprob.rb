require 'const'
require 'dbi'

Count_xls = "../data/tællinger/counts.xls"
CS = "DBI:ADO:Provider=Microsoft.Jet.OLEDB.4.0;Data Source=#{Count_xls};Extended Properties=\"Excel 8.0;HDR=Yes;IMEX=1\";"

DBI.connect(CS) do |dbh|  
  Count_rows = dbh.select_all "SELECT * FROM [data$]"  
end

puts Count_rows.inspect