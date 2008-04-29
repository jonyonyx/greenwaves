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
      str << "#{rd.to_vissim(i+1)}"
    end
    str
  end
end
class RoutingDecision
  attr_reader :input_link, :veh_type
  def initialize
    @routes = []
  end
  def add_route route, fractions
    raise "Warning: starting link (#{route.start}) of route was different 
             from the input link of the routing decision(#{@input_link})!" unless route.start == @input_link
      
    raise "Wrong vehicle types detected among fractions, expecting only #{@veh_type}" if fractions.any?{|f| f.veh_type != @veh_type}
    raise "Wrong number of fractions, #{fractions.size}, expected #{@time_intervals.size}\n#{fractions.sort.join("\n")}" unless fractions.size == @time_intervals.size
    @routes << [route, fractions]
  end
  def to_vissim i
    str = "ROUTING_DECISION #{i} NAME \"#{@desc ? @desc : (@veh_type)} from #{@input_link}\" LABEL  0.00 0.00\n"
    # AT must be AFTER the input point
    # place decisions as early as possibly to give vehicles time to changes lanes
    
    str << "     LINK #{@input_link.number} AT #{@input_link.length * 0.2}\n"
    str << "     TIME #{@time_intervals.sort.map{|int|int.to_vissim}.join(' ')}\n"
    str << "     NODE 0\n"
    str << "      VEHICLE_CLASSES #{Type_map[@veh_type]}\n"
    
    j = 1
    
    for route, fractions in @routes
      
      exit_link = route.exit
      # dump vehicles late on the route exit link to avoid placing the destination
      # upstream of the last connector
      str << "     ROUTE     #{j}  DESTINATION LINK #{exit_link.number}  AT   #{exit_link.length * 0.1}\n"
      str << "     #{fractions.sort.map{|f|f.to_vissim}.join(' ')}\n"
      str << "     OVER #{route.to_vissim}\n"
      j += 1
    end
    str
  end
end
class QueueCounter < VissimElem
  attr_reader :link
  def to_s
    "#{super} at #{@link}" 
  end
end
class TravelTime < VissimElem
  attr_reader :from,:to,:vehicle_classes
  def to_s
    "#{super} from #{@from} to #{@to}"
  end
  def <=>(tt2)
    (@from == tt2.from) ? (@to <=> tt2.to) : (@from <=> tt2.from)
  end
end
class Node < VissimElem
  
end

Name_pat = "([,\\w\\s\\d\\/']*)" # pattern for names in vissim network files

class Vissim
  attr_reader :links_map,:conn_map,:sc_map,:tt_map,:node_map,:qc_map,:links,:input_links,:exit_links
  def initialize inpfile
    inpfile = inpfile
    inp = IO.readlines inpfile

    @links_map = {}
    # first parse all LINKS
    parse_links(inp) do |l|
      @links_map[l.number] = l
    end
    
    # enrich the existing object with data from the database
    for row in exec_query "SELECT NUMBER, Intersection AS NAME, [FROM], TYPE FROM [links$] As LINKS WHERE TYPE = 'IN'"
      number = row['NUMBER'].to_i
    
      next unless @links_map.has_key?(number)
      links_map[number].update :from => row['FROM'], :link_type => row['TYPE'], :name => row['NAME']
    end
    
    begin # fetch bus inputs
      for businputlinknum in exec_query('SELECT [In Link] FROM [buses$]').flatten.map{|f| f.to_i}.uniq
        links_map[businputlinknum].is_bus_input = true
      end
    rescue
      # skip bus input links
    end

    @conn_map = {}
    #now get the connectors and join them up using the links
    parse_connectors(inp) do |conn|
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
      from_link.add_successor to_link, conn
    end
    
    @links = @links_map.values
    
    @input_links = @links.find_all{|l| l.input?}
    @exit_links = @links.find_all{|l| l.exit?}
    
    begin
      plan_sql = "SELECT 
        INSECTS.Number As ISNUM, 
        PLANS.PROGRAM,
        [Group Name] As GRPNAME,
        [Group Number] As GRPNUM, 
        #{USEDOGS ? 'PRIORITY,' : ''}
        [Red End] As RED_END, 
        [Green End] As GREEN_END, 
        [Red-Amber] As TRED_AMBER, 
        Amber As TAMBER
       FROM [plans$] As PLANS
       INNER JOIN [intersections$] As INSECTS ON PLANS.Intersection = INSECTS.Name
       WHERE PLANS.PROGRAM = '#{PROGRAM}'"

      plans = exec_query(plan_sql)
    rescue
      puts "No signal plans found."
      plans = []
    end
    
    begin
      sc_sql = "SELECT 
        Number As ISNUM,
        PROGRAMS.[Cycle Time] As CYCLE_TIME,
        OFFSET
       FROM (([offsets$] As OFFSETS
       INNER JOIN [intersections$] As INSECTS ON INSECTS.Name = OFFSETS.Intersection)
       INNER JOIN [programs$] AS PROGRAMS ON OFFSETS.Program = PROGRAMS.Name)
       WHERE OFFSETS.PROGRAM = '#{PROGRAM}'"
      
      scinfo = exec_query(sc_sql)
    rescue
      puts "No signal controllers found."
      scinfo = []      
    end
    
    @sc_map = {}
    parse_controllers(inp) do |sc|
      # enrich this signal controller with signal plans, if any
      
      scrow = scinfo.find{|r| r['ISNUM'] == sc.number}      
      sc.update(:cycle_time => scrow['CYCLE_TIME'].to_i, :offset => scrow['OFFSET']) if scrow
      
      for row in plans.find_all{|r| r['ISNUM'] == sc.number}
        grp = sc.groups[row['GRPNUM'].to_i]
        grp.update(:red_end => row['RED_END'].to_i,
          :green_end => row['GREEN_END'].to_i,
          :tred_amber => row['TRED_AMBER'].to_i,
          :tamber => row['TAMBER'].to_i,
          :priority => row['PRIORITY'])
      end
      
      @sc_map[sc.number] = sc
    end
    
    @qc_map = {}    
    parse_queuecounters(inp) do |qcnum, linknum|
      qc = QueueCounter.new(qcnum, :link => @links.find{|l| l.number == linknum})
      @qc_map[qc.number] = qc
    end
    
    @node_map = {}
    parse_nodes(inp) do |num,name, coords|
      node = Node.new!(num, :name => name, :coords => coords)
      @node_map[node.number] = node
    end
    
    @tt_map = {}    
    parse_traveltimes(inp) do |num, name, fromnum, tonum, vcs|
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
  def parse_queuecounters(inp)
    i = 0
    while i < inp.length
      unless inp[i] =~ /^QUEUE_COUNTER (\d+)     LINK (\d+)/
        i += 1
        next
      end
      yield $1.to_i, $2.to_i
      i += 1
    end
  end
  def parse_traveltimes(inp)
    i = 0
    while i < inp.length
      unless inp[i] =~ /^TRAVEL_TIME   (\d+) NAME \"#{Name_pat}\"/
        i += 1
        next
      end
      
      num = $1.to_i
      name = $2
            
      i += 1
      
      inp[i] =~ /FROM\s+LINK\s+(\d+)\s+AT\s+\d+.\d+\s+TO\s+LINK\s+(\d+)\s+AT\s+\d+.\d+\s+SMOOTHING\s+\d.\d+\s+VEHICLE_CLASSES\s+([\d ]+)+/
      
      yield num, name, $1.to_i, $2.to_i, $3.split(' ').map{|vcs| vcs.to_i}
      i += 1
    end
  end
  def parse_nodes(inp)
    i = 0
    while i < inp.length
      unless inp[i] =~ /NODE\s+(\d+)\s+NAME\s+\"#{Name_pat}\"/
        i += 1
        next
      end
      
      num = $1.to_i
      name = $2
      
      i += 2
      
      inp[i] =~ /NETWORK_AREA (\d+)\s+([\d\. ]+)+/
      
      len = $1.to_i
      flatcoords = $2.split(/\s+/).map{|s| s.to_f}
      
      coords = flatcoords.chunk len
      
      yield num, name, coords
      i += 1
    end
  end
  # returns signal controllers and their groups.
  def parse_controllers(inp)
    i = 0
    while i < inp.length
      unless inp[i] =~ /^SCJ (\d+)\s+NAME \"#{Name_pat}\"/ #\s+TYPE FIXED_TIME\s+CYCLE_TIME ([\d\.]+)\s+ OFFSET ([\d\.])
        i += 1
        next
      end
      
      ctrl = SignalController.new!($1.to_i,
        :name => $2, 
        :cycle_time => $3, 
        :offset => $4)
      
      i += 1
      # parse signal groups and signal heads
      # until the next signal controller statement is found or we run out of lines
      until inp[i] =~ /^SCJ/ or i > inp.length
        
        # find the signal groups
        if inp[i] =~ /^SIGNAL_GROUP (\d+)  NAME \"#{Name_pat}\"  SCJ #{ctrl.number}.+TRED_AMBER ([\d\.]+)\s+TAMBER ([\d\.]+)/
          
          grp = ctrl.add_group($1.to_i,
            :name => $2,
            :red_end => $3,
            :green_end => $4,
            :tred_amber => $5,
            :tamber => $6)
          
        elsif inp[i] =~ /SIGNAL_HEAD (\d+)\s+NAME\s+\"#{Name_pat}"\s+LABEL  0.00 0.00\s+SCJ #{ctrl.number}\s+GROUP (\d+)/
          num = $1.to_i
          name = $2
          grpnum = $3.to_i
          grp = ctrl.groups[grpnum]
          
          raise "Signal head '#{name}' is missing its group #{grpnum} at controller '#{ctrl}'" unless grp
          
          # optionally match against the TYPE flag (eg. left arrow)
          inp[i] =~ /POSITION LINK (\d+)\s+LANE (\d)\s+AT (\d+\.\d+)/
                                
          grp.add_head(num, 
            :name => name, 
            :position_link => @links_map[$1.to_i], 
            :lane => $2.to_i, 
            :at => $3.to_f)
        end      
      
        i += 1
      end
      
      yield ctrl
    end
  end
  def parse_connectors(inp)
    i = 0
    while i < inp.length
      unless inp[i] =~ /^CONNECTOR\s+(\d+) NAME \"#{Name_pat}\"/
        i += 1
        next
      end
  
      number = $1.to_i
      name = $2
  
      i += 1
  
      # number always in the first line after conn declaration
      # example: FROM LINK 28 LANES 1 2 AT 819.728
      inp[i] =~ /FROM LINK (\d+) LANES (\d )+/
      from_link = @links_map[$1.to_i]
      lanes = $2.split(' ')
  
      # next comes the knot definitions
      # and the the to-link
      i += 1 until inp[i] =~ /TO LINK (\d+)/
  
      to_link = @links_map[$1.to_i]
      
      # look for any closed to declarations
      # (they are mandatory)
      i += 1 until inp[i] == "" or inp[i] =~ /(CLOSED|CONNECTOR|-- .+ --)/
      
      closed_to = if $1 == "CLOSED"
        inp[i+1] =~ /VEHICLE_CLASSES ([\d ]+)+/
        $1.split(' ').map{|str| str.to_i}
      else
        []
      end
  
      conn = Connector.new!(number, 
        :name => name, 
        :from => from_link, 
        :to => to_link, 
        :lanes => lanes, 
        :closed_to => closed_to) 
      
      # check if this connector is a decision
      if name =~ /([NSEW])(\d+)([LTR])(\d+)?/
        # only one connector object represents each physical connector
        conn.dec = Decision.new!(
          :from => $1,
          :intersection => $2.to_i,
          :turning_motion => $3,
          :weight => ($4 ? $4.to_i : nil),  # for multiple connectors in same turning motion
          :connector => conn) 
      end
      
      yield conn
    end
  end
  def parse_links(inp)
    i = 0
    while i < inp.length
      unless inp[i] =~ /^LINK\s+(\d+) NAME \"#{Name_pat}\"/
        i += 1
        next
      end
      
      number = $1.to_i
      name = $2
      
      i += 1
      
      inp[i] =~ /LENGTH\s+(\d+\.\d+) LANES\s+(\d+)/
  
      yield Link.new!(number,
        :name => name,
        :length => $1.to_f,
        :lanes => $2.to_i)
    end
  end
end

if __FILE__ == $0
  vissim = Vissim.new(Default_network)
  
  puts vissim.links_map[51].adjacent
  
  #  for sc in vissim.sc_map.values.sort
  #    puts sc.to_s
  #  end
end