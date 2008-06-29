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
    raise "Wrong number of fractions, #{fractions.size}, expected #{@time_intervals.size}\n#{fractions.sort.join("\n")}\n#{route}" unless fractions.size == @time_intervals.size
    @routes << [route, fractions]
  end
  def tbegin
    @time_intervals.min.tstart
  end
  def to_vissim i
    str = "ROUTING_DECISION #{i} NAME \"#{@desc ? @desc : (@veh_type.to_s.capitalize)} from #{@input_link}\" LABEL  0.00 0.00\n"
    # AT must be AFTER the input point
    # place decisions as early as possibly to give vehicles time to changes lanes
    
    str << "     LINK #{@input_link.number} AT #{@input_link.length * 0.1 + 10}\n"
    str << "     TIME #{@time_intervals.sort.map{|int|int.to_vissim(tbegin)}.join(' ')}\n"
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

# SQL for extracting traffic count information for turning ratios
# note there are two placeholders: PERIOD_START and PERIOD_END, which 
# must be substituted by a time-of-day value such as 7:00 or 15:00
TURNING_SQL = "SELECT clng(INTSECT.number) as intersection_number,
                  from_direction, to_direction,
                  [Turning Motion] As turn, 
                  [Period Start] As tstart,
                  [Period End] As tend,
                  cars, trucks
                FROM [counts$] As COUNTS
                INNER JOIN [intersections$] As INTSECT
                ON COUNTS.Intersection = INTSECT.Name
                WHERE [Period End] BETWEEN \#1899/12/30 PERIOD_START:00\# AND \#1899/12/30 PERIOD_END:00\#
                AND NOT IsNull(to_direction)"

class Stream
  attr_reader :from, :to, :intersection, :traffic # eg N / S / E / W
  
  def initialize from,to,intersection,turning_motion
    @from,@to,@intersection = from,to,intersection
    @turning_motion = turning_motion
    @traffic = Hash.new {|h,k| h[k] = {}} # period => veh_type => quantity
  end
  
  def turning_motion
    @turning_motion
  end
  
  def approach
    "#{@from}#{@intersection}"
  end
  
  def add_fraction tstart, tend, cars, trucks
    period = Interval.new(tstart,tend)
    @traffic[period][:cars] = cars
    @traffic[period][:trucks] = trucks
  end
  
  def get_traffic(period, veh_type, volume)
    vehicles = @traffic[period][veh_type]
    if volume > vehicles
      @traffic[period][veh_type] = 0 # stream was drained
      return vehicles # he gets the rest
    else
      @traffic[period][veh_type] -= volume # got what he asked for      
    end
    volume # got what he wanted
  end
  
  def to_s
    "#{@from}#{@intersection}#{@turning_motion}"
  end
end

def print_streams streams
  streams.each do |s|
    puts s
    s.traffic.keys.sort.each do |period|
      puts "\t#{period}: #{s.traffic[period]}"
    end
  end
end
# helper-classes for Decision
class Interval
  attr_reader :tstart, :tend
  def initialize tstart,tend
    @tstart,@tend = tstart,tend    
  end
  def shift(seconds)
    @tstart += seconds
    @tend += seconds
  end
  def copy
    Interval.new(@tstart,@tend)
  end
  def to_vissim(tbegin); "FROM #{@tstart - tbegin} UNTIL #{@tend - tbegin}"; end
  def to_s; "#{@tstart.to_hm} to #{@tend.to_hm}"; end
  def <=>(i2); @tstart <=> i2.tstart; end
end
class Fraction
  attr_reader :interval, :veh_type, :quantity
  def copy
    Fraction.new!(:interval => @interval.copy,:veh_type => @veh_type,:quantity => @quantity)
  end
  def <=>(f2); @interval <=> f2.interval; end
  def to_s; "Fraction from #{@interval} = #{quantity} #{@veh_type}"; end
  def to_vissim; "FRACTION #{@quantity}";end
end

def get_routing_decisions vissim, program
  
  decisions = vissim.decisions.find_all do |dec| 
    dec.fractions.any?{|fraction|program.interval === fraction.interval.tstart}
  end
    
  routing_decisions = RoutingDecisions.new
  
  decision_points = []
  decisions.each do |dec|
    dp = decision_points.find do |dp|
      dp.from_direction == dec.decide_from_direction and 
        dp.intersection == dec.decide_at_intersection
    end
    
    # create new dp, if no other decision created it before
    if dp.nil?
      dp = DecisionPoint.new(dec.decide_from_direction,dec.decide_at_intersection)
      decision_points << dp
    end
    dp.decisions << dec
  end
    
  # find the local routes from the decision point
  # to the point where the vehicles are dropped off downstream of intersection
  decision_points.sort.each do |dp|
    decision_link = dp.link(vissim)
    
    for veh_type in [:cars,:trucks]
      rd = RoutingDecision.new!(:input_link => decision_link, :veh_type => veh_type, :time_intervals => dp.time_intervals)
  
      # add routes to the decision point
      for dec in dp.decisions
        dest = dec.drop_link
    
        # find the route through the intersection (ie. the turning motion)
        local_routes = vissim.find_routes(decision_link,dest)
        local_route = local_routes.find{|r| r.decisions.include?(dec)}
        raise "No routes from #{decision_link} to #{dest} over #{dec} among these routes:
               \n#{local_routes.map{|lr|lr.to_vissim}.join("\n")}" if local_route.nil?
                
        fractions = dec.fractions.find_all do |fraction| 
          fraction.veh_type == veh_type and
            program.interval === fraction.interval.tstart
        end
        if program.repeat_first_interval
          first_fraction = dec.fractions.min_by{|f|f.interval}
          
          raise "Fractions at #{dec}:\n#{fractions.join("\n")}" unless first_fraction
          
          new_first_fraction = first_fraction.copy
          new_first_fraction.interval.shift(-program.resolution * 60)
          
          fractions << new_first_fraction
        end
        rd.add_route(local_route, fractions)
      end
  
      routing_decisions << rd 
    end
    
  end
  
  routing_decisions
end

if __FILE__ == $0  
  puts "BEGIN"
  
  require 'cowi_tests'
  
  vissim = Vissim.new
  
  rds = get_routing_decisions vissim,MORNING
  puts rds.to_vissim
    
  puts "END"
end