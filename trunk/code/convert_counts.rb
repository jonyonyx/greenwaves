require 'const'

count_rows = [['Intersection', 'Period End', 'From', 'Turning Motion', 'Cars', 'Trucks']]
for turning_motion in ['Left', 'Through', 'Right']
  sql = "SELECT 
         Intersection,
         [Period End],
         [From], 
         'TURN' As [Turning Motion], 
         [Cars TURN] As Cars, 
         [Trucks TURN] As Trucks
        FROM [counts$]
        WHERE Intersection LIKE 'Gammel%'"
  
  rows = exec_query(sql.gsub('TURN',turning_motion))    
  
  count_rows.concat(rows.find_all{|r| ['Cars','Trucks'].all?{|vehtype| r[vehtype] and r[vehtype].to_f > EPS}})
end

to_xls count_rows, 'conversion'

puts "Completed conversion, wrote #{count_rows.size} rows in the new format."