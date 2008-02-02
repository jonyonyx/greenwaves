require 'const'

class Vissim
  attr_reader :links_map,:conn_map,:sc_map
  def initialize inpfile
    inp = IO.readlines(inpfile)

    @links_map = {}
    # first parse all LINKS
    parse_links(inp) do |link|
      @links_map[link.number] = link
    end

    @conn_map = {}
    #now get the connectors and join them up using the links
    parse_connectors(inp) do |conn|
      # found a connection, join up the links
      conn.from.add conn.to, conn  
      @conn_map[conn.number] = conn
    end
    
    @sc_map = {}
    parse_controllers(inp) do |sc|
      puts sc#.inspect
      @sc_map[sc.number] = sc
      for grp in sc.groups.values
        puts "\t#{grp}"
        for head in grp.heads
          puts "\t\t#{head}"
        end
      end
    end
  end
  # returns signal controllers and their groups.
  def parse_controllers inp    
    puts "parsing controllers"
    i = 0
    while i < inp.length
      unless inp[i] =~ /^SCJ (\d+)\s+NAME \"([\w\s\d\/]*)\"\s+TYPE (\w+)\s+CYCLE_TIME ([\d\.]+)\s+ OFFSET ([\d\.])/
        i += 1
        next
      end
      
      ctrl = SignalController.new($1.to_i,
        'NAME' => $2, 
        'TYPE' => $3, 
        'CYCLE_TIME' => $4, 
        'OFFSET' => $5)
      
      i += 1
      # parse signal groups and signal heads
      # until the next signal controller statement is found
      until inp[i] =~ /^SCJ/
        # find the signal groups
        if inp[i] =~ /^SIGNAL_GROUP (\d+)  NAME \"([,\w\s\d\/]*)\"  SCJ #{ctrl.number}  RED_END ([\d\.]+)  GREEN_END ([\d\.]+)  TRED_AMBER ([\d\.]+)  TAMBER ([\d\.]+)/
          
          grp = SignalGroup.new($1.to_i,
            'NAME' => $2,
            'RED_END' => $3,
            'GREEN_END' => $4,
            'TRED_AMBER' => $5,
            'TAMBER' => $6)
          ctrl.add grp
        elsif inp[i] =~ /SIGNAL_HEAD (\d+)\s+NAME \"([\w\s\d\/]*)\"\s+LABEL  0.00 0.00\s+SCJ #{ctrl.number}\s+GROUP (\d+)\s+POSITION LINK (\d+)\s+LANE (\d)/
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
  def parse_connectors inp
    i = 0
    while i < inp.length
      unless inp[i] =~ /^CONNECTOR\s+(\d+) NAME \"([\w\s\d]*)\"/
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
  
      yield Connector.new(number,name,from_link,to_link,lanes)     
    end
  end
  def parse_links inp    
    for line in inp
      next unless line =~ /^LINK\s+(\d+) NAME \"([\w\s\d]*)\"/
  
      yield Link.new($1.to_i,'NAME' => $2)
    end
  end
end


#puts Links[25060312].exit?
#puts Links[25060312].adjacent
#exit(0)