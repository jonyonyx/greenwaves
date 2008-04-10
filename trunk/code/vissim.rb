require 'const'
require 'network'
require 'signal'
require 'vissim_elem'

class RoutingDecisions < Array
  include VissimOutput
  def section_header; /^-- Routing Decisions: --/; end
  def to_vissim
    str = ''
    each_with_index do |rd,i|
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
    # place decisions as early as possibly to give vehicles time to changes lanes
    
    str += "     LINK #{@input_link.number} AT #{@input_link.length * 0.2}\n"
    str += "     TIME FROM 0.0 UNTIL 99999.0\n"
    str += "     NODE 0\n"
    str += "      VEHICLE_CLASSES #{Type_map[@veh_type]}\n"
    
    @routes.each_with_index do |route_info,j|
      route = route_info['ROUTE']
      exit_link = route.exit
      # dump vehicles late on the route exit link to avoid placing the destination
      # upstream of the last connector
      str += "     ROUTE     #{j+1}  DESTINATION LINK #{exit_link.number}  AT   #{exit_link.length * 0.1}\n"
      str += "     FRACTION #{route_info['FRACTION']}\n"
      str += "     OVER #{route.to_vissim}\n"
    end
    str
  end
end
class QueueCounter < VissimElem
  attr_reader :link
  def update opts
    @link = opts[:link]
  end
  def to_s
    "#{super} at #{@link}" 
  end
end
class TravelTime < VissimElem
  attr_reader :from,:to,:vehicle_classes
  def update opts
    @from = opts[:from]
    @to = opts[:to]
    @vehicle_classes = opts[:veh_classes].map{|num| Type_map_rev[num]}
  end
  def to_s
    "#{super} from #{@from} to #{@to}"
  end
  def <=>(tt2)
    (@from == tt2.from) ? (@to <=> tt2.to) : (@from <=> tt2.from)
  end
end
class Node < VissimElem; end

Name_pat = "([,\\w\\s\\d\\/']*)" # pattern for names in vissim network files

class Vissim
  attr_reader :links_map,:conn_map,:sc_map,:tt_map,:node_map,:qc_map,:inp,:links,:input_links,:exit_links
  def initialize inpfile
    @inpfile = inpfile
    @inp = IO.readlines inpfile

    @links_map = {}
    # first parse all LINKS
    parse_links do |l|
      @links_map[l.number] = l
    end
    
    # enrich the existing object with data from the database
    for row in exec_query "SELECT NUMBER, Intersection AS NAME, [FROM], TYPE FROM [links$] As LINKS WHERE TYPE = 'IN'"    
      number = row['NUMBER'].to_i
    
      next unless links_map.has_key?(number)
      links_map[number].update row    
    end
    
    for businputlinknum in exec_query('SELECT [In Link] FROM [buses$]').flatten.map{|f| f.to_i}.uniq
      links_map[businputlinknum].is_bus_input = true
    end

    @conn_map = {}
    #now get the connectors and join them up using the links
    parse_connectors do |conn|
      # found a connection, join up the links
      unless conn.closed_to_any?(Cars_and_trucks)
        # only links which can be reached are cars and trucks are interesting
      
        @conn_map[conn.number] = conn
      end
    end
        
    # remove non-input links which cannot be reached by cars and trucks
    for link in @links_map.values
      next if link.input? or link.is_bus_input
      conns = @conn_map.values.find_all{|c| c.to == link}
      next unless conns.empty? # a predecessor exists if there is a connector to this link
      @links_map.delete(link.number)
        
      # remove all outgoing connectors from this link
      for conn in @conn_map.values.find_all{|c| c.from == link}
        @conn_map.delete(conn.number)
      end
    end
    
    # notify the links of connected links
    for conn in @conn_map.values
      from_link = conn.from
      to_link = conn.to
      from_link.add :successor, to_link, conn
    end
    
    @links = @links_map.values
    
    @input_links = @links.find_all{|l| l.input?}
    @exit_links = @links.find_all{|l| l.exit?}
    
    @sc_map = {}
    parse_controllers do |sc|
      @sc_map[sc.number] = sc
    end
    
    @qc_map = {}    
    parse_queuecounters do |qcnum, linknum|
      qc = QueueCounter.new(qcnum, :link => @links.find{|l| l.number == linknum})
      @qc_map[qc.number] = qc
    end
    
    @node_map = {}
    parse_nodes do |num,name|
      node = Node.new(num, 'NAME' => name)
      @node_map[node.number] = node
    end
    
    @tt_map = {}    
    parse_traveltimes do |num, name, fromnum, tonum, vcs|
      from = @links.find{|l| l.number == fromnum}
      to = @links.find{|l| l.number == tonum}
      raise "From link with number #{fromnum} not found" unless from
      raise "To link with number #{tonum} not found" unless to
      
      @tt_map[num] = TravelTime.new(num, 'NAME' => name ,:from => from, :to => to, :veh_classes => vcs)
    end
  end
  def to_s
    str = ''    
    for sc in @sc_map.values
      str += "#{sc}\n"
      for grp in sc.groups.values
        str += "\t#{grp}\n"
        for head in grp.heads
          str += "\t\t#{head}\n"
        end
      end
    end
    str
  end
  def parse_queuecounters
    i = 0
    while i < @inp.length
      unless @inp[i] =~ /^QUEUE_COUNTER (\d+)     LINK (\d+)/
        i += 1
        next
      end
      yield $1.to_i, $2.to_i
      i += 1
    end
  end
  def parse_traveltimes
    i = 0
    while i < @inp.length
      unless @inp[i] =~ /^TRAVEL_TIME   (\d+) NAME \"#{Name_pat}\"/
        i += 1
        next
      end
      
      num = $1.to_i
      name = $2
            
      i += 1
      
      @inp[i] =~ /FROM\s+LINK\s+(\d+)\s+AT\s+\d+.\d+\s+TO\s+LINK\s+(\d+)\s+AT\s+\d+.\d+\s+SMOOTHING\s+\d.\d+\s+VEHICLE_CLASSES\s+([\d ]+)+/
      
      yield num, name, $1.to_i, $2.to_i, $3.split(' ').map{|vcs| vcs.to_i}
      i += 1
    end
  end
  def parse_nodes
    i = 0
    while i < @inp.length
      unless @inp[i] =~ /NODE\s+(\d+)\s+NAME\s+\"#{Name_pat}\"/
        i += 1
        next
      end
      
      yield $1.to_i, $2
      i += 1
    end
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
          
          raise "Signal head '#{head}' is missing its group #{grpnum} at controller '#{ctrl}'" unless grp
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
      
      # look for any closed to declarations
      # (they are mandatory)
      i += 1 until @inp[i] == "" or @inp[i] =~ /(CLOSED|CONNECTOR|-- .+ --)/
      
      closed_to = if $1 == "CLOSED"
        @inp[i+1] =~ /VEHICLE_CLASSES ([\d ]+)+/
        $1.split(' ').map{|str| str.to_i}
      else
        []
      end
  
      yield Connector.new(number,name,from_link,to_link,lanes,closed_to)     
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
      
      @inp[i] =~ /LENGTH\s+(\d+\.\d+) LANES\s+(\d+)/
      
      opts = {'NAME' => name, 'LENGTH' => $1.to_f, 'LANES' => $2.to_i}
  
      yield Link.new(number,opts)
    end
  end
end

if __FILE__ == $0
  vissim = Vissim.new(Default_network)
  
  puts vissim.node_map.values
end