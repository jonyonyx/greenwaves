require 'vissim'
require 'turningprob'
require 'vissim_input'
require 'vap'

require 'cowi_tests'

program = AFTERNOON
vissim = Vissim.new
vissim.foreignadjust(true,'N2')
vissim.get_inputs(program).write
vissim.get_routing_decisions(program).write
vissim.controllers_with_plans.each do |sc|
  next unless sc.number == 1
  generate_controller sc,Vissim_dir,FIXED_TIME_PROGRAM_NAME[program]
end
