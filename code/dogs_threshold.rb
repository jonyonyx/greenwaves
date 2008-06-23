# scripts for finding suitable dogs threshold values
# for vehicle counts and possibly detector load percentages
# INCOMPLETE
 
require 'const'

def get_thresholds(detectors)

  acc_xls = "#{Herlev_dir}aggr.xls"
  aggr_CS = "DBI:ADO:Provider=Microsoft.Jet.OLEDB.4.0;Data Source=#{acc_xls};Extended Properties=\"Excel 8.0;HDR=Yes;IMEX=1\";"

  # fetch historical traffic input data in 15m granularity
  rows = exec_query "SELECT AVG(Detected) As Q 
         FROM [data$] 
         WHERE DoW IN ('Mon','Tue','Wed','Thu','Fri') AND 
         Detector IN ('#{detectors.join("', '")}') AND
         Time BETWEEN \#1899/12/30 07:00:00\# AND \#1899/12/30 09:00:00\#
         GROUP BY Time" , aggr_CS
  
  q = rows.map{|r| r['Q']}
  
 # puts "#{detectors.join(',')}: [#{q.min},#{q.max}]"
  ubounds,lbounds = [],[]
  q.min.step(q.max, (q.max - q.min) / (DOGS_LEVELS.to_f - 1)) do |bound| # sum over 15min
    # scale down to match a BASE_CYCLE_TIME period
    ub = (bound * BASE_CYCLE_TIME / (Res*60.0)).round
    ubounds << ub
    # set lower bound 10% below upper bound to avoid hystereses ie. rapid changing 
    # between adjacent dogs levels!
    lbounds << (ub - DOGS_LEVELDOWN_BUFFER*ub).round 
  end
  [ubounds,lbounds]
end

if __FILE__ == $0
  puts get_thresholds(['D3']).inspect
end

