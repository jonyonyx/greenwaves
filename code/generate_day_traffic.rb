require 'const'

# generate hourly values for day program at gl køge landevej

sql = "SELECT avg(cars) * 4 as cars, avg(trucks) * 4 as trucks, from_direction,[turning motion] as turn, intersection FROM 
  [counts$]
  GROUP BY intersection,from_direction,to_direction,[turning motion]"

data = [['Intersection','Period Start','Period End','Flow','Cars','Trucks','From_direction','to_direction','Turning Motion','Time of Day']]

for row in DB[sql].all
  data << [row[:intersection],'12:00','13:00',nil,row[:cars] * 0.75,row[:trucks] * 0.75,row[:from_direction],nil,row[:turn],'Dag']
end

#for row in data
#  puts row.inspect
#end

to_xls(data,'data',File.join(Base_dir,'data','day_plans.xls'))