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
  attr_reader :connectors,:decisions,:controllers
  def initialize inpfile = Default_network
    inp = IO.readlines(inpfile).map!{|link| link.strip}.delete_if{|link| link.empty?}
      
    # find relevant sections of the vissim file
    section_start = section_name = nil
    inp.each_with_index do |link, i| 
      next unless link =~ SECTIONPATTERN
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
    @links_map.delete_if do |n,link|
      # a predecessor exists if there is a connector to this link
      not (link.input? or link.is_bus_input) and not @connectors.any?{|c| c.to_link == link}
    end
        
    # remove all outgoing connectors which no longer have a from link
    @connectors.delete_if{|c| @links_map[c.from_link.number].nil?}
    @decisions = @connectors.find_all{|c| c.instance_of?(Decision)}
    
    # notify the links of connected links
    for conn in @connectors
      from_link = conn.from_link
      to_link = conn.to_link
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
      
      artery_decisions = @decisions.find_all do |d| 
        (sc1..sc2) === d.intersection and 
          d.turning_motion == "T" and
          d.from_direction == from1
      end
      
      for route in routes.find_all{|r| artery_decisions.all?{|d| r.connectors.include?(d)}}
        puts route.to_vissim
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
    
    while scline = inp.shift
      next unless scline =~ /^SCJ (\d+)\s+NAME #{NAMEPATTERN}/
        
      sc = SignalController.new!($1.to_i, :name => $2)
      
      # parse signal groups and signal heads
      # until the next signal controller statement is found or we run out of lines
      while line = inp.shift
        if line =~ /^SCJ/ # start of new SC definition
          inp.insert(0,line) # put line back in front
          break
        end
        
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
          opts = {:name => $2}
          grpnum = $3.to_i
          grp = sc.group(grpnum)
          
          raise "Signal head '#{opts[:name]}' is missing its group #{grpnum} at controller '#{sc}'" unless grp
          
          # optionally match against the TYPE flag (eg. left arrow)
          line =~ /POSITION LINK\s+(\d+)\s+LANE\s+(\d)\s+AT\s+(\d+\.\d+)/
                                
          opts[:position_link] = link($1.to_i)
          opts[:lane] = $2.to_i
          opts[:at] = $3.to_f
          
          grp.add_head(num, opts)
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
    
    while conn_line = inp.shift
      next unless conn_line =~ /^CONNECTOR\s+(\d+) NAME #{NAMEPATTERN}/
      number = $1.to_i
      opts = {:name => $2}
      
      # number always in the first line after conn declaration
      # example: FROM LINK 28 LANES 1 2 AT 819.728
      inp.shift =~ /FROM LINK (\d+) LANES (\d )+/
      opts[:from_link] = link($1.to_i)
      opts[:lanes] = $2.split(' ').map{|str| str.to_i}
  
      # next comes the knot definitions
      # and the the to-link
      begin
        line = inp.shift 
      end until line =~ /TO LINK (\d+)/
  
      opts[:to_link] = link($1.to_i)
      
      # look for any closed to declarations (they are not mandatory)
      
      set_closed_to(opts,inp)
      
      # check if this connector is a decision
      conn = if opts[:name] =~ /([NSEW])(\d+)([LTR])(\d+)?/
        Decision.new!(number,
          opts.merge({
              :from_direction => $1,
              :intersection => $2.to_i,
              :turning_motion => $3,
              :weight => $4 ? $4.to_i : nil}))
      else
        Connector.new!(number,opts)
      end
      
      # only links which can be reached are cars and trucks are interesting 
      @connectors << conn unless conn.closed_to_any?(Cars_and_trucks)
    end
  end
  def set_closed_to opts, inp
    begin
      line = inp.shift 
    end until line.nil? or line =~ /(CLOSED|LINK|CONNECTOR)/
      
    opts[:closed_to] = if $1 == 'CLOSED'
      inp.shift =~ /VEHICLE_CLASSES\s+([\d ]+)+/
      $1.split(' ').map{|str| str.to_i}
    else
      inp.insert(0, line)
      []
    end
  end
  def parse_links(inp)

    # we do a lot of lookups on link numbers later on
    # this map will save time.
    @links_map = {}
    
    while line = inp.shift
      next unless line =~ /^LINK\s+(\d+) NAME #{NAMEPATTERN}/
      
      number = $1.to_i
      opts = {:name => $2}
      
      inp.shift =~ /LENGTH\s+(\d+\.\d+)\s+LANES\s+(\d+)/
      opts[:length] = $1.to_f
      opts[:lanes] = $2.to_i
      
      # extract from and to coordinates
      while line2 = inp.shift
        if line2 =~ /(FROM|TO)\s+(\d+.\d+)\s+(\d+.\d+)/
          opts[:"#{$1.downcase}_point"] = Point.new!(:x => $2.to_f, :y => $3.to_f)
          break if $1 == 'TO' # next line will be a new LINK definition
        end
      end
      
      set_closed_to(opts,inp)
  
      @links_map[number] = Link.new!(number, opts)
    end
    
    # enrich the existing link objects with data from the database
    for row in LINKS.filter(:link_type => 'IN')
      link(row[:number].to_i).update(row.retain_keys!(:from, :link_type, :name))
    end
    
    begin # note which links have bus inputs (mandatory)
      BUSES.each do |businputrow|
        link(businputrow[:input_link].to_i).is_bus_input = true
      end
    rescue; end # skip bus input links; table was not defined (see BUSES)    
  end
  def to_s
    str =  "Controllers: #{@controllers.size}\n"
    str << "Links: #{@links_map.size}\n"
    str << "   - inputs: #{input_links.size}\n"
    str << "   - bus inputs: #{links.find_all{|l|l.is_bus_input}.size}\n"
    str << "   - exits: #{exit_links.size}\n"
    str << "Connectors: #{@connectors.size}\n"
    str << "   - decisions: #{decisions.size}\n"
    str << "Total links & connectors: #{@connectors.size + @links_map.size}"
    str
  end
end

if __FILE__ == $0
  vissim = Vissim.new  
  #puts vissim
  #raise "Found dangling connectors" if vissim.connectors.any?{|c| c.from_link.nil? or c.to_link.nil?}
  #  for conn in vissim.connectors
  #    puts conn
  #  end
  
  #  for sc in vissim.controllers.find_all{|x| x.has_plans?}.sort
  #    puts sc
  #  end
end
