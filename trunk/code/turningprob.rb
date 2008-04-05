require 'network'
require 'vissim_routes'

def get_vissim_routes vissim

  routes = get_full_routes vissim

  # join decisions to their successors
#  for route in routes
#    decisions = route.decisions
#    for i in (0...decisions.length-1)
#      decisions[i].add_succ decisions[i+1]
#    end
#  end

  decisions = routes.collect{|r|r.decisions}.flatten.uniq 

  turning_sql = "SELECT Number, [From], 
        SUM([Cars Left]) As Cars_L,
        SUM([Cars Through]) As Cars_T,
        SUM([Cars Right]) As Cars_R,
        SUM([Total Cars]) As Cars_TOT,
        SUM([Trucks Left]) As Trucks_L,
        SUM([Trucks Through]) As Trucks_T,
        SUM([Trucks Right]) As Trucks_R,
        SUM([Total Trucks]) As Trucks_TOT
       FROM [counts$] 
       GROUP BY Number,[From]"

  decision_points = []

  for row in exec_query turning_sql
    isnum = row['Number'].to_i
    from = row['From'][0..0] # extract the first letter of the From
        
    dp = DecisionPoint.new(from,isnum)
    for dec in decisions.find_all{|d| d.intersection == isnum and d.from == from}
      #puts dec
      for veh_type in Cars_and_trucks_str
        # set the probability of making this turning decisions 
        # as given in the traffic counts
        # turning_motion must equal L(eft), T(hrough) or R(ight)
        dec.p[veh_type] = row["#{veh_type}_#{dec.turning_motion}"] / row["#{veh_type}_TOT"] 
      end
      dp.add dec
    end
    dp.check_prob_assigned # throws a warning if not all flow is assigned to decisions
    decision_points << dp
  end

  routing_decisions = RoutingDecisions.new

  # find the local routes from the decision point
  # to the point where the vehicles are dropped off downstream of intersection
  for dp in decision_points
    for veh_type in Cars_and_trucks_str
      dp_link = dp.link # the common starting point for decision in this point
      rd = RoutingDecision.new(dp_link, veh_type)
  
      # add routes to the decision point
      for d_end in dp.decisions
        p = d_end.p[veh_type]
        next if p < EPS
        dest = d_end.connector.to
        #puts "Route from #{dp_link} over #{d_end.connector} with fraction #{d_end.p}"
    
        local_routes = find_routes dp_link,dest
    
        raise "Warning: found multiple routes (#{local_routes.length}) from #{dp_link} to #{dest}" if local_routes.length > 1
        raise "Warning: no routes from #{dp_link} to #{dest}!" if local_routes.empty?
        
        route = local_routes.first
        rd.add_route route, p
      end
  
      routing_decisions.add rd 
    end
  end

  routing_decisions
end

