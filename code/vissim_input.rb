##
# Load an .csv file containing accumulated detections for some period.
# Output strings, which define input in consecutive periods in the Vissim format (see below)

require 'const'
require 'dbi'

puts "BEGIN"    

INPUT_FACTOR = 1.0

Links = get_links(nil, 'IN')

Input_rows = exec_query "SELECT COUNTS.Intersection, LINKS.Number, HOUR([Period End]) As H, MINUTE([Period End]) As M, 
              [Total Cars] As Cars,
              [Total Trucks] As Trucks
              FROM [counts$] As COUNTS
              INNER JOIN [links$] As LINKS 
              ON  COUNTS.Intersection = LINKS.Intersection AND 
                  COUNTS.From = LINKS.From
              WHERE LINKS.Type = 'IN' 
              ORDER BY [Period End], LINKS.Number"

Insect_info = exec_query "SELECT Name, [Count Date] FROM [intersections$]"

#for row in Insect_info
#  puts row.inspect
#end
#
#exit(0)
Step = Res*60 
Time_fmt2 = '%H:%M:%S'
HM_min_tuple = exec_query("SELECT HOUR(MIN([Period End])), MINUTE(MIN([Period End])) FROM [counts$]").first
HM_max_tuple = exec_query("SELECT HOUR(MAX([Period End])), MINUTE(MAX([Period End])) FROM [counts$]").first
T_start = Time.parse(HM_min_tuple.join(':')) - Step
T_end = Time.parse(HM_max_tuple.join(':'))

class Input
  def initialize t_start, t_end
    @t_start = t_start
    @t_end = t_end
    @inputs = []
  end
  def add link, veh_type, t_end, quantity, desc = nil
    @inputs << {'LINK' => link, 'TYPE' => veh_type, 'COMP' => Type_map[veh_type], 'TEND' => t_end, 'Q' => quantity, 'DESC' => desc}
  end
  def to_vissim
    str = ''
    @inputs.each_with_index do |input, input_num|  
      link = input['LINK']
      
      if input['TEND']        
        t = input['TEND']
        t_begin = t - Step
        q = input['Q']
      else
        # no TEND indicates this is a bus input
        t = @t_end
        t_begin = @t_start
        # bus frequencies are given by the hour so scale it
        q = input['Q'] * (t.hour - t_begin.hour) # assume t_begin .. t_end in the same day
      end
      
      q = q * INPUT_FACTOR
      
      str += "INPUT #{input_num+1}\n" +
        "      NAME \"#{input['DESC'] ? input['DESC'] : input['TYPE']} from #{link.from} on #{link.name} (#{t_begin.strftime(Time_fmt2)}-#{t.strftime(Time_fmt2)})\" LABEL  0.00 0.00\n" +
        "      LINK #{link.number} Q #{q} COMPOSITION #{input['COMP']}\n" +
        "      TIME FROM #{t_begin - @t_start} UNTIL #{t - @t_start}\n"
    end
    str
  end
end

I = Input.new(T_start, T_end)

# iterate over the detected data by period...
for row in Input_rows
  
  t = Time.parse("#{row['H']}:#{row['M']}")  
  link_number = row['Number'].to_i
  
  link = Links.find{|l| l.number == link_number}
  raise "Warning: unable to locate link with number #{link_number}" unless link
  
  isname = row['Intersection']
  
  isrow = Insect_info.find{|r| r['Name'] == isname}
  
  raise "Warning: unable to find counting date for intersection '#{isname}'" unless isrow
  
  count_date = Time.parse(isrow['Count Date'].to_s)
      
  # number of years which has passed since the traffic count
  years_passed = Time.now.year - count_date.year
  
  # produce an input per vehicle type
  for veh_type in ['Cars','Trucks']
    flow = row[veh_type]
    next unless flow > 0.0
    
    # link inputs in Vissim is defined in veh/h
    # also scale the input according to the time which has passed
    link_contrib = flow * (60/Res) * 1.015 ** years_passed 
    
    I.add link, veh_type, t, link_contrib  
  end
end

# generate bus inputs
Busplan = exec_query "SELECT Bus, [IN Link], Frequency FROM [buses$]"

for row in Busplan
  link_number = row['IN Link']
  link = Links.find{|l| l.number == link_number}
  raise "Warning: unable to locate link with number #{link_number}" unless link
  
  # add a bus input for each bus even though it is on the same link
  I.add link, "Buses", nil, row['Frequency'], "Bus #{row['Bus']}"
end

output_string = I.to_vissim

Clipboard.set_data output_string
puts output_string

puts "Link Input Data has been placed on your clipboard."

puts "END"