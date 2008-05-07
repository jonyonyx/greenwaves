require 'network'
require 'vissim'
require 'vissim_routes'
require 'vissim_output'

class RoutingDecisions < Array
  include VissimOutput
  def section_header; /^-- Routing Decisions: --/; end  
  def to_vissim
    str = ''
    each_with_index do |rd,i|
      str << "#{rd.to_vissim(i+1)}"
    end
    str
  end
end
class RoutingDecision
  attr_reader :input_link, :veh_type
  def initialize
    @routes = []
  end
  def add_route route, fractions
    raise "Warning: starting link (#{route.start}) of route was different 
             from the input link of the routing decision(#{@input_link})!" unless route.start == @input_link
      
    raise "Wrong vehicle types detected among fractions, expecting only #{@veh_type}" if fractions.any?{|f| f.veh_type != @veh_type}
    raise "Wrong number of fractions, #{fractions.size}, expected #{@time_intervals.size}\n#{fractions.sort.join("\n")}" unless fractions.size == @time_intervals.size
    @routes << [route, fractions]
  end
  def to_vissim i
    str = "ROUTING_DECISION #{i} NAME \"#{@desc ? @desc : (@veh_type)} from #{@input_link}\" LABEL  0.00 0.00\n"
    # AT must be AFTER the input point
    # place decisions as early as possibly to give vehicles time to changes lanes
    
    str << "     LINK #{@input_link.number} AT #{@input_link.length * 0.1 + 10}\n"
    str << "     TIME #{@time_intervals.sort.map{|int|int.to_vissim}.join(' ')}\n"
    str << "     NODE 0\n"
    str << "      VEHICLE_CLASSES #{Type_map[@veh_type]}\n"
    
    j = 1
    
    for route, fractions in @routes      
      exit_link = route.exit
      # dump vehicles late on the route exit link to avoid placing the destination
      # upstream of the last connector
      str << "     ROUTE     #{j}  DESTINATION LINK #{exit_link.number}  AT   #{exit_link.length * 0.1}\n"
      str << "     #{fractions.sort.map{|f|f.to_vissim}.join(' ')}\n"
      str << "     OVER #{route.to_vissim}\n"
      j += 1
    end
    str
  end
end
def get_vissim_routes vissim

  decisions = vissim.decisions

  turning_sql = "SELECT INTSECT.Number,
                  [From], 
                  [Turning Motion] As TURN, 
                  [Period Start] As TSTART,
                  [Period End] As TEND,
                  Cars, Trucks
                FROM [counts$] As COUNTS
                INNER JOIN [intersections$] As INTSECT
                ON COUNTS.Intersection = INTSECT.Name
                WHERE [Period End] BETWEEN \#1899/12/30 #{PERIOD_START}:00\# AND \#1899/12/30 #{PERIOD_END}:00\#"

  decision_points = []
  
  period_start = Time.parse(PERIOD_START)

  for row in exec_query turning_sql
    isnum = row['Number'].to_i
    from = row['From'][0..0] # extract the first letter of the From

    # see if this decision point was created for a different time slice
    dp = decision_points.find{|x| x.intersection == isnum and x.from_direction == from}
    
    unless dp
      dp = DecisionPoint.new(from,isnum)
      decision_points << dp
    end
    
    # turning_motion must equal L(eft), T(hrough) or R(ight)
    turning_motion = row['TURN'][0..0]
    
    # extract all decisions relevant to this turning count row
    rowdecisions = decisions.find_all{|d| d.intersection == dp.intersection and d.from_direction == dp.from_direction and turning_motion == d.turning_motion}
    
    # find the sum of weights in order to distributed this rows quantity over the relevant decisions
    sum_of_weights = rowdecisions.map{|dec| dec.weight ? dec.weight : 1}.sum    
    
    for dec in rowdecisions    
      for veh_type in Cars_and_trucks_str                
        dec.add_fraction(
          Time.parse(row['TSTART'][-8..-1]) - period_start, 
          Time.parse(row['TEND'][-8..-1]) - period_start, 
          veh_type, 
          (row[veh_type] * (dec.weight ? dec.weight : 1)) / sum_of_weights)
      end
      dp.decisions << dec unless dp.decisions.include?(dec)
    end
  end

  # TODO: add checkup to tell if all flows from the database were assigned to a decision point
 
  routing_decisions = RoutingDecisions.new
  
  # find the local routes from the decision point
  # to the point where the vehicles are dropped off downstream of intersection
  for dp in decision_points
    
    for veh_type in Cars_and_trucks_str
      input_link = dp.link(vissim) # the common starting point for decision in this point
      rd = RoutingDecision.new!(:input_link => input_link, :veh_type => veh_type, :time_intervals => dp.time_intervals)
  
      # add routes to the decision point
      for dec in dp.decisions
        dest = dec.to_link # where vehicles are "dropped off"
    
        # find the route through the intersection (ie. the turning motion)
        local_routes = find_routes(input_link,dest)
        local_route = local_routes.find{|r| r.decisions.include?(dec)}
        raise "No routes from #{input_link} to #{dest} over #{dec}! Found these routes:
               #{local_routes.join("\n")}" if local_route.nil?
            
        rd.add_route(local_route, 
          dec.fractions.find_all{|f| f.veh_type == veh_type})
      end
  
      routing_decisions << rd 
    end
  end
  routing_decisions
end

if __FILE__ == $0  
  puts "BEGIN"
  vissim = Vissim.new
  
  routingdec = get_vissim_routes vissim
  #puts routingdec.to_vissim
  routingdec.write
    
  puts "END"
end