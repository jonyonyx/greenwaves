require 'network'
require 'vissim_routes'

def get_vissim_routes vissim

  # find all relevant ie. reacheable decisions in the network
  # a decision is reacheable if it is traversed by a full route
  # ie. a route, which starts at an input link and exits the network on completion
  decisions = vissim.conn_map.values.map{|c|c.dec} - [nil]

  turning_sql = "SELECT INTSECT.Number,
                  [From], 
                  [Turning Motion] As TURN, 
                  [Period Start] As TSTART,
                  [Period End] As TEND,
                  Cars, Trucks
                FROM [vd_data$] As COUNTS
                INNER JOIN [intersections$] As INTSECT
                ON COUNTS.Intersection = INTSECT.Name
                WHERE [Period End] BETWEEN \#1899/12/30 #{PERIOD_START}:00\# AND \#1899/12/30 #{PERIOD_END}:00\#"

  decision_points = []
  
  period_start = Time.parse(PERIOD_START)

  for row in exec_query turning_sql
    isnum = row['Number'].to_i
    from = row['From'][0..0] # extract the first letter of the From

    # see if this decision point was created for a different time slice
    dp = decision_points.find{|x| x.intersection == isnum and x.from == from}
    
    unless dp
      dp = DecisionPoint.new(from,isnum)
      decision_points << dp
    end
    
    # turning_motion must equal L(eft), T(hrough) or R(ight)
    turning_motion = row['TURN'][0..0]
    
    for dec in decisions.find_all{|d| d.intersection == dp.intersection and d.from == dp.from and turning_motion == d.turning_motion}
      for veh_type in Cars_and_trucks_str                
        dec.add_fraction(
          Time.parse(row['TSTART'][-8..-1]) - period_start, 
          Time.parse(row['TEND'][-8..-1]) - period_start, 
          veh_type, row[veh_type])
      end
      dp.add(dec) unless dp.decisions.include?(dec)
    end
  end

  # TODO: add checkup to tell if all flows from the database were assigned to a decision point
 
  routing_decisions = RoutingDecisions.new
  
  # find the local routes from the decision point
  # to the point where the vehicles are dropped off downstream of intersection
  for dp in decision_points
    
    for veh_type in Cars_and_trucks_str
      input_link = dp.link # the common starting point for decision in this point
      rd = RoutingDecision.new!(:input_link => input_link, :veh_type => veh_type, :time_intervals => dp.time_intervals)
  
      # add routes to the decision point
      for dec in dp.decisions
        dest = dec.connector.to # where vehicles are "dropped off"
    
        # find the route through the intersection (ie. the turning motion)
        local_route = find_routes(input_link,dest).find{|r| r.decisions.include?(dec)}
        raise "No routes from #{input_link} to #{dest}!" if local_route.nil?
            
        rd.add_route(
          local_route, 
          dec.fractions.find_all{|f| f.veh_type == veh_type}
        )
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
  #puts routingdec.to_vissim
    
  puts "END"
end