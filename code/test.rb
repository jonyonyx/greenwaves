# 
# To change this template, choose Tools | Templates
# and open the template in the editor.
 

require 'csv'
require 'const'

puts "BEGIN"

class Klass  
  def hi name
    puts "hi #{name} i am klass!"
  end
end

class SubKlass < Klass
  def hi name
    super "name"
    puts "hi #{name} i am subklass!"
    #super.hi
  end
end

sk = SubKlass.new

sk.hi "andreas"

puts "END"