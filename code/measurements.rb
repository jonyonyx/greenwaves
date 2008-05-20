# insertion of measurement points (queue length detectors and travel time sections)
# note! obsoleted, use node evaluations per intersection instead!
# buses are an exception for travel time evaluations

require 'vissim_output'

def insert_measurements vissim = Vissim.new(Default_network)
  routes = vissim.get_full_routes
  
  #insert_queuecounters vissim, routes
  insert_traveltimes routes, :buses => true
end
class QueueCounter < VissimElem
  attr_reader :link
  def to_s; "#{super} at #{@link}"; end
end
class TravelTime < VissimElem
  attr_reader :from,:to,:vehicle_classes
  def to_s; "#{super} from #{@from} to #{@to}"; end
  def <=>(tt2)
    (@from == tt2.from) ? (@to <=> tt2.to) : (@from <=> tt2.from)
  end
end
class Node < VissimElem; end

class QueueCounters < Array
  include VissimOutput
  def section_header; /^-- Queue Counters: --/; end
  def to_vissim
    str = ''
    each_with_index do |link,i|
      str += "QUEUE_COUNTER #{i+1}     LINK #{link.number}  AT #{link.length - 5}\n"
    end
    str
  end
end

def insert_queuecounters vissim, routes = get_full_routes(vissim)

  decisions = routes.collect{|r|r.decisions}.flatten.uniq 

  qc = QueueCounters.new
  # insert a queue length detector before each turning motion
  # a decision is a connector. the from link is where to put the measuring device
  decisions.sort.each{|dec| qc << dec.connector.from}

  #puts qc.to_vissim
  qc.write
end

class TravelTimes < Array
  include VissimOutput
  def section_header; /^-- Travel Times: --/; end
  def add name, input, exit, veh_types = Cars_and_trucks
    self << {:name => name, :input => input, :exit => exit, :vehtyp => veh_types}
  end
  def to_vissim
    str = "TRAVEL_TIME   AGGREGATION_INTERVAL 99999 FROM 0 UNTIL 99999 RAW YES DATABASE TABLE \"TRAVELTIMES\"  AGGREGATE NO\n"
    each_with_index do |tt,i|      

      str += "
TRAVEL_TIME   #{i+1} NAME \"#{tt[:name]}\"   DISPLAY LABEL 0.000 0.000 0.000 0.000  EVALUATION YES
  FROM    LINK #{tt[:input]}  AT 20.000    TO    LINK #{tt[:exit]}  AT  50.000  SMOOTHING 0.25        VEHICLE_CLASSES #{tt[:vehtyp].join(' ')}"
     
    end
    str
  end
end
def insert_traveltimes routes, opts
  tts = TravelTimes.new

  if opts[:buses]
    # Insert travel time measurings for each bus line
    for row in exec_query "SELECT BUS, [Input_Link], [Exit_Link] FROM [buses$]"
      tts.add "Bus #{row[0].to_i}", row[1].to_i, row[2].to_i, [Type_map['Buses']]
    end
  end

  if opts[:private_vehicles]
    # Insert travel time measurings for full routes which have a certain length
    for route in routes.find_all{|r| r.length >= MIN_ROUTE_LENGTH}.sort
      tts.add "From #{route.start} to #{route.exit}", route.start.number, route.exit.number
    end
  end

  #puts tts.to_vissim
  tts.write
end

if __FILE__ == $0
  insert_measurements
end