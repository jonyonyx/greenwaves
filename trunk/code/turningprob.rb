require 'const'
require 'vissim'
require 'vissim_routes'
require 'dbi'

vissim = Vissim.new("#{Vissim_dir}tilpasset_model.inp")

routes = get_routes(vissim,'Herlev')

for route in routes
  decisions = route.decisions
  for i in (0...decisions.length)
    decisions[i].add_succ decisions[i+1]
  end
end

decisions = routes.collect{|r|r.decisions}.flatten.uniq 

Turning_sql = "SELECT Number, [From], 
        SUM([Cars Left]) As CARS_L,
        SUM([Cars Through]) As CARS_T,
        SUM([Cars Right]) As CARS_R,
        SUM([Total Cars]) As CARS_TOT
       FROM [counts$] 
       WHERE Number IN (1,2,3,4,5)
       GROUP BY Number,[From]"

for row in exec_query(Turning_sql)
  isnum = row['Number'].to_i
  from = row['From'][0..0] # extract the first letter of the From
    
  sum = 0
  for dec in decisions.find_all{|d| d.intersection == isnum and d.from == from}
    # set the probability of making this turning decisions 
    # as given in the traffic counts
    # turning_motion must equal L(eft), T(hrough) or R(ight)
    dec.p = row['CARS_' + dec.turning_motion] / row['CARS_TOT'] 
    sum += dec.p
  end
  raise "Warning: the sum of turning probabilities for decision point #{from}#{isnum} was #{sum}!" if (sum-1.0).abs > 0.01
end

for dec in decisions.sort
  puts "#{dec} #{format('%02f %02f',dec.flow,dec.p)}: #{dec.successors.join(' ')}"
end

puts "Found #{decisions.length} decisions in #{routes.length} routes"
