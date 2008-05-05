require 'const'
require 'network'
require 'signal'
require 'vissim_elem'

# vissim element names. match anything that isn't the last quotation mark
NAMEPATTERN = '\"([^\"]*)\"'
SECTIONPATTERN = /-- ([^-:]+): --/ # section start

# sections, which are parsed from the network file
# and symbols for the methods, which handle them
SECTION_PARSERS = {
  'Links' => :parse_links, 
  'Connectors' => :parse_connectors, 
  'Signal Controllers (SC)' => :parse_controllers  
}

class Vissim
  attr_reader :connectors,:controllers
  def initialize inpfile = Default_network
    inp = IO.readlines(inpfile).map!{|line| line.strip}.delete_if{|line| line.empty?}
      
    # find relevant sections of the vissim file
    section_start = section_name = nil
    inp.each_with_index do |line, i| 
      next unless line =~ SECTIONPATTERN
      if section_start
        if parser = SECTION_PARSERS[section_name] 
          # found a parser interested in the section
          send parser, inp[section_start+2...i]
        end
        section_start = i
        section_name = $1
      else # first occurrence of section start
        section_start = i
        section_name = $1
      end
    end       
    
    # remove non-input links which cannot be reached
    @links_map.delete_if do |num, line|
      # a predecessor exists if there is a connector to this link
      not (line.input? or line.is_bus_input) and not @connectors.any?{|c| c.to == line}
    end
        
    # remove all outgoing connectors which no longer have a from link
    @connectors.delete_if{|c| link(c.from.number).nil?}
    
    # notify the links of connected links
    for conn in @connectors
      from_link = conn.from
      to_link = conn.to
      from_link.add_successor(to_link, conn)
    end
    
    if ARTERY
      # attempt to mark links as arterial
      # and note the direction of the link;
      # this is used by the signal optimization routines
      sc1 = ARTERY[:sc1][:scno]
      sc2 = ARTERY[:sc2][:scno]
      from1 = ARTERY[:sc1][:from_direction]
      from2 = ARTERY[:sc2][:from_direction] 

      # look for routes passing decisions Through
      require 'vissim_routes'
      routes = get_full_routes(self)
      
      puts "Found #{routes.size} routes"
      
      for route in routes.find_all{|r| r.decisions.map{|d| d.name}.include?("#{from1}#{sc1}")}
        puts route
      end
    end
  end
  def input_links; links.find_all{|l| l.input?}; end
  def exit_links; links.find_all{|l| l.exit?}; end
  def links; @links_map.values; end
  def link(number); @links_map[number]; end
  # parse signal controllers and their groups + heads
  def parse_controllers(inp)
    plans = begin
      DB["SELECT 
        INSECTS.Number As isnum, 
        PLANS.program,
        [Group Name] As grpname,
        [Group Number] As grpnum, 
        #{USEDOGS ? 'priority,' : ''}
        [Red End] As red_end, 
        [Green End] As green_end, 
        [Red-Amber] As tred_amber, 
        Amber As tamber
       FROM [plans$] As PLANS
       INNER JOIN [intersections$] As INSECTS ON PLANS.Intersection = INSECTS.Name
       WHERE PLANS.PROGRAM = '#{PROGRAM}'"].all      
    rescue; []; end # No signal plans found
    
    scinfo = begin
      DB["SELECT 
        Number As isnum,
        PROGRAMS.[Cycle Time] As cycle_time,
        offset
       FROM (([offsets$] As OFFSETS
       INNER JOIN [intersections$] As INSECTS ON INSECTS.Name = OFFSETS.Intersection)
       INNER JOIN [programs$] AS PROGRAMS ON OFFSETS.Program = PROGRAMS.Name)
       WHERE OFFSETS.PROGRAM = '#{PROGRAM}'"].all
    rescue; []; end # No signal controllers found
    
    @controllers = []   
    
    inp.each_with_index do |scline, i|  
      next unless scline =~ /^SCJ (\d+)\s+NAME #{NAMEPATTERN}/
        
      sc = SignalController.new!($1.to_i,
        :name => $2, 
        :cycle_time => $3, 
        :offset => $4)
      
      # parse signal groups and signal heads
      # until the next signal controller statement is found or we run out of lines
      inp[i+1..-1].each do |line|
        break if line =~ /^SCJ/ # start of new SC definition
        
        # find the signal groups
        if line =~ /^SIGNAL_GROUP\s+(\d+)\s+NAME\s+#{NAMEPATTERN}\s+SCJ #{sc.number}.+TRED_AMBER\s+([\d\.]+)\s+TAMBER\s+([\d\.]+)/
          
          sc.add_group($1.to_i,
            :name => $2,
            :red_end => $3,
            :green_end => $4,
            :tred_amber => $5,
            :tamber => $6)
          
        elsif line =~ /SIGNAL_HEAD\s+(\d+)\s+NAME\s+#{NAMEPATTERN}\s+LABEL\s+0.00\s+0.00\s+SCJ\s+#{sc.number}\s+GROUP\s+(\d+)/
          num = $1.to_i
          name = $2
          grpnum = $3.to_i
          grp = sc.group(grpnum)
          
          raise "Signal head '#{name}' is missing its group #{grpnum} at controller '#{sc}'" unless grp
          
          # optionally match against the TYPE flag (eg. left arrow)
          line =~ /POSITION LINK\s+(\d+)\s+LANE\s+(\d)\s+AT\s+(\d+\.\d+)/
                                
          grp.add_head(num, 
            :name => name, 
            :position_link => link($1.to_i), 
            :lane => $2.to_i, 
            :at => $3.to_f)
        end
      end
      
      # enrich this signal controller with signal plans, if any            
      scrow = scinfo.find{|r| r[:isnum] == sc.number}      
      sc.update(scrow.retain_keys!(:cycle_time, :offset)) if scrow
      
      for row in plans.find_all{|r| r[:isnum] == sc.number}
        grp = sc.group(row[:grpnum].to_i)
        grp.update(row.retain_keys!(:red_end, :green_end, :tred_amber, :tamber, :priority))
      end
      
      @controllers << sc
    end
  end
  def parse_connectors(inp)
    @connectors = []
    
    inp.each_with_index do |conn_line, i|
      next unless conn_line =~ /^CONNECTOR\s+(\d+) NAME #{NAMEPATTERN}/
      number = $1.to_i
      name = $2
      
      i += 1 
      # number always in the first line after conn declaration
      # example: FROM LINK 28 LANES 1 2 AT 819.728
      inp[i] =~ /FROM LINK (\d+) LANES (\d )+/
      from_link = link($1.to_i)
      lanes = $2.split(' ')
  
      # next comes the knot definitions
      # and the the to-link
      i += 1 until inp[i] =~ /TO LINK (\d+)/
  
      to_link = link($1.to_i)
      
      # look for any closed to declarations
      # (they are mandatory)
      i += 1 until inp[i].nil? or inp[i] =~ /(CLOSED|CONNECTOR)/
      
      closed_to = if $1 == "CLOSED"
        inp[i+1] =~ /VEHICLE_CLASSES ([\d ]+)+/
        $1.split(' ').map{|str| str.to_i}
      else; []; end
      
      conn = Connector.new!(number, 
        :name => name, 
        :from => from_link, 
        :to => to_link, 
        :lanes => lanes, 
        :closed_to => closed_to)
      
      # only links which can be reached are cars and trucks are interesting  
      next if conn.closed_to_any?(Cars_and_trucks)
      
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
      
      @connectors << conn
    end
  end
  def parse_links(inp)

    # we do a lot of lookups on link numbers later on
    # this map will save time.
    @links_map = {}
    
    inp.each_with_index do |line, i|
      next unless line =~ /^LINK\s+(\d+) NAME #{NAMEPATTERN}/
      
      number = $1.to_i
      opts = {:name => $2}
      
      inp[i+1] =~ /LENGTH\s+(\d+\.\d+)\s+LANES\s+(\d+)/
      opts[:length] = $1.to_f
      opts[:lanes] = $2.to_i
      
      inp[i+2..-1].each do |line2|
        break if line2 =~ /^LINK/
        if line2 =~ /(FROM|TO)\s+(\d+.\d+)\s+(\d+.\d+)/
          opts["#{$1.downcase}_point".to_sym] = Point.new!(:x => $2.to_f, :y => $3.to_f)
        end
      end
  
      @links_map[number] = Link.new!(number, opts)
    end
    
    # enrich the existing link objects with data from the database
    for row in LINKS.find_all{|r| r[:link_type] == 'IN'} # dataset.filter doesn't work...
      next unless link = link(row[:number].to_i)
      link.update row.retain_keys!(:from, :link_type, :name)
    end
    
    begin # fetch bus inputs
      BUSES.each do |businputrow|
        link(businputrow[:input_link].to_i).is_bus_input = true
      end
    rescue; end # skip bus input links; table was not defined (see BUSES)    
  end
  def to_s
    str = "Controllers: #{@controllers.size}\n"
    str << "Links: #{@links_map.size}\n"
    str << "Connectors: #{@connectors.size}"    
    str
  end
end

if __FILE__ == $0
  vissim = Vissim.new
  
  #  for sc in vissim.controllers.find_all{|x| x.has_plans?}.sort
  #    puts sc
  #  end
end
