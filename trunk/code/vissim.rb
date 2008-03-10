require 'const'
require 'fileutils'
Name_pat = '([,\w\s\d\/]*)'

class VissimOutput  
  @@inpname = 'tilpasset_model.inp'
  @@inpfile = "#{Vissim_dir}#{@@inpname}"
  def write
    section_contents = to_vissim # make sure this can be successfully generated
    FileUtils.cp @@inpfile, "d:\\temp\\#{@@inpname}#{rand}" # backup
    inp = IO.readlines(@@inpfile)
    section_start = (0...inp.length).to_a.find{|i| inp[i] =~ section_header} + 1
    section_end = (section_start...inp.length).to_a.find{|i| inp[i] =~ /-- .+ --/ } - 1 
    File.open(@@inpfile, "w") do |file| 
      file << inp[0..section_start]
      file << section_contents
      file << inp[section_end..-1]
    end
    puts "Wrote #{self.class} to '#{@@inpfile}'"
  end
end
Early_decisions = [48131192,48131192]
class RoutingDecisions < VissimOutput
  def initialize
    @routing_decisions = []
  end
  def section_header; /^-- Routing Decisions: --/; end
  def add routing_decision
    @routing_decisions << routing_decision
  end
  def to_vissim
    str = ''
    @routing_decisions.each_with_index do |rd,i|
      str += "#{rd.to_vissim(i+1)}"
    end
    str
  end
