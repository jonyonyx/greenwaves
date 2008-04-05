# insertion of measurement points (queue length detectors and travel time sections)

require 'const'
require 'vissim'
require 'vissim_routes'

class QueueCounters < VissimOutput
  def initialize; @links = []; end
  def section_header; /^-- Queue Counters: --/; end
  def add link; @links << link; end
  def to_vissim
    str = ''
    @links.each_with_index do |link,i|
      str += "QUEUE_COUNTER #{i+1}     LINK #{link.number}  AT #{link.length - 5}\n"
    end
    str
  end
end

vissim = Vissim.new(Default_network)

routes = get_full_routes vissim

decisions = routes.collect{|r|r.decisions}.flatten.uniq 

qc = QueueCounters.new
# insert a queue length detector before each turning motion
# a decision is a connector. the from link is where to put the measuring device
decisions.sort.each{|dec| qc.add dec.connector.from}

#qc.write

class TravelTimes < VissimOutput
  def initialize; @tts = []; end
  def section_header; /^-- Travel Times: --/; end
  def add name, input, exit, veh_types = Cars_and_trucks
    @tts << {:name => name, :input => input, :exit => exit, :vehtyp => veh_types}
  end
  def to_vissim
    str = "TRAVEL_TIME   AGGREGATION_INTERVAL 99999 FROM 0 UNTIL 99999 RAW YES DATABASE TABLE \"TRAVELTIMES\"  AGGREGATE NO\n"
    @tts.each_with_index do |tt,i|      

      str += "
TRAVEL_TIME   #{i+1} NAME \"#{tt[:name]}\"   DISPLAY LABEL 0.000 0.000 0.000 0.000  EVALUATION YES
  FROM    LINK #{tt[:input]}  AT 20.000    TO    LINK #{tt[:exit]}  AT  50.000  SMOOTHING 0.25        VEHICLE_CLASSES #{tt[:vehtyp].join(' ')}"
     
    end
    str
  end
end

tts = TravelTimes.new

# Insert travel time measurings for each bus line
for row in exec_query "SELECT BUS, [In Link], [Out Link] FROM [buses$]"
  tts.add "Bus #{row[0].to_i}", row[1].to_i, row[2].to_i, [Type_map['Buses']]
end

# Insert travel time measurings for full routes
for route in routes.sort
  tts.add "From #{route.start} to #{route.exit}", route.start.number, route.exit.number
end

#puts tts.to_vissim
tts.write