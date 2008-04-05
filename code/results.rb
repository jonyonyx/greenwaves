# 
# collect results from vissim results .mdb file

require 'const'

ttsql = 'SELECT TOP 100
          [Time] As SimSec, 
          [No_] As TTNUM, 
          Veh As VehCnt,
          Trav As TT
         FROM TRAVELTIMES'

File.open('c:\temp\test.csv','w') do |file|
  file << "Simulation Second;Travel Time Number;Vehicles;Travel Time\n"
  for r in exec_query(ttsql, CSRESDB)
    ttnum = r['TTNUM']
    puts ttnum
    file << "#{r['SimSec'].round};#{ttnum};#{r['VehCnt']};#{r['TT'].round}\n"
  end
end