require 'const'
require 'vissim'

vissim = Vissim.new

vissim.controllers_with_plans.each do |sc|
  data = [['Group','Red End','Green End','DOGS Priority']]
  sc.groups.each do |grp|
    data << [grp.name,grp.red_end,grp.green_end,grp.priority]
  end
  
#  for row in data
#    puts row.inspect
#  end
  
  puts to_tex(data,:caption => "#{sc.name}",:col_align => 'c')
  puts
end