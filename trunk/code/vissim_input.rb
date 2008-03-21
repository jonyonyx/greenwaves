require 'const'  
class Inputs < VissimOutput
  def initialize
    @inputs = []
  end
  def section_header; /^-- Inputs: --/; end
  def add input
    @inputs << input
  end
  def to_vissim
    str = ''
    inputnum = 1
    tstart = @inputs.map{|i| i.tstart}.min
    for input in @inputs
      link = input.link
      
      for veh_type, q in input.veh_flow_map      
        str += "INPUT #{inputnum}\n" +
          "      NAME \"#{veh_type} from #{link.from} on #{link.name}\" LABEL  0.00 0.00\n" +
          "      LINK #{link.number} Q #{q * INPUT_FACTOR} COMPOSITION #{Type_map[veh_type]}\n" +
          "      TIME FROM #{input.tstart - tstart} UNTIL #{input.tend - tstart}\n"
        
        inputnum += 1
      end
    end
    str
  end
end

class Input
  attr_reader :link,:tstart,:tend,:veh_flow_map
  def initialize link, tstart, tend, veh_flow_map
    @link, @tstart, @tend, @veh_flow_map = link, tstart, tend, veh_flow_map
  end
  def ratio veh_type1, veh_type2
    @veh_flow_map[veh_type1] / @veh_flow_map[veh_type2]
  end
end

def get_inputs vissim

  links = vissim.input_links

  input_sql = "SELECT COUNTS.Intersection, LINKS.Number, HOUR([Period End]) As H, MINUTE([Period End]) As M, 
              [Total Cars] As Cars,
              [Total Trucks] As Trucks
              FROM [counts$] As COUNTS
              INNER JOIN [links$] As LINKS 
              ON  COUNTS.Intersection = LINKS.Intersection AND 
                  COUNTS.From = LINKS.From
              WHERE LINKS.Type = 'IN' 
              ORDER BY [Period End], LINKS.Number"

  insect_info = exec_query "SELECT Name, [Count Date] FROM [intersections$]"

  inputs = Inputs.new

  # iterate over the detected data by period to generate
  # input which varies with the defined resolution
  for row in exec_query input_sql
  
    tend = Time.parse("#{row['H']}:#{row['M']}")  
    link_number = row['Number'].to_i
  
    link = links.find{|l| l.number == link_number}
    raise "Unable to locate link with number #{link_number}" unless link
  
    isname = row['Intersection']
  
    isrow = insect_info.find{|r| r['Name'] == isname}
  
    raise "Unable to find counting date for intersection '#{isname}'" unless isrow
  
    count_date = Time.parse(isrow['Count Date'].to_s)
      
    # number of years which has passed since the traffic count
    years_passed = Time.now.year - count_date.year
  
    veh_flow_map = {}
    # produce an input per vehicle type
    for veh_type in ['Cars','Trucks']
      flow = row[veh_type]
      next if flow < EPS
    
      # link inputs in Vissim is defined in veh/h
      # also scale the input according to the time which has passed
      veh_flow_map[veh_type] = flow * (Minutes_per_hour/Res) * ANNUAL_INCREASE ** years_passed 
    end
    tstart = tend - Res*Minutes_per_hour
    inputs.add Input.new(link, tstart, tend, veh_flow_map)
  end
  
  # for northern end (by herlev sygehus) and roskildevej
  # use the dogs detector data and take the cars-to-truck ratios from the
  # traffic counts

  inputs
end

if __FILE__ == $0
  vissim = Vissim.new(Default_network)
  inputs = get_inputs vissim
  
  puts inputs.to_vissim
end