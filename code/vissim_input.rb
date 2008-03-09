##
# Load an .csv file containing accumulated detections for some period.
# Output strings, which define input in consecutive periods in the Vissim format (see below)

require 'const'  

def get_inputs

  links = get_links('TYPE' => 'IN')

  input_rows = exec_query "SELECT COUNTS.Intersection, LINKS.Number, HOUR([Period End]) As H, MINUTE([Period End]) As M, 
              [Total Cars] As Cars,
              [Total Trucks] As Trucks
              FROM [counts$] As COUNTS
              INNER JOIN [links$] As LINKS 
              ON  COUNTS.Intersection = LINKS.Intersection AND 
                  COUNTS.From = LINKS.From
              WHERE LINKS.Type = 'IN' 
              ORDER BY [Period End], LINKS.Number"

  insect_info = exec_query "SELECT Name, [Count Date] FROM [intersections$]"

  hm_min_tuple = exec_query("SELECT HOUR(MIN([Period End])), MINUTE(MIN([Period End])) FROM [counts$]").first
  hm_max_tuple = exec_query("SELECT HOUR(MAX([Period End])), MINUTE(MAX([Period End])) FROM [counts$]").first
  t_start = Time.parse(hm_min_tuple.join(':')) - Res*60
  t_end = Time.parse(hm_max_tuple.join(':'))

  inputs = Inputs.new(t_start, t_end)

  # iterate over the detected data by period...
  for row in input_rows
  
    t = Time.parse("#{row['H']}:#{row['M']}")  
    link_number = row['Number'].to_i
  
    link = links.find{|l| l.number == link_number}
    raise "Warning: unable to locate link with number #{link_number}" unless link
  
    isname = row['Intersection']
  
    isrow = insect_info.find{|r| r['Name'] == isname}
  
    raise "Warning: unable to find counting date for intersection '#{isname}'" unless isrow
  
    count_date = Time.parse(isrow['Count Date'].to_s)
      
    # number of years which has passed since the traffic count
    years_passed = Time.now.year - count_date.year
  
    # produce an input per vehicle type
    for veh_type in ['Cars','Trucks']
      flow = row[veh_type]
      next unless flow > EPS
    
      # link inputs in Vissim is defined in veh/h
      # also scale the input according to the time which has passed
      link_contrib = flow * (60/Res) * ANNUAL_INCREASE ** years_passed 
   
      inputs.add link, veh_type, t, link_contrib  
    end
  end

  # generate bus inputs
  for row in exec_query "SELECT Bus, [IN Link], Frequency FROM [buses$]"
    link_number = row['IN Link']
    link = links.find{|l| l.number == link_number}
    raise "Warning: unable to locate link with number #{link_number}" unless link
  
    # add a bus input for each bus even though it is on the same link
    inputs.add link, "Buses", nil, row['Frequency'], "Bus #{row['Bus']}"
  end

  inputs
end