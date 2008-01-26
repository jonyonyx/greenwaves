# 
# To change this template, choose Tools | Templates
# and open the template in the editor.
 
require 'const'
require 'win32ole'

puts "BEGIN"

puts "Loading Vissim..."

vissim = WIN32OLE.new('VISSIM.Vissim')

puts "Loading network..."

vissim.LoadNet Vissim_dir + 'tilpasset_model.inp'
vissim.LoadLayout Vissim_dir + 'vissim.ini'

puts "Loading simulation..."

sim = vissim.Simulation

sim.Period = 100 # simulation seconds
sim.Resolution = 1 # steps per simulation second

puts "Starting the simulator..."

sim.RunContinuous

puts "Simulation completed, exiting Vissim..."

vissim.Exit

puts "END"
