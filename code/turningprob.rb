require 'const'
require 'dbi'

Count_xls = "../data/counts/counts.xls"
CS = "DBI:ADO:Provider=Microsoft.Jet.OLEDB.4.0;Data Source=#{Count_xls};Extended Properties=\"Excel 8.0;HDR=Yes;IMEX=1\";"

SQL = "SELECT Intersection, [From], 
        SUM([Cars Left]) / SUM([Total Cars]) AS L,
        SUM([Cars Through]) / SUM([Total Cars]) AS T,
        SUM([Cars Right]) / SUM([Total Cars]) AS R
       FROM [data$] 
       GROUP BY Intersection,[From]"

DBI.connect(CS) do |dbh|  
  Count_rows = dbh.select_all SQL  
end

for row in Count_rows
  puts "'#{row['Intersection']}' #{row['From'][0..0]}: "  + 
       format('%f %f %f',row['L'],row['T'],row['R'])
  sum = row['L']+row['T']+row['R']
  raise "Warning: this rows turning probabilities summed to #{sum}!" if (sum-1.0).abs > 0.01
end
