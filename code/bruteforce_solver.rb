require 'const'

N = 4
C = 10

cycle_times = (0...C).to_a

def printa a
  for r in a
    puts r.inspect
  end
end
ar = (cycle_times * N).permutation(N).to_a

puts "Before: #{ar.size}"
ar.each{|r|r.map!{|o|o-r.min}}

ar = ar.uniq

puts "After: #{ar.size}:"
printa ar