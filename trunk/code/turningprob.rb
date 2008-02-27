require 'const'
require 'vissim'
require 'vissim_routes'
require 'dbi'

vissim = Vissim.new("#{Vissim_dir}tilpasset_model.inp")

#for conn in vissim.conn_map.values.find_all{|conn| conn.is_dp}.sort
#  puts "#{conn.intersection} #{conn.from_direction} #{conn.turning_motion}"
#end

routes = get_routes(vissim,'herlev')

decisions = routes.collect{|r|r.decisions}.flatten.uniq

# enrich decision objects
for dec in decisions
  dec.traversed_by(routes.find_all{|r| r.decisions.include?(dec)})
end

#exit(0)

Plans_file = "../data/counts/counts.xls"
CS = "DBI:ADO:Provider=Microsoft.Jet.OLEDB.4.0;Data Source=#{Plans_file};Extended Properties=\"Excel 8.0;HDR=Yes;IMEX=1\";"

DBI.connect(CS) do |dbh|  
  P_rows = dbh.select_all "SELECT Number, [From], 
        SUM([Cars Left]) / SUM([Total Cars]) AS L,
        SUM([Cars Through]) / SUM([Total Cars]) AS T,
        SUM([Cars Right]) / SUM([Total Cars]) AS R
       FROM [data$] 
       WHERE Number IN (1,2,3,4,5)
       GROUP BY Number,[From]"
end

for row in P_rows
  isnum = row['Number'].to_i
  from = row['From'][0..0] # extract the first letter of the From
  
  sum = 0
  for dec in decisions.find_all{|d| d.intersection == isnum and d.from == from}
    # set the probability of making this turning decisions 
    # as given in the traffic counts
    dec.p = row[dec.turning_motion] # turning_motion must equal L(eft), T(hrough) or R(ight)
    sum += dec.p
  end
  raise "Warning: the sum of turning probabilities for decision point #{from}#{isnum} was #{sum}!" if (sum-1.0).abs > 0.01
end

for dec in decisions.sort
  puts "#{dec}: #{routes.map{|r| dec.traversed_by?(r) ? 1 : 0}.join(' ')} = y * #{dec.p}"
end

puts "Decisions (rows): #{decisions.length}"
puts "Routes (columns): #{routes.length}"