
require 'const'
require 'vissim'

vissimlookup = Vissim.new
vissim = Vissim.new 'C:\projects\62832\avedore_24_trafik.inp'

t0 = Time.parse('0:00') # simulation start time eg. 7:00

tstart = Time.parse('11:00') # start time of first input
tend = Time.parse('13:00') # - of last input

timerange = ((tstart-t0).to_i...(tend-t0).to_i)

data = [['Intersection','Period Start','Period End','Flow','Cars','Trucks','From_direction','to_direction','Turning Motion','Time of Day']]

# compositions
cars = 5
trucks = 6

link2intersection = {20 => {:intersection_number => 2, :from_direction => 'N'}}

for input in vissim.inputs.find_all{|i| timerange === i.tstart}.sort
  link = input.link
  
  controller = vissimlookup.controllers.find do |sc|
    sc.number == (link.intersection_number || link2intersection[link.number][:intersection_number])    
  end
  
  next if controller.nil? # could not find signal controller this link - not needed    
  
  data << [
    controller.name,
    (t0 + input.tstart).to_hm,
    (t0 + input.tend).to_hm,
    nil,
    input.veh_flow_map[cars],
    input.veh_flow_map[trucks],
    link.from_direction || link2intersection[link.number][:from_direction],
    nil,nil,
    'Day'
  ]
end

#for row in data
#  puts row.inspect
#end

to_xls(data,'data',File.join(Base_dir,'data','day_plans.xls'))
