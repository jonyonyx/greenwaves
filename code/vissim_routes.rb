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
  
  i = i + 1
  # number always in the first line after conn declaration
  from_link_num = inp[i].split[2].to_i
  
  # next comes the knot definitions
  # and the the to-link
  i = i + 1 until /TO LINK/.match(inp[i])
  
  to_link_num = inp[i].split[2].to_i
    
  # found a connection
  Links[from_link_num].add(Links[to_link_num])
     
end

# now have both the connectors and links

def discover link, route=Route.new, &callback
  route << link
  for adj_link in link.adjacent
    next if route.include?(adj_link) # avoid loops
    if adj_link.exit?
      route << adj_link
      yield route # found an exit link for this route
    else
      discover(adj_link,route,&callback) # look further
    end
  end
end

Input_links = VissimFun.get_links('herlev','input').find_all{|l| l.input? }
Exit_links = VissimFun.get_links('herlev','exit').find_all{|l| l.exit? }

Exit_numbers = Exit_links.map{|l| l.number}

routes = []
for link in Input_links.map{|l| Links[l.number]}#[1..1]
  discover(link) do |route|
    #puts route.map{|l|l.number}.join(' > ')
    routes << route if Exit_numbers.include?(route.exit.number)
  end
end

puts "found #{routes.length} routes"

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

for route in routes[0..0]
  puts route.to_s
end

puts "END"