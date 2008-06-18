
require 'const'

SIGNALSQL = 'SELECT link, t, avg(volume__0_) as volume FROM LINK_EVAL GROUP BY link,t'

approach_names = {  
  48131190 => 'Herlev Hovedgade from East',
  48131194 => 'Herlev Bygade to Herlev Hovedgade',
  48131212 => 'Herlev Hovedgade to Herlev Bygade',
  48131198 => 'Herlev Hovedgade from West',
  48131202 => 'Herlev Hovedgade from South'
}

data = [['Approach', 'Simulation Second','Volume']]
['DOGS','Modified DOGS'].each do |test_name|
  resdir = File.join(ENV['TEMP'],"vissim#{test_name.gsub(/\s/,'_').downcase}")
 
  rows = exec_query(SIGNALSQL, "#{CSPREFIX}#{File.join(resdir,'results.mdb')};")
  
  for row in rows
    link = row['link'].to_i
    next unless approach_names.has_key?(link)
    data << [approach_names[link] || link,row['t'].to_i,row['volume'].round]
  end
end

#for row in data
#  puts row.inspect
#end

to_xls(data, 'data', File.join('c:','greenwaves','results','link_evals.xls'))
