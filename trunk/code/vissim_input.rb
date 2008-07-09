require 'const'
require 'vissim_output'
require 'vissim'

class Inputs < Array
  include VissimOutput
  def section_header; /^-- Inputs: --/; end
  def to_vissim
    str = ''
    inputnum = 1
    tbegin = map{|i| i.interval}.min.tstart
    sort.each do |input|
      link = input.link
      
      fraction = input.fraction
      interval = input.interval
      veh_type = fraction.veh_type
      
      str << "INPUT #{inputnum}\n" +
        "      NAME \"#{veh_type.to_s.capitalize} from #{link.from_direction}#{link.name.empty? ? '' : " ON " + link.name}\" LABEL  0.00 0.00\n" +
        "      LINK #{link.number} Q EXACT #{fraction.quantity.round.to_f} COMPOSITION #{Type_map[veh_type]}\n" +
        "      TIME FROM #{interval.tstart - tbegin} UNTIL #{interval.tend - tbegin}\n"
        
      inputnum += 1
    end
    str
  end
end

class Input
  attr_reader :link,:fraction,:interval
  def initialize link, fraction
    @link, @fraction = link, fraction
    @interval = fraction.interval
  end
  def to_s
    "Input on #{@link}: #{@fraction}"
  end
  
  # sort by time intervals then vehicle types
  def <=>(other)
    if @interval == other.interval
      @fraction.veh_type.to_s <=> other.fraction.veh_type.to_s
    else
      @interval <=> other.interval
    end
  end
end

class Vissim
  def get_inputs program
    
    inputs = Inputs.new
    
    @decisions.group_by{|dec|dec.original_approach}.each do |approach,decisions|      
      
      # find a *start* link that reaches all decisions at the approach without
      # traversing other decisions      
      input_link = @start_links.find do |link|
        routes = find_routes(link,decisions)
        decisions.all?{|dec|routes.any?{|r|r.include?(dec)}} and routes.all?{|r|r.decisions.size == 1}
      end
      
      next if input_link.nil? # this approach is not an input and is fed by upstream decisions
      
      raise "Unable to locate link with number #{link_number}" unless input_link
        
      dp = DecisionPoint.new(decisions.first.from_direction,decisions.first.intersection)
      decisions.each{|dec|dp << dec}
      
      dp.time_intervals(program,false).each do |interval|
        [:cars,:trucks].each do |vehtype|
          fractions = decisions.map{|dec|dec.fractions.filter(interval,vehtype)}.flatten
          total_quantity = Fractions.sum(fractions) * INPUT_SCALING * (60/interval.resolution_in_minutes)
          
          combined_fraction = Decision::Fraction.new(interval,vehtype,total_quantity)
          inputs << Input.new(input_link,combined_fraction)
        end
      end
  
    end
  
    if program.repeat_first_interval
      # heating of the simulator
      time_offset = program.resolution * 60
      inputs.find_all{|i|i.interval.tstart == program.from}.each do |input|    
        newfraction = input.fraction.copy
        newfraction.interval.shift!(-time_offset)
        inputs << Input.new(input.link,newfraction)
      end
    end
    
    inputs
  end
end

if __FILE__ == $0
  puts "BEGIN"
  require 'cowi_tests'
  
  vissim = Vissim.new
  
  inputs = vissim.get_inputs MORNING
  #inputs.write
  #puts inputs.to_vissim
  
  puts "END"
end
