# 
# To change this template, choose Tools | Templates
# and open the template in the editor.
 

require 'csv'
require 'const'

puts "BEGIN"

s = "abc456abc"
i = 0

until /456/.match(s)
  puts i
  i+=1
end


puts "END"