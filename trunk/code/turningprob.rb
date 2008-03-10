require 'const'
require 'vissim'
require 'vissim_routes'

def get_vissim_routes

  vissim = Vissim.new("#{Vissim_dir}tilpasset_model.inp")

  routes = get_routes(vissim)

  # join decisions to their successors
  for route in routes
    decisions = route.decisions
    for i in (0...decisions.length-1)
      decisions[i].add_succ decisions[i+1]
    end
  end

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
       WHERE Number IN (1,2,3,4,5)
       GROUP BY Number,[From]"

  decision_points = []

  for row in exec_query(turning_sql)
    isnum = row['Number'].to_i
    from = row['From'][0..0] # extract the first letter of the From
    
    dp = DecisionPoint.new(from,isnum)
    for dec in decisions.find_all{|d| d.intersection == isnum and d.from == from}
      for veh_type in ['Cars','Trucks']
        # set the probability of making this turning decisions 
        # as given in the traffic counts
        # turning_motion must equal L(eft), T(hrough) or R(ight)
        dec.p[veh_type] = row[veh_type + '_' + dec.turning_motion] / row[veh_type + '_TOT'] 
      end
      dp.add dec
    end
    dp.check_prob_assigned # throws a warning if not all flow is assigned to decisions
    decision_points << dp
  end

  routing_decisions = RoutingDecisions.new

  for dp in decision_points
    for veh_type in ['Cars','Trucks']
      dp_link = dp.link # the common starting point for decision in this point
      rd = RoutingDecision.new(dp_link, veh_type)
  
      # add routes to the decision point
      for d_end in dp.decisions
        p = d_end.p[veh_type]
        next if p < EPS
        dest = d_end.connector.to
        #puts "Route from #{dp_link} over #{d_end.connector} with fraction #{d_end.p}"
    
        local_routes = find_routes(dp_link,dest)
    
        raise "Warning: found multiple routes (#{local_routes.length}) from #{dp_link} to #{dest}" if local_routes.length > 1
    
        route = local_routes.first
        rd.add_route(route, p)
      end
  
      routing_decisions.add rd 
    end
  end
  
  # generate bus routes
  input_links = routes.map{|r|r.start}.uniq # collect the set of starting links
  output_links = routes.map{|r|r.exit}.uniq # collect the set of exit links
  
  busplan = exec_query "SELECT BUS, [IN Link], [OUT Link] As OUT, Frequency As FREQ FROM [buses$]"
  businputs = busplan.map{|row| row['IN Link'].to_i}.uniq
  
  busroutemap = {}
  for input_num in businputs
    busroutemap[input_num] = busplan.find_all{|r| r['IN Link'].to_i == input_num}
  end
  
  for input_num,businfo in busroutemap
    input = input_links.find{|l| l.number == input_num}
    output_nums = businfo.map{|i| i['OUT'].to_i}
    outputs = output_links.find_all{|l| output_nums.include? l.number}
    
    busnames = businfo.map{|i| i['BUS']}
    
    rd = RoutingDecision.new(input, 'Buses', "Bus#{busnames.length > 1 ? 'es' : ''} #{busnames.join(', ')}")
    
    freq_sum = businfo.inject(0){|sum,i| sum + i['FREQ']}
    
    for output in outputs
      # find the route which connects this input and output link
      route = routes.find{|r| r.start == input and r.exit == output}
    
      busfreq = businfo.find{|i| i['OUT'].to_i == output.number}['FREQ']
      
      rd.add_route(route, busfreq / freq_sum)
    end
    routing_decisions.add rd
  end

  routing_decisions
end
