# 
# To change this template, choose Tools | Templates
# and open the template in the editor.
 

require 'csv'
require 'const'

puts "BEGIN"

O = 66
C = 80

# no modulus(!)
def t_loc(t_mas)  
  if t_mas >= O
    t_mas - O + 1
  else
    t_mas - O + C + 1
  end
end

1.upto(80){|t_mas| puts "#{t_mas} => #{t_loc(t_mas)}"}


puts "END"