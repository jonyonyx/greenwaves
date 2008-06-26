require 'const'
require 'vissim_output'
require 'vissim'

class Inputs < Array
  include VissimOutput
  def section_header; /^-- Inputs: --/; end
  def get_by_link number
    find_all{|i| i.link.number == number}
  end
  def to_vissim
    str = ''
    inputnum = 1
    tbegin = map{|i| i.tstart}.min
    each do |input|
      link = input.link
      
      for veh_type, q in input.veh_flow_map      
        str << "INPUT #{inputnum}\n" +
          "      NAME \"#{veh_type} from #{link.from_direction}#{link.name.empty? ? '' : " ON " + link.name}\" LABEL  0.00 0.00\n" +
          "      LINK #{link.number} Q #{q * 0.8} COMPOSITION #{Type_map[veh_type]}\n" +
          "      TIME FROM #{input.tstart - tbegin} UNTIL #{input.tend - tbegin}\n"
        
        inputnum += 1
      end
    end
    str
  end
  def to_a
    
  end
end

class Input
  attr_reader :link,:tstart,:tend,:veh_flow_map
  def initialize link, tstart, tend, veh_flow_map
    @link, @tstart, @tend, @veh_flow_map = link, tstart, tend, veh_flow_map
  end
  def ratio veh_type1, veh_type2
    flow_type1 = @veh_flow_map[veh_type1] || 0.0
    flow_type1.to_f / (flow_type1 + (@veh_flow_map[veh_type2] || 0.0))
  end
  def to_s
    "Input on #{@link} from #{@tstart} to #{@tend}: #{@veh_flow_map.inspect}"
  end
  def <=>(other)
    @tstart <=> other.tstart
  end
end

def get_inputs vissim,program

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
  
  # for northern end (by herlev sygehus) and roskildevej
  # use the dogs detector data and take the cars-to-truck ratios from the
  # traffic counts  
  
  if Project == 'dtu'
    for det in ['D3', # northern input from herlev sygehus
        'D01','D03','D06' # roskildevej
      ]
      
      # Fetch the link input number for this detector
      number = exec_query("SELECT LINKS.Number 
        FROM [detectors$] As DETS
        INNER JOIN [links$] As LINKS
        ON DETS.Intersection = LINKS.Intersection_name
        AND DETS.FROM = LINKS.From_direction
        WHERE DETS.Name = '#{det}'").flatten.first.to_i
      
      # now change the input for this link number to use
      # the data from this detector, respecting the vehicle ratio
      
      inputs_for_link = inputs.get_by_link number
      raise "No inputs found for link #{number}" if inputs_for_link.empty?
      
      #puts "input link: #{number}"
      
      sql = "SELECT 
          HOUR(Time) As h,
          MINUTE(Time) As m,
          AVG(Detected) As detected
        FROM [data$]
        WHERE NOT DoW IN ('Sat','Sun') 
        AND Detector = '#{det}'
        AND [Time] BETWEEN \#1899/12/30 #{program.from.to_hm}:00\# AND \#1899/12/30 #{program.to.to_hm}:00\#
        GROUP BY Detector,Time"
      
      for row in DOGSDB[sql].all
        input = inputs_for_link.find{|i| i.tend.hour == row[:h] and i.tend.min == row[:m]}
        raise "Input for link #{number} at tend #{row[:h]}h#{row[:m]}m not found" if input.nil?
        # Vissim expects flow in vechicles per hour. The dogs flow seems to have been adjusted
        # already by inspecting of before and after flow data for each vehicle type (see commented code below)
        flow = row[:detected].to_f * 4
        
        # Assume the DOGS detector data follow approx. the same vehicle type
        # proportion as the counting data and reuse the proportion.
        r = input.ratio('Cars', 'Trucks')        
        #        before_cars = input.veh_flow_map['Cars']
        #        before_trucks = input.veh_flow_map['Trucks']
        input.veh_flow_map['Cars'] = flow * r
        input.veh_flow_map['Trucks'] = flow * (1 - r)
        
        #        puts "Cars delta: #{before_cars - input.veh_flow_map['Cars']}"
        #        puts "Trucks delta: #{before_trucks - input.veh_flow_map['Trucks']}"
      end
    end
  end
  
  inputs
end

if __FILE__ == $0
  puts "BEGIN"
  vissim = Vissim.new
  
  inputs = get_inputs vissim
  inputs.write
  #puts inputs.to_vissim
  
  puts "END"
end