require 'network'
require 'vissim_routes'

def get_vissim_routes vissim

  routes = get_full_routes vissim

  decisions = routes.collect{|r|r.decisions}.flatten.uniq

  turning_sql = "SELECT INSECTS.Number, [From], 
        SUM([Cars Left]) As Cars_L,
        SUM([Cars Through]) As Cars_T,
        SUM([Cars Right]) As Cars_R,
        SUM([Total Cars]) As Cars_TOT,
        SUM([Trucks Left]) As Trucks_L,
        SUM([Trucks Through]) As Trucks_T,
        SUM([Trucks Right]) As Trucks_R,
        SUM([Total Trucks]) As Trucks_TOT
       FROM [counts$] As COUNTS
       INNER JOIN [intersections$] As INSECTS
       ON COUNTS.Intersection = INSECTS.Name
       WHERE [Period End] BETWEEN \#1899/12/30 #{PERIOD_START}:00\# AND \#1899/12/30 #{PERIOD_END}:00\#
       GROUP BY Number,[From]"

  decision_points = []

  for row in exec_query turning_sql
    puts row.inspect
    isnum = row['Number'].to_i
    from = row['From'][0..0] # extract the first letter of the From
        
    dp = DecisionPoint.new(from,isnum)
    for dec in decisions.find_all{|d| d.intersection == isnum and d.from == from}
      puts dec
      for veh_type in Cars_and_trucks_str
        # set the probability of making this turning decisions 
        # as given in the traffic counts
        # turning_motion must equal L(eft), T(hrough) or R(ight)
        
        q_turning_motion = row["#{veh_type}_#{dec.turning_motion}"]
        
        next unless q_turning_motion
        
        dec.p[veh_type] = q_turning_motion / row["#{veh_type}_TOT"] 
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
    
        raise "Found multiple routes (#{local_routes.length}) from #{dp_link} to #{dest}" if local_routes.length > 1
        raise "No routes from #{dp_link} to #{dest}!" if local_routes.empty?
        
        route = local_routes.first
        rd.add_route route, p
      end
  
      routing_decisions << rd 
    end
  end

  routing_decisions
end

if __FILE__ == $0  
  puts "BEGIN"
  vissim = Vissim.new(Default_network)
  
  routingdec = get_vissim_routes vissim
  
  puts routingdec.to_vissim
  
  puts "END"
end