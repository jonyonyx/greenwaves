require 'const'
require 'network'
require 'signal'
require 'vissim_elem'
require 'vissim_distance'

# vissim element names. match anything that isn't the last quotation mark
NAMEPATTERN = '\"([^\"]*)\"'
SECTIONPATTERN = /-- ([^-:]+): --/ # section start
COORDINATEPATTERN = '(\-?\d+.\d+) (\-?\d+.\d+)' # x, y

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
    
    # notify the links of their outgoing connectors
    @connectors.each{|conn| conn.from_link.outgoing_connectors << conn}
    
    if Project == 'dtu'
      # attempt to mark links as arterial
      # and note the direction of the link;
      # this is used by the signal optimization routines
      sc1 = ARTERY[:sc1][:scno]
      sc2 = ARTERY[:sc2][:scno]
      from1 = ARTERY[:sc1][:from_direction]
      from2 = ARTERY[:sc2][:from_direction]
      
      scs_to_pass = (sc1..sc2)
      
      artery_decisions = Hash.new{|h,k| h[k] = []}
      @decisions.each do |d| 
        if scs_to_pass === d.intersection and d.turning_motion == "T" and [from1,from2].include?(d.from_direction)
          artery_decisions[d.from_direction] << d
        end
      end
      
      # look for routes passing the artery decisions
      routes = get_full_routes
      
      for from_direction, decisions in artery_decisions
        artery_routes = routes.find_all{|r| decisions.all?{|d| r.decisions.include?(d)}}
        puts "Warning: no artery routes were found!" if artery_routes.empty?
        puts "Warning: #{artery_routes.size} routes were found from #{from_direction}; expected only one." if artery_routes.size > 1
        if artery_routes.size == 1
          route = artery_routes.first
       
          # mark links and connectors in the artery route so that the signal controllers may see which
          # direction they give green to.
          route.mark_arterial from_direction
        end
      end
    end
  end
  def input_links; links.find_all{|l| l.input?}; end
  def exit_links; links.find_all{|l| l.exit?}; end
  def links; @links_map.values; end
  def link(number); @links_map[number]; end
  def controllers_with_plans; @controllers.find_all{|sc| sc.has_plans?}; end
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
        [Green End] As green_end
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
        if line =~ /^SIGNAL_GROUP\s+(\d+)\s+NAME\s+#{NAMEPATTERN}\s+SCJ\s+#{sc.number}.+TRED_AMBER\s+([\d\.]+)\s+TAMBER\s+([\d\.]+)/
          
          sc.add_group($1.to_i,
            :name => $2,
            :tred_amber => $3.to_i,
            :tamber => $4.to_i)
          
        elsif line =~ /SIGNAL_HEAD\s+(\d+)\s+NAME\s+#{NAMEPATTERN}\s+LABEL\s+0.00\s+0.00\s+SCJ\s+#{sc.number}\s+GROUP\s+(\d+)/
          num = $1.to_i
          opts = {:name => $2}
          grpnum = $3.to_i
          grp = sc.group(grpnum)
          
          raise "Signal head '#{opts[:name]}' is missing its group #{grpnum} at controller '#{sc}'" if grp.nil?
          
          # optionally match against the TYPE flag (eg. left arrow)
          line =~ /POSITION LINK\s+(\d+)\s+LANE\s+(\d)\s+AT\s+(\d+\.\d+)/
          
          pos_link_num = $1.to_i # heads can be placed on both links and connectors (RoadSegment)
          opts[:position_link] = link(pos_link_num) || @connectors.find{|c|c.number == pos_link_num}
          raise "Position link #{pos_link_num} for head #{opts[:name]} at #{sc} could not be found!" if opts[:position_link].nil?
          
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
        grp.update(row.retain_keys!(:red_end, :green_end, :priority))
      end
      
      @controllers << sc
    end
    @controllers.sort!
  end
  def parse_connectors(inp)
    @connectors = []
    
    while conn_line = inp.shift
      next unless conn_line =~ /^CONNECTOR\s+(\d+) NAME #{NAMEPATTERN}/
      number = $1.to_i
      opts = {:name => $2}
      
      inp.shift =~ /FROM LINK (\d+) LANES (\d )+AT (\d+\.\d+)/
      opts[:from_link] = link($1.to_i)
      opts[:from_lanes] = $2.split(' ').map{|str| str.to_i}
      opts[:at_from_link] = $3.to_f
  
      set_over_points(opts, inp)
  
      inp.shift =~ /TO LINK (\d+) LANES (\d )+AT (\d+\.\d+)/
      opts[:to_link] = link($1.to_i)
      opts[:to_lanes] = $2.split(' ').map{|str| str.to_i}      
      opts[:at_to_link] = $3.to_f
      
      # look for any closed to declarations (they are not mandatory)
      
      set_closed_to(opts,inp)
      
      # check if this connector is a decision
      conn = if opts[:name] =~ /([NSEW])(\d+)([LTR])(\d+)?/   
        decid = "#{$1}#{$2}#{$3}" # decision identifier
        
        opts[:from_direction] = $1
        opts[:intersection] = $2.to_i
        opts[:turning_motion] = $3
        opts[:weight] = $4 ? $4.to_i : nil
                
        # Extract information on an optional, alternative
        # decision point which this decision should origin from
        opts[:name] =~ /decide-at ([NSEW])(\d+)/
        opts[:decide_from_direction] = $1 || opts[:from_direction]
        opts[:decide_at_intersection] = $2 ? $2.to_i : opts[:intersection]
        
        # The link at which this decision should end, ie. drop
        # the affected vehicles so they may obtain a new route
        opts[:drop_link] = links.find{|l| l.drop_for.include?(decid)} || opts[:to_link]      
        
        Decision.new!(number,opts)
      else
        Connector.new!(number,opts)
      end
      
      # only links which can be reached are cars and trucks are interesting 
      @connectors << conn if conn.allows_private_vehicles?
    end
  end
  # Extract knot definitions for links and connectors
  def set_over_points opts, inp    
    opts[:over_points] = []
    while line = inp.shift
      if not line =~ /^OVER/
        inp.insert(0, line)
        break
      end
      for over_part in line.split('OVER')
        over_part.strip!
        next if over_part.empty?
        opts[:over_points] << Point.new(*over_part.split(' ').map{|s|s.to_f})
      end
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
      inp.shift =~ /FROM\s+#{COORDINATEPATTERN}/
      opts[:from_point] = Point.new($1.to_f, $2.to_f)
      set_over_points(opts,inp)
      
      inp.shift =~ /TO\s+#{COORDINATEPATTERN}/
      opts[:to_point] = Point.new($1.to_f, $2.to_f)      
      
      set_closed_to(opts,inp)
  
      @links_map[number] = Link.new!(number, opts)
    end
    
    #     
    link_is_sql = "SELECT LINKS.number, from_direction, link_type, INSECTS.Number AS intersection_number
                   FROM [links$] AS LINKS
                   INNER JOIN [intersections$] AS INSECTS ON LINKS.Intersection_Name = INSECTS.Name"
    
    # enrich the existing link objects with data from the database
    for row in DB[link_is_sql].all
      link_num = row[:number].to_i
      row[:intersection_number] = row[:intersection_number].to_i
      link = link(link_num)
      raise "Link number #{link_num} was marked as an input link, but could not be found!" if link.nil?
      link.update(row.retain_keys!(:from_direction, :intersection_number, :link_type))
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
    str << "Total links & connectors: #{@connectors.size + @links_map.size}\n"    
    str << "Total knots (over-points): #{(@connectors+links).map{|rs|rs.over_points.size}.sum}"
    str
  end
end

if __FILE__ == $0
  vissim = Vissim.new 
  
#  for link in vissim.links
#    puts "#{link} at #{link.intersection_number}"
#  end
#  vissim.decisions.each do |dec|
#    puts "#{dec}: #{dec.drop_link}"
#  end
  scs = vissim.controllers_with_plans
  (0...scs.size-1).to_a[-2..-2].each do |i|
    sc1, sc2 = *scs[i..i+1]
    puts "Distance from #{sc1.name} to #{sc2.name}: #{vissim.distance(sc1, sc2)}"
    #puts "Distance from #{sc2.name} to #{sc1.name}: #{vissim.distance(sc2, sc1)}"
    puts
  end
  #  for sc in vissim.controllers.find_all{|x| x.has_plans?}.sort
  #    #rows << [sc.number, sc.name, sc.arterial_groups.map{|grp|grp.name}.join(', ')]
  #    puts sc
  #  end
  #
  #  puts rows.inspect  
  #  puts to_tex(rows,:caption => 'Groups for main traffic direction as perceived by traffic signal designer', :label => 'lab:arterial_groups')
end
