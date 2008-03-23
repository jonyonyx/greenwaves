require 'const'  
class Inputs < VissimOutput
  def initialize
    @inputs = []
  end
  def section_header; /^-- Inputs: --/; end
  def add input
    @inputs << input
  end
  def get_by_link number
    @inputs.find_all{|i| i.link.number == number}
  end
  def to_vissim
    str = ''
    inputnum = 1
    tbegin = @inputs.map{|i| i.tstart}.min
    for input in @inputs
      link = input.link
      
      for veh_type, q in input.veh_flow_map      
        str += "INPUT #{inputnum}\n" +
          "      NAME \"#{veh_type} from #{link.from} on #{link.name}\" LABEL  0.00 0.00\n" +
          "      LINK #{link.number} Q #{q * INPUT_FACTOR} COMPOSITION #{Type_map[veh_type]}\n" +
          "      TIME FROM #{input.tstart - tbegin} UNTIL #{input.tend - tbegin}\n"
        
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
    flow_type1 = @veh_flow_map[veh_type1]
    flow_type1.to_f / (flow_type1 + @veh_flow_map[veh_type2])
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
  
  for det, from in [['D3','North'],['D01','South'],['D03','West'],['D06','East']]
        
    #fetch the link input number    
    number = exec_query("SELECT LINKS.Number 
        FROM [detectors$] As DETS
        INNER JOIN [links$] As LINKS
        ON DETS.Intersection = LINKS.Intersection
        WHERE DETS.Name = '#{det}'
        AND LINKS.From = '#{from}'").flatten.first.to_i
    
    # now change the input for this link number to use
    # the data from this detector, respecting the vehicle ratio
    
    inputs_for_link = inputs.get_by_link number
    
    #puts "input link: #{number.inspect}"
    
    sql = "SELECT 
          HOUR(Time) As H,
          MINUTE(Time) As M,
          AVG(Detected) As Detected
        FROM #{Accname}
        WHERE NOT DoW IN ('Sat','Sun') 
        AND Detector = '#{det}'
        AND Time BETWEEN \#1899/12/30 07:00:00\# AND \#1899/12/30 09:00:00\#
        GROUP BY Detector,Time"
    
    for row in exec_query sql, CSVCS
      input = inputs_for_link.find{|i| i.tend.hour == row['H'] and i.tend.min == row['M']}
      qtot = row['Detected'].to_f
      r = input.ratio('Cars', 'Trucks')
      #puts "ratio: #{r}"
      input.veh_flow_map['Cars'] = qtot * r
      input.veh_flow_map['Trucks'] = qtot * (1 - r)
    end
  end
  
  inputs
end

if __FILE__ == $0
  vissim = Vissim.new(Default_network)
  inputs = get_inputs vissim
  
  puts inputs.to_vissim
end