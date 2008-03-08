require 'const'
require 'vissim'
require 'vissim_routes'
require 'dbi'

vissim = Vissim.new("#{Vissim_dir}tilpasset_model.inp")

routes = get_routes(vissim,nil)

# join decisions to their successors
for route in routes
  decisions = route.decisions
  for i in (0...decisions.length-1)
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

decision_points = []

for row in exec_query(Turning_sql)
  isnum = row['Number'].to_i
  from = row['From'][0..0] # extract the first letter of the From
    
  dp = DecisionPoint.new(from,isnum)
  for dec in decisions.find_all{|d| d.intersection == isnum and d.from == from}
    # set the probability of making this turning decisions 
    # as given in the traffic counts
    # turning_motion must equal L(eft), T(hrough) or R(ight)
    dec.p = row['CARS_' + dec.turning_motion] / row['CARS_TOT'] 
    dp.add dec
  end
  dp.check_prob_assigned # throws a warning if not all flow is assigned to decisions
  decision_points << dp
end


#decision_points[0].link
#exit(0)

routing_decisions = []

# 
for dp in decision_points
  puts "finding link for #{dp}"
  dp_link = dp.link # the common starting point for decision in this point
  rd = RoutingDecision.new(dp_link,1001)  
  puts "found dp link: #{dp_link}"
  
  # add routes to the decision point
  for d_end in dp.decisions
    dest = d_end.connector.to
    puts "Route from #{dp_link} over #{d_end.connector} with fraction #{d_end.p}"
    
    local_routes = find_routes(dp_link,dest)
    
    raise "Warning: found multiple routes (#{local_routes.length}) from #{dp_link} to #{dest}" if local_routes.length > 1
    
    route = local_routes.first
    rd.add_route(route, d_end.p)
  end
  
  routing_decisions << rd 
end

puts routing_decisions

str = routing_decisions.sort.find_all{|rd| rd.composition != 1003}.map{|rd| rd.to_vissim}.join("\n")
  
puts str

Clipboard.set_data str
puts "Please find the Routing Decisions on your clipboard."
