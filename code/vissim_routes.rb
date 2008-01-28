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
Herlev_links = VissimFun.get_links('herlev')

def discover link, route, &block_expr
  route << link
  for adj_link in link.adjacent
    next if route.include?(adj_link)
    if adj_link.exit?
      #puts "found an exit at #{adj_link}"
      yield route + [adj_link] # found an exit link down this route
    else
      #puts "Following #{link} -> #{adj_link}"
      discover(adj_link,route,&block_expr) # look further
    end
  end
end

for link in Herlev_links.map{|l| Links[l.number]}[0..0]
  discover(link,[]) do |route|
    puts route.join(' -> ')
  end
end

puts "END"