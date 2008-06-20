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

TURNING_SQL = "SELECT clng(INTSECT.number) as intersection_number,
                  from_direction, to_direction,
                  [Turning Motion] As turn, 
                  [Period Start] As tstart,
                  [Period End] As tend,
                  cars, trucks
                FROM [counts$] As COUNTS
                INNER JOIN [intersections$] As INTSECT
                ON COUNTS.Intersection = INTSECT.Name
                WHERE [Period End] BETWEEN \#1899/12/30 #{PERIOD_START}:00\# AND \#1899/12/30 #{PERIOD_END}:00\#"
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

def get_streams
  streams = []
  DB[TURNING_SQL].each do |row|
    from = row[:from_direction][0..0]
    to = row[:to_direction][0..0]
    intersection = row[:intersection_number]
    
    stream = streams.find{|s|s.from == from and s.to == to and s.intersection == intersection}
    if not stream 
      stream = Stream.new(from[0..0],to[0..0],intersection,row[:turn][0..0])
      streams << stream
    end
    stream.add_fraction(
      Time.parse(row[:tstart][-8..-1]) - START_TIME, 
      Time.parse(row[:tend][-8..-1]) - START_TIME, 
      row[:cars], row[:trucks])
  end
  
  streams
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
  def hash; @tstart.hash + @tend.hash; end
  def eql?(other); @tstart == other.tstart and @tend == other.tend; end
  def to_vissim; "FROM #{@tstart} UNTIL #{@tend}"; end
  def to_s; "#{@tstart} to #{@tend}"; end
  def <=>(i2); @tstart <=> i2.tstart; end
end
class Fraction
  attr_reader :interval, :veh_type, :quantity
  def <=>(f2); @interval <=> f2.interval; end
  def to_s; "Fraction from #{@interval} = #{quantity} #{@veh_type}"; end
  def to_vissim; "FRACTION #{@quantity}";end
end

def get_routing_decisions vissim  
  
  streams = get_streams
  
  vissim.decisions.sort.each do |dec|
    
    # find the stream which defines the quantity of vehicles over this decision
    quantity_stream = streams.find do |s|
      s.from == dec.from_direction and 
        s.turning_motion == dec.turning_motion and 
        s.intersection == dec.intersection
    end || raise("Could not find stream for #{dec}")
    
    # the donor stream is usually identical to quantity_stream
    # but may be some upstream source, which should be adjusted
    donor_stream = streams.find do |s|
      s.from == dec.decide_from_direction and
        s.intersection == dec.decide_at_intersection and
        s.turning_motion == 'T' # TODO correctly determine which stream is the donor
    end || quantity_stream
    
    quantity_stream.traffic.keys.sort.each do |period|
      [:cars,:trucks].each do |veh_type|
        request_vehicles = quantity_stream.traffic[period][veh_type]
        vehicles = donor_stream.get_traffic(period, veh_type,request_vehicles)
      
        puts "Received only #{vehicles} of #{request_vehicles} #{veh_type} for stream #{quantity_stream} from #{donor_stream}" if request_vehicles != vehicles
        dec.add_fraction(period, veh_type, vehicles)
      end
    end
    
  end
  
  decisions = vissim.decisions.find_all{|dec|not dec.fractions.empty?}
 
  routing_decisions = RoutingDecisions.new
  
  # find the local routes from the decision point
  # to the point where the vehicles are dropped off downstream of intersection
  decisions.map{|dec|dec.decision_point}.uniq.sort.each do |dp|
    decision_link = dp.link(vissim)
    #puts dp if dp.from_direction == 'N' and dp.intersection == 2
    
    for veh_type in [:cars,:trucks]
      rd = RoutingDecision.new!(:input_link => decision_link, :veh_type => veh_type, :time_intervals => dp.time_intervals)
  
      # add routes to the decision point
      for dec in dp.decisions
        dest = dec.drop_link
    
        # find the route through the intersection (ie. the turning motion)
        local_routes = vissim.find_routes(decision_link,dest)
        local_route = local_routes.find{|r| r.decisions.include?(dec)}
        raise "No routes from #{decision_link} to #{dest} over #{dec} among these routes:
               #{local_routes.map{|lr|lr.to_vissim}.join("\n")}" if local_route.nil?
                
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
  
  rds =  get_routing_decisions vissim
  #puts rds.to_vissim
  rds.write
    
  puts "END"
end