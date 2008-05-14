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

  turning_sql = "SELECT INTSECT.number,
                  [from], 
                  [Turning Motion] As turn, 
                  [Period Start] As tstart,
                  [Period End] As tend,
                  cars, trucks
                FROM [counts$] As COUNTS
                INNER JOIN [intersections$] As INTSECT
                ON COUNTS.Intersection = INTSECT.Name
                WHERE [Period End] BETWEEN \#1899/12/30 #{PERIOD_START}:00\# AND \#1899/12/30 #{PERIOD_END}:00\#"

  decisions = []
  DB[turning_sql].all.map do |row|
    isnum = row[:number].to_i
    from_direction = row[:from][0..0] # extract the first letter (N, S, E or W)    
    turning_motion = row[:turn][0..0] # turning_motion must equal L(eft), T(hrough) or R(ight)
    
    # extract all decisions relevant to this turning count row
    rowdecisions = vissim.decisions.find_all do |d| 
      d.intersection == isnum and 
        d.from_direction == from_direction and 
        turning_motion == d.turning_motion
    end
    
    # find the sum of weights in order to distributed this rows quantity over the relevant decisions
    sum_of_weights = rowdecisions.map{|dec| dec.weight || 1}.sum
    
    for dec in rowdecisions
      for veh_type in Cars_and_trucks_str
        vehicles = row[veh_type.downcase.to_sym] * (dec.weight || 1) / sum_of_weights
        dec.add_fraction(
          Time.parse(row[:tstart][-8..-1]) - START_TIME, 
          Time.parse(row[:tend][-8..-1]) - START_TIME, 
          veh_type, vehicles)
      end
      #puts dec, row.inspect if dec.from_direction == 'E' and dec.intersection == 1
      decisions << dec unless decisions.include?(dec)
    end
  end

  # TODO: add checkup to tell if all flows from the database were assigned to a decision point
 
  routing_decisions = RoutingDecisions.new
  
  # find the local routes from the decision point
  # to the point where the vehicles are dropped off downstream of intersection
  # 
  #.find_all{|dp|dp.intersection == 1 and dp.from_direction == 'S'}
  decisions.map{|dec|dec.decision_point}.uniq.sort.each do |dp|
    decision_link = dp.link(vissim)
    #puts "Decision taken at: #{decision_link}"
#    puts dp
    
    for veh_type in Cars_and_trucks_str[0..0]
      rd = RoutingDecision.new!(:input_link => decision_link, :veh_type => veh_type, :time_intervals => dp.time_intervals)
  
      # add routes to the decision point
      for dec in dp.decisions
#        puts "  #{dec} drop at #{dec.drop_link}"
        dest = dec.drop_link
    
        # find the route through the intersection (ie. the turning motion)
        local_routes = vissim.find_routes(decision_link,dest)
        local_route = local_routes.find{|r| r.decisions.include?(dec)}
        raise "No routes from #{decision_link} to #{dest} over #{dec} among these routes:
               #{local_routes.map{|lr|lr.to_vissim}.join("\n")}" if local_route.nil?
        
#        for ldec in local_route.decisions
#          puts "    passing #{ldec}"
#        end
        
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