end
class RoutingDecision
  attr_reader :input_link, :veh_type
  def initialize input_link, veh_type, desc = nil
    @desc = desc
    @input_link = input_link
    @veh_type = veh_type
    @routes = []
  end
  def add_route route, fraction
    raise "Warning: starting link (#{route.start}) of route was different 
             from the input link of the routing decision(#{@input_link})!" unless route.start == @input_link
      
    @routes << {'ROUTE' => route, 'FRACTION' => fraction}
  end
  def to_vissim i
    str = "ROUTING_DECISION #{i} NAME \"#{@desc ? @desc : (@veh_type)} from #{@input_link}\" LABEL  0.00 0.00\n"
    # AT must be AFTER the input point
    # link inputs are always defined in the end of the link
    str += "     LINK #{@input_link.number} AT 25.000\n"
    str += "     TIME FROM 0.0 UNTIL 99999.0\n"
    str += "     NODE 0\n"
    str += "      VEHICLE_CLASSES #{Type_map[@veh_type]}\n"
        
    @routes.each_with_index do |route_info,j|
      route = route_info['ROUTE']
      str += "     ROUTE     #{j+1}  DESTINATION LINK #{route.exit.number}  AT   7.500\n"
      str += "     FRACTION #{route_info['FRACTION']}\n"
      str += "     OVER #{route.to_vissim}\n"
    end
    str
  end
end  

class Inputs < VissimOutput
  def initialize t_start, t_end
    @t_start = t_start
    @t_end = t_end
    @inputs = []
  end
  def section_header; /^-- Inputs: --/; end
  def add link, veh_type, t_end, quantity, desc = nil
    @inputs << {'LINK' => link, 'TYPE' => veh_type, 'COMP' => Type_map[veh_type], 'TEND' => t_end, 'Q' => quantity, 'DESC' => desc}
  end
  def to_vissim
    str = ''
    @inputs.each_with_index do |input, input_num|  
      link = input['LINK']
      
      if input['TEND']
        t = input['TEND']
        t_begin = t - Res*60
        q = input['Q']
      else
        # no TEND indicates this is a bus input
        t = @t_end
        t_begin = @t_start
        # bus frequencies are given by the hour so scale it
        q = input['Q'] * (t.hour - t_begin.hour) # assume t_begin .. t_end in the same day
      end
      
      q = q * INPUT_FACTOR
      
      str += "INPUT #{input_num+1}\n" +
        "      NAME \"#{input['DESC'] ? input['DESC'] : input['TYPE']} from #{link.from} on #{link.name}\" LABEL  0.00 0.00\n" +
        "      LINK #{link.number} Q #{q} COMPOSITION #{input['COMP']}\n" +
        "      TIME FROM #{t_begin - @t_start} UNTIL #{t - @t_start}\n"
    end
    str
  end
end

class Vissim
  attr_reader :links_map,:conn_map,:sc_map,:inp
  def initialize inpfile
    @inpfile = inpfile
    @inp = IO.readlines(inpfile)

    @links_map = {}
    # first parse all LINKS
    parse_links do |link|
      @links_map[link.number] = link
    end

    @conn_map = {}
    #now get the connectors and join them up using the links
    parse_connectors do |conn|
      # found a connection, join up the links
      conn.from.add conn.to, conn  
      @conn_map[conn.number] = conn
    end
    
    @sc_map = {}
    parse_controllers do |sc|
      @sc_map[sc.number] = sc
    end
  end
  def to_s
    str = ''    
    for sc in @sc_map.values
      for grp in sc.groups.values
        str += "\t#{grp}\n"
        for head in grp.heads
          str += "\t\t#{head}\n"
        end
      end
    end
    str
  end
  # returns signal controllers and their groups.
  def parse_controllers
    i = 0
    while i < @inp.length
      unless @inp[i] =~ /^SCJ (\d+)\s+NAME \"#{Name_pat}\"\s+TYPE FIXED_TIME\s+CYCLE_TIME ([\d\.]+)\s+ OFFSET ([\d\.])/
        i += 1
        next
      end
      
      ctrl = SignalController.new($1.to_i,
        'NAME' => $2, 
        'CYCLE_TIME' => $3, 
        'OFFSET' => $4)
      
      i += 1
      # parse signal groups and signal heads
      # until the next signal controller statement is found
      until @inp[i] =~ /^SCJ/
        # find the signal groups
        if @inp[i] =~ /^SIGNAL_GROUP (\d+)  NAME \"#{Name_pat}\"  SCJ #{ctrl.number}  RED_END ([\d\.]+)  GREEN_END ([\d\.]+)  TRED_AMBER ([\d\.]+)  TAMBER ([\d\.]+)/
          
          grp = SignalGroup.new($1.to_i,
            'NAME' => $2,
            'RED_END' => $3,
            'GREEN_END' => $4,
            'TRED_AMBER' => $5,
            'TAMBER' => $6)
          ctrl.add grp
        elsif @inp[i] =~ /SIGNAL_HEAD (\d+)\s+NAME \"#{Name_pat}\"\s+LABEL  0.00 0.00\s+SCJ #{ctrl.number}\s+GROUP (\d+)\s+POSITION LINK (\d+)\s+LANE (\d)/
          head = SignalHead.new($1.to_i, 'NAME' => $2, 'POSITION LINK' => $4, 'LANE' => $5)
          grpnum = $3.to_i
          grp = ctrl.groups[grpnum]
          
          raise "Warning: signal head '#{head}' is missing its group #{grpnum} at controller '#{ctrl}'" unless grp
          grp.add(head) 
        end      
      
        i += 1
      end
      
      yield ctrl
    end
  end
  def parse_connectors
    i = 0
    while i < @inp.length
      unless @inp[i] =~ /^CONNECTOR\s+(\d+) NAME \"#{Name_pat}\"/
        i += 1
        next
      end
  
      number = $1.to_i
      name = $2
  
      i += 1
  
      # number always in the first line after conn declaration
      # example: FROM LINK 28 LANES 1 2 AT 819.728
      @inp[i] =~ /FROM LINK (\d+) LANES (\d )+/
      from_link = @links_map[$1.to_i]
      lanes = $2.split(' ')
  
      # next comes the knot definitions
      # and the the to-link
      i += 1 until @inp[i] =~ /TO LINK (\d+)/
  
      to_link = @links_map[$1.to_i]
  
      yield Connector.new(number,name,from_link,to_link,lanes)     
    end
  end
  def parse_links    
    i = 0
    while i < @inp.length
      unless @inp[i] =~ /^LINK\s+(\d+) NAME \"#{Name_pat}\"/
        i += 1
        next
      end
      
      number = $1.to_i
      name = $2
      
      i += 1
      
      @inp[i] =~ /LANES  (\d+)/
  
      yield Link.new(number,'NAME' => name, 'LANES' => $1)
    end
  end
end
