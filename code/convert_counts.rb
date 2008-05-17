require 'const'

count_rows = [['Intersection', 'Period End', 'from_direction', 'Turning Motion', 'Cars', 'Trucks']]
for turning_motion in ['Left', 'Through', 'Right']
  sql = "SELECT 
         Intersection,
         [Period End],
         [From], 
         'TURN' As [Turning Motion], 
         ([Cars TURN] + 0) As Cars, 
         ([Trucks TURN] + 0) As Trucks
        FROM [counts_old$]"
  
  rows = exec_query(sql.gsub('TURN',turning_motion))
  
  count_rows.concat(rows)
end

csv = count_rows.map do |row|
  row.join(';')
end.join("\n")

puts csv
