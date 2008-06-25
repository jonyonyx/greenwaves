require 'const'

# generate hourly values for day program at gl køge landevej

sql = "SELECT avg(cars) as cars, avg(trucks) as trucks, from_direction, intersection as tend FROM 
  [counts$] WHERE intersection IN ('Gammel K\370ge Landevej')
  GROUP BY intersection,from_direction"

data = [['Intersection','Period Start','Period End','Flow','Cars','Trucks','From_direction','to_direction','Turning Motion','Time of Day']]

for row in DB[sql].all
  puts row.inspect
end
