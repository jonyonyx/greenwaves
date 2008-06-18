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
  vissim = get_vissim_instance
  get_inputs(vissim).write
  get_decisions_with_fractions(vissim).write
  generate_controllers(vissim, :dogs_enabled => true)  
#end  
#opts.on('vap'){generate_controllers(get_vissim_instance)}
#opts.on('inputs'){get_inputs(get_vissim_instance).write}
#opts.on('routes'){get_vissim_routes(get_vissim_instance).write}
#
#opts.parse(ARGV)


