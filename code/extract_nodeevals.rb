require 'const'

db = Sequel.dbi "#{CSPREFIX}#{File.join('C:\projects\62832\test_scenarios\scenario_basis_dag','results.mdb')};"

sql = "SELECT 
              fromlink,
              tend,
              movement,
              avg(avequeue) as aveq,
              avg(maxqueue) as maxq,
              avg(delay_all_) as delay              
            FROM NODEEVALUATION
            WHERE fromlink IN (6,9,20,35)
            AND movement <> 'All'
            GROUP BY fromlink,tend,movement
            ORDER BY tend,fromlink"

rows = db[sql].all



for row in rows
  puts row.inspect
end

puts "Query returned #{rows.size} rows"
