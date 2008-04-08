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
  {:name => 'DOGS and bus', :dogs => true, :buspriority => true},
  {:name => 'DOGS no bus', :dogs => true, :buspriority => false},
  {:name => 'No DOGS with bus', :dogs => false, :buspriority => true},
  {:name => 'No DOGS or bus', :dogs => false, :buspriority => false}
]

testqueue = ThreadSafeArray.new tests

insert_measurements

puts "Loading Vissim..."

vissimnet = Vissim.new(Default_network)

threads = []

# start a vissim instance for each processor 
# (vissim does not use parallel computations before 5.10)
ENV['NUMBER_OF_PROCESSORS'].times do
  threads << Thread.new do 
    vissim = WIN32OLE.new('VISSIM.Vissim')

    puts "Loading network..."

    vissim.LoadNet Default_network
    vissim.LoadLayout "#{Vissim_dir}speed.ini"

    puts "Loading simulator..."

    sim = vissim.Simulation

    sim.Period = 1 * Minutes_per_hour * Seconds_per_minute # simulation seconds
    #sim.Period = 900 # simulation seconds
    sim.Resolution = 1 # steps per simulation second

    results = TravelTimeResults.new(vissimnet)

    while parms = testqueue.pop
  
      generate_controllers parms
  
      print "Running simulation '#{parms[:name]}'... "
  
      sim.RandomSeed = rand
      sim.RunContinuous
  
      puts "done"
  
      results.extract_results parms[:name]
  
      i += 1
    end

    puts "Completed #{i} simulation#{i != 1 ? 's' : ''}, exiting Vissim..."

    vissim.Exit
  end
end

threads.each{|t| t.join}

puts "Preparing Results..."

results.to_xls

puts "END"
