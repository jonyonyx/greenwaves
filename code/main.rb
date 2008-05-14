require 'vissim'
require 'turningprob'
require 'vissim_input'

vissim = Vissim.new

get_inputs(vissim).write
get_vissim_routes(vissim).write