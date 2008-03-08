# scripts for finding suitable dogs threshold values
# for vehicle counts and possibly detector load percentages
 
require 'const'

puts "BEGIN"

DOGS_LEVELS = 8
DOGS_LEVELDOWN_BUFFER = 0.1 # percentage of threshold value for current level
BASE_CYCLE_TIME = 80 # seconds

Acc_xls = "#{Herlev_dir}aggr.xls"
Aggr_CS = "DBI:ADO:Provider=Microsoft.Jet.OLEDB.4.0;Data Source=#{Acc_xls};Extended Properties=\"Excel 8.0;HDR=Yes;IMEX=1\";"


th = {}

for det in [['D3'],['D14']]#[0..0]  
  # fetch historical traffic input data in 15m granularity
  rows = exec_query "SELECT AVG(Detected) As Q 
         FROM [data$] 
         WHERE DoW IN ('Mon','Tue','Wed','Thu','Fri') AND 
         Detector IN ('#{det.join("', '")}') AND
         Time BETWEEN \#1899/12/30 07:00:00\# AND \#1899/12/30 09:00:00\#
         GROUP BY Time" , Aggr_CS
  
  q = rows.map{|r| r['Q']}
  
  puts "#{det.join(',')}: [#{q.min},#{q.max}]"
  
  ubound_ar = []
  lbound_ar = []
  th[det] = {'UBOUND' => ubound_ar, 'LBOUND' => lbound_ar}
  q.min.step(q.max, (q.max - q.min) / (DOGS_LEVELS.to_f - 1)) do |bound| # sum over 15min
    # scale down to match a BASE_CYCLE_TIME period
    ub = (bound * BASE_CYCLE_TIME / (Res*60.0)).round
    ubound_ar << ub
    # set lower bound 10% below upper bound to avoid hystereses ie. rapid changing 
    # between adjacent dogs levels!
    lbound_ar << (ub - 0.1*ub).round 
  end
end

print ['UBOUND','LBOUND'].map{|btype| "\t#{btype}_CNT_CRIT [2,#{DOGS_LEVELS}] = " + th.values.map{|h| h[btype]}.inspect}.join(",\n"),";"


