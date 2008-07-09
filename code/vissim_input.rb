require 'const'
require 'vissim_output'
require 'vissim'

class Inputs < Array
  include VissimOutput
  def section_header; /^-- Inputs: --/; end
  def to_vissim
    str = ''
    inputnum = 1
    tbegin = map{|i| i.interval}.min.tstart
    sort.each do |input|
      link = input.link
      
      fraction = input.fraction
      interval = input.interval
      veh_type = fraction.veh_type
      
      str << "INPUT #{inputnum}\n" +
        "      NAME \"#{veh_type.to_s.capitalize} from #{link.from_direction}#{link.name.empty? ? '' : " ON " + link.name}\" LABEL  0.00 0.00\n" +
        "      LINK #{link.number} Q EXACT #{fraction.quantity.round.to_f} COMPOSITION #{Type_map[veh_type]}\n" +
        "      TIME FROM #{interval.tstart - tbegin} UNTIL #{interval.tend - tbegin}\n"
        
      inputnum += 1
    end
    str
  end
end

class Input
  attr_reader :link,:fraction,:interval
  def initialize link, fraction
    @link, @fraction = link, fraction
    @interval = fraction.interval
  end
  def to_s
    "Input on #{@link}: #{@fraction}"
  end
  
  # sort by time intervals then vehicle types
  def <=>(other)
    if @interval == other.interval
      @fraction.veh_type.to_s <=> other.fraction.veh_type.to_s
    else
      @interval <=> other.interval
    end
  end
end

class Vissim
  def get_inputs program
    
    inputs = Inputs.new
    
    @decisions.group_by{|dec|dec.original_approach}.each do |approach,decisions|      
      
      # find a *start* link that reaches all decisions at the approach without
      # traversing other decisions      
      input_link = @start_links.find do |link|
        routes = find_routes(link,decisions)
        decisions.all?{|dec|routes.any?{|r|r.include?(dec)}} and routes.all?{|r|r.decisions.size == 1}
      end
      
      next if input_link.nil? # this approach is not an input and is fed by upstream decisions
      
      raise "Unable to locate link with number #{link_number}" unless input_link
        
      dp = DecisionPoint.new(decisions.first.from_direction,decisions.first.intersection)
      decisions.each{|dec|dp << dec}
      
      dp.time_intervals(program,false).each do |interval|
        [:cars,:trucks].each do |vehtype|
          fractions = decisions.map{|dec|dec.fractions.filter(interval,vehtype)}.flatten
          total_quantity = Fractions.sum(fractions) * INPUT_SCALING * (60/interval.resolution_in_minutes)
          
          combined_fraction = Decision::Fraction.new(interval,vehtype,total_quantity)
          inputs << Input.new(input_link,combined_fraction)
        end
      end
  
    end
  
    if program.repeat_first_interval
      # heating of the simulator
      time_offset = program.resolution * 60
      inputs.find_all{|i|i.interval.tstart == program.from}.each do |input|    
        newfraction = input.fraction.copy
        newfraction.interval.shift!(-time_offset)
        inputs << Input.new(input.link,newfraction)
      end
    end
    
    inputs
  end
end

def get_inputs_old vissim,program

  links = vissim.input_links
  
  # Aggregate all turning motions in the same from-direction
  input_sql = "SELECT COUNTS.intersection As isname, LINKS.number, [Period Start] As tstart, [Period End] As tend, 
              SUM(cars) As cars, SUM(trucks) As trucks
              FROM [counts$] As COUNTS
              INNER JOIN [links$] As LINKS 
              ON  COUNTS.Intersection = LINKS.intersection_name AND 
                  COUNTS.from_direction = LINKS.from_direction
              WHERE LINKS.link_type = 'IN'
              AND [Period End] BETWEEN \#1899/12/30 #{program.from.to_hm}:00\# AND \#1899/12/30 #{program.to.to_hm}:00\#
              GROUP BY intersection, [Period End], [Period Start], LINKS.number
              ORDER BY intersection, [Period End]"

  insect_info = DB["SELECT name, count_date FROM [intersections$]"].all

  inputs = Inputs.new

  # iterate over the detected data by period to generate
  # input which varies with the defined resolution
  for row in DB[input_sql].all
  
    tstart = Time.parse(row[:tstart][-8..-1])
    tend = Time.parse(row[:tend][-8..-1])
    link_number = row[:number].to_i
  
    input_link = links.find{|l| l.number == link_number} # insert traffic here
    raise "Unable to locate link with number #{link_number}" unless input_link
    
    # scale the traffic from the counting date to now
    isrow = insect_info.find{|r| r[:name] == row[:isname]}  
    raise "Unable to find counting date for intersection '#{row[:isname]}'" if isrow.nil?
          
    count_date = Time.parse(isrow[:count_date].to_s)
      
    # number of years which has passed since the traffic count
    years_passed = Time.now.year - count_date.year
  
    veh_flow_map = {}
    # produce an input per vehicle type
    for veh_type in [:cars,:trucks]
      flow = row[veh_type.to_sym]
      next if flow < EPS
    
      # link inputs in Vissim is defined in veh/h
      # also scale the input according to the time which has passed
      resolution_in_minutes = (tend-tstart) / 60
      scaled_flow = flow * INPUT_SCALING * (MINUTES_PER_HOUR/resolution_in_minutes) * (ANNUAL_INCREASE ** years_passed) 
      #puts "#{input_link}: #{flow} -> #{scaled_flow} #{scaled_flow/flow} from #{tstart} to #{tend}"
      veh_flow_map[veh_type] = scaled_flow
    end
    
    inputs << Input.new(input_link, tstart, tend, veh_flow_map)
  end
  
  if program.repeat_first_interval
    # heating of the simulator
    time_offset = program.resolution * 60
    inputs.find_all{|i|i.tstart == program.from}.each do |input|    
      inputs << Input.new(input.link,input.tstart - time_offset, input.tend - time_offset,input.veh_flow_map)
    end
  end
  
  inputs
end

if __FILE__ == $0
  puts "BEGIN"
  require 'cowi_tests'
  
  vissim = Vissim.new
  
  inputs = vissim.get_inputs MORNING
  inputs.write
  #puts inputs.to_vissim
  
  puts "END"
end
