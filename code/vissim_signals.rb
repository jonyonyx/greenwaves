require 'vissim'
#require 'profile'

puts "BEGIN"

vissim = Vissim.new("#{Vissim_dir}tilpasset_model.inp")

puts "Signal controllers: #{vissim.sc_map.length}"

puts "END"