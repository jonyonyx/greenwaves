##
# This file can enumerate the possible routes between
# a list of links and generate Vissim output. Useful for 
# generating relative flows.

# facts:
# - connectors always connect two links denoted the from- and to link
# - in a non-trivial network links are always connected to at least 1 connector
# - there exist a route from A to C if there exist a connector from A to B and 
#   from B to C. This can be determined by following the outgoing connectors
#   from A and then B until a connector, which ends in C, is found

require 'const'

puts "BEGIN"

inp = IO.readlines("#{Vissim_dir}tilpasset_model.inp")

Links = {} # map from link numbers for link objects

# first parse all LINKS

for line in inp
  m =  /^LINK\s+(\d+) NAME \"([\w\s\d]*)\"/.match(line)
  next unless m
  number = m[1].to_i
  name = m[2]
  
  #puts "#{number} '#{name}'"
  
  Links[number] = Link.new(number,name,nil)
end

#now get the connectors and join them up using the links

i = 0
while i < inp.length
  line = inp[i]
  m =  /^CONNECTOR\s+(\d+) NAME \"([\w\s\d]*)\"/.match(line)
  unless m
    i = i + 1
    next
  end
  
  conn_number = m[1].to_i
  
  i = i + 1
  
  # number always in the first line after conn declaration
  # example: FROM LINK 28 LANES 1 2 AT 819.728
  m = /FROM LINK (\d+) LANES (\d )+/.match(inp[i])
  from_link_num = m[1].to_i
  lanes = m[2].split(' ').length
  
  # next comes the knot definitions
  # and the the to-link
  i = i + 1 until /TO LINK/.match(inp[i])
  
  to_link_num = inp[i].split[2].to_i
    
  from_link = Links[from_link_num]
  to_link = Links[to_link_num]
  
  conn = Connector.new(conn_number,from_link,to_link,lanes)
  
  # found a connection
  from_link.add to_link, conn     
end

#puts Links[25060312].exit?
#puts Links[25060312].adjacent
#exit(0)

# now have both the connectors and links

def discover link, path=[[link,nil]], &callback
  for adj_link,conn in link.adjacent
    # avoid loops by checking if the path contain this link
    next if path.map{|l,c|l}.include?(adj_link) 
    
    # assume there exist a valid route using this connector to reach adj_link;
    # if this is not true, nothing is returned anyhow.
    if adj_link.exit?
      # found an exit link for this path
      yield Route.new(path + [[adj_link,conn]]) 
    else
      # copy the path to avoid backreferences among routes
      discover(adj_link,path + [[adj_link,conn]],&callback) # look further
    end
  end
end

Herlev_links = VissimFun.get_links('herlev')

Input_links = Herlev_links.find_all{|l| l.input? }
Exit_links = Herlev_links.find_all{|l| l.exit? }

Exit_numbers = Exit_links.map{|l| l.number}

routes = []
for link in Input_links.map{|l| Links[l.number]}.compact#[8..8]
  puts "discovering from #{link}"
  discover(link) do |route|
    #puts route.to_s
    routes << route if Exit_numbers.include?(route.exit.number)
  end
end

# arterial optimization: prune "identical" routes ie same start and end

identical_routes = [] # the identical routes with fewer lanes to remove
for i in (0...routes.length)
  for j in (0...routes.length)
    next if i == j
    r1 = routes[i]
    r2 = routes[j]
    
    if r1.start == r2.start and r1.exit == r2.exit
      # found identical route
      # the shortest one is always the best, since the other includes 
      # a rest stop
      identical_routes << [r1,r2].min
    end
    
  end
end
routes = routes - identical_routes
puts "Pruned #{identical_routes.length} of #{identical_routes.length + routes.length} routes because they had the same start and exit"
#exit(0)

# Example of routing decision

#ROUTING_DECISION 3 NAME "" LABEL  0.00 0.00
#     LINK 47131394  AT 50.246
#     TIME  FROM 0.0 UNTIL 99999.0
#     NODE 0
#      VEHICLE_CLASSES ALL
#     ROUTE     2  DESTINATION LINK 48131218  AT  142.668
#       FRACTION     1
#       OVER 10267 48130431 10927 20094 10930 48130432 10274
#     ROUTE     1  DESTINATION LINK 25060312  AT   57.012
#       FRACTION     1
#       OVER 10266 48130429 49131059 48130424 10139

# generate a routing decision for each link
output_string = ''
i = 1
for link in Input_links#.find_all{|l| l.number == 48130426} # herlev sydgående
  output_string += "ROUTING_DECISION #{i} NAME \"\" LABEL  0.00 0.00\n"
  # AT must be AFTER the input point
  # link inputs are always defined in the end of the link
  output_string += "     LINK #{link.number} AT 50.000\n"
  output_string += "     TIME FROM 0.0 UNTIL 99999.0\n"
  output_string += "     NODE 0\n"
  output_string += "      VEHICLE_CLASSES ALL\n"
  
  # routing decisions have one or more routes to choose from
  j = 1
  for route in routes.find_all{|r| r.start.number == link.number}.sort
    output_string += "     ROUTE     #{j}  DESTINATION LINK #{route.exit.number}  AT   5.000\n"
    output_string += "     FRACTION 1\n"
    output_string += "     OVER #{route.to_vissim}\n"
    j += 1
  end  

  puts "Generated #{j-1} routes starting from #{link}"
  i += 1
end

Clipboard.set_data output_string
puts "Please find the Routing Decisions on your clipboard."

puts "END"