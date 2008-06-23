# Script for extraction of cycle times from a vissim test run

require 'const'

SIGNALSQL = 'SELECT DISTINCT simtime,clng(cycsec) as t,sc FROM SIGNALCHANGES WHERE (sc = 4 OR sc = 12) AND cycsec >= 80 ORDER BY simtime'

data = [['Simulation Second', 'Cycle Time','DOGS Area','Test Name']]
['DOGS','Modified DOGS'].each do |test_name|
  resdir = File.join(ENV['TEMP'],"vissim#{test_name.gsub(/\s/,'_').downcase}")
 
  rows = exec_query(SIGNALSQL, "#{CSPREFIX}#{File.join(resdir,'results.mdb')};")
  area_master = {12 => 'Glostrup', 4 => 'Herlev'}
  for row in rows.find_all{|r|r['t'] % 5 == 0}.to_a
    area = area_master[row['sc']]
    data << [row['simtime'].to_i,row['t'],area,test_name]
  end
end

to_xls(data, 'cycle_times', RESULTS_FILE)
