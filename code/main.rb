require 'vissim'
require 'turningprob'
require 'vissim_input'


vissim = Vissim.new("#{Vissim_dir}tilpasset_model.inp")

#get_inputs.write
puts get_vissim_routes(vissim).to_vissim
#require 'vap'