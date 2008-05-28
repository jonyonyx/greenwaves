require 'const'

sql = "SELECT Cars, Trucks FROM [counts$] WHERE intersection = 'Amagermotorvejen Nord'"

for row in DB[sql].all
  puts row.inspect
end