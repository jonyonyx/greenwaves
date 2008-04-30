require 'const'

count_rows = [['Intersection', 'Period End', 'From', 'Turning Motion', 'Cars', 'Trucks']]
for turning_motion in ['Left', 'Through', 'Right']
  sql = "SELECT 
         Intersection,
         [Period End],
         [From], 
         'TURN' As [Turning Motion], 
         ([Cars TURN] + 0) As Cars, 
         ([Trucks TURN] + 0) As Trucks
        FROM [counts_old$]
        WHERE Intersection LIKE 'Gammel%'"
  
  rows = exec_query(sql.gsub('TURN',turning_motion))    
  
  count_rows.concat(rows)
end

to_xls count_rows, 'conversion'

puts "Completed conversion, wrote #{count_rows.size} rows in the new format."