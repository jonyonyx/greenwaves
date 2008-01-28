# 
# To change this template, choose Tools | Templates
# and open the template in the editor.
 

require 'csv'
require 'const'

puts "BEGIN"

test = "123"

if test.instance_of?(String)
  puts "a string"
elsif test.instance_of?(Fixnum)
  puts "an int"
else
  puts "#{test.class}"
end

puts "END"