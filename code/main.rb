require 'vissim'
require 'turningprob'
require 'vissim_input'


vissim = Vissim.new(Default_network)

get_inputs(vissim).write
#puts get_vissim_routes(vissim).to_vissim
get_vissim_routes(vissim).write
require 'measurements'
require 'vap'