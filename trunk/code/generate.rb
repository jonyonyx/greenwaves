require 'vissim'
require 'turningprob'
require 'vissim_input'
require 'vap'
require 'optparse'

def usage
  puts "Usage: #{$0.split(File::SEPARATOR).last} [all] | [vap | input | routes]"
end

def get_vissim_instance
  @vissim ||= Vissim.new
end

#opts = OptionParser.new
#opts.on('-h','--help') {usage}
#opts.on('all') do 
require 'cowi_tests'

vissim = get_vissim_instance
#vissim.countadjust(%w{N2})
vissim.foreignadjust
get_inputs(vissim, MORNING).write
get_routing_decisions(vissim, MORNING).write
vissim.controllers_with_plans.each do |sc|
  generate_controller sc,Vissim_dir,'M80'
end
#end
#opts.on('vap'){generate_controllers(get_vissim_instance)}
#opts.on('inputs'){get_inputs(get_vissim_instance).write}
#opts.on('routes'){get_vissim_routes(get_vissim_instance).write}
#
#opts.parse(ARGV)


