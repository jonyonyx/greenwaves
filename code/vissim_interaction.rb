# 
# To change this template, choose Tools | Templates
# and open the template in the editor.
 
require 'const'
require 'win32ole'
require 'vap'
require 'results'
require 'measurements'

puts "BEGIN"

tests = [
  {:name => 'DOGS_and_bus', :dogs => true, :buspriority => true},
  {:name => 'DOGS_no_bus', :dogs => true, :buspriority => false}
]

insert_measurements

puts "Loading Vissim..."

vissimnet = Vissim.new(Default_network)
vissim = WIN32OLE.new('VISSIM.Vissim')

puts "Loading network..."

vissim.LoadNet Default_network
vissim.LoadLayout "#{Vissim_dir}speed.ini"

puts "Loading simulator..."

sim = vissim.Simulation

#sim.Period = 2 * Minutes_per_hour * Seconds_per_minute # simulation seconds
sim.Period = 600 # simulation seconds
sim.Resolution = 1 # steps per simulation second

results = TravelTimeResults.new

n = tests.length
i = 1
for parms in tests
  
  generate_controllers parms
  
  print "Running simulation #{i} of #{n}... "
  
  sim.RandomSeed = rand
  sim.RunContinuous
  
  puts "done"
  
  results.extract_results parms[:name]
  
  i += 1
end

puts "Completed #{n} simulation#{n != 1 ? 's' : ''}, exiting Vissim..."

vissim.Exit

puts "Printing Results:"

results.print vissimnet

puts "END"
