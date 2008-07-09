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
    unless fractions.size == @time_intervals.size
      raise "Wrong number of fractions, #{fractions.size}, " +
        "expected #{@time_intervals.size}\n#{fractions.sort.join("\n")}\n#{route}\n#{@time_intervals.join("\n")}" 
    end
    @routes << [route, fractions]
  end
  def tbegin
    @time_intervals.min.tstart
  end
  def to_vissim i
    str = "ROUTING_DECISION #{i} NAME \"#{@desc ? @desc : (@veh_type.to_s.capitalize)} from #{@input_link}\" LABEL  0.00 0.00\n"
    # AT must be AFTER the input point
    # place decisions as early as possibly to give vehicles time to changes lanes
    
    str << "     LINK #{@input_link.number} AT 5.0\n"
    str << "     TIME #{@time_intervals.sort.map{|int|int.to_vissim(tbegin)}.join(' ')}\n"
    str << "     NODE 0\n"
    str << "      VEHICLE_CLASSES #{Type_map[@veh_type]}\n"
    
    j = 1
    
    for route, fractions in @routes      
      exit_link = route.exit
      # dump vehicles late on the route exit link to avoid placing the destination
      # upstream of the last connector
      str << "     ROUTE     #{j}  DESTINATION LINK #{exit_link.number}  AT   #{exit_link.exit? ? (exit_link.length - 5.0) : 4.0}\n"
      str << "     #{fractions.sort.join_by(:to_vissim,' ')}\n"
      str << "     OVER #{route.to_vissim}\n"
      j += 1
    end
    str
  end
end

class Vissim
  def get_routing_decisions program
  
    decisions = @decisions.find_all do |dec| 
      not dec.disable_route? and 
        dec.fractions.any?{|fraction|program.interval === fraction.interval.tstart}
    end
  
    routing_decisions = RoutingDecisions.new
  
    decision_points = []
    
    decisions.group_by{|dec|dec.decide_at_intersection}.each do |intersection,intersection_decisions|
      intersection_decisions.group_by{|dec|dec.decide_from_direction}.each do |from_direction,approach_decisions|
        dp = DecisionPoint.new(from_direction,intersection)
        approach_decisions.each{|dec|dp << dec}
        decision_points << dp
      end      
    end
  
    # find the local routes from the decision point
    # to the point where the vehicles are dropped off downstream of intersection
    decision_points.sort.each do |dp|
      decision_link = dp.link(self)
    
      for veh_type in [:cars,:trucks]
        rd = RoutingDecision.new!(
          :input_link => decision_link, 
          :veh_type => veh_type, 
          :time_intervals => dp.time_intervals(program))
  
        # add routes to the decision point
        for dec in dp
          dest = dec.drop_link
    
          # find the route through the intersection (ie. the turning motion)
          local_routes = find_routes(decision_link,dest)
          local_route = local_routes.find{|r| r.decisions.include?(dec)}
          raise "No routes from #{decision_link} to #{dest} over #{dec} among these routes:
               \n#{local_routes.map{|lr|lr.to_vissim}.join("\n")}" if local_route.nil?
                
          fractions = dec.fractions.find_all do |fraction| 
            fraction.veh_type == veh_type and
              program.interval === fraction.interval.tstart
          end
        
          if program.repeat_first_interval
            first_fraction = dec.fractions.find_all{|f|f.veh_type == veh_type and program.interval === f.interval.tstart}.min_by{|f|f.interval}
          
            raise "Fractions at #{dec}:\n#{fractions.join("\n")}" unless first_fraction
            
            new_first_fraction = first_fraction.copy
            new_first_fraction.interval.shift!(-program.resolution_in_seconds)
          
            fractions << new_first_fraction
          end
          rd.add_route(local_route, fractions)
        end
  
        routing_decisions << rd 
      end
    
    end
  
    routing_decisions
  end
end

if __FILE__ == $0  
  puts "BEGIN"
  
  require 'cowi_tests'
  network = 'C:\projects\62832\test_scenarios\scenario_basis_eftermiddag\amagermotorvejen_avedore-havnevej.inp'
  vissim = Vissim.new network
  
  rds = vissim.get_routing_decisions AFTERNOON
  #puts rds.to_vissim
  rds.write network
    
  puts "END"
end