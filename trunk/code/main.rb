require 'vissim'
require 'turningprob'
require 'vissim_input'
require 'vap'

puts "BEGIN"

vissim = Vissim.new

#get_inputs(vissim).write
#get_vissim_routes(vissim).write
generate_controllers(vissim)

puts "FINISHED"