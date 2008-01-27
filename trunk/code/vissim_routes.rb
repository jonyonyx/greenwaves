##
# This file can enumerate the possible routes between
# a list of links and generate Vissim output. Useful for 
# generating relative flows.


require 'const'

puts "BEGIN"

Links = VissimFun.get_links('herlev')

inp = IO.readlines("#{Vissim_dir}tilpasset_model.inp")

class Connector  
  def initialize number
    @number = number
    @incoming = []
    @outgoing = []
  end
  def add_incoming link
    @incoming << link    
  end
  def add_outgoing link
    @outgoing << link  
  end
  def hash; number; end
  def to_s
    "CONNECTOR #{@number}
       Incoming links: #{@incoming.join(',')}
       Outgoing links: #{@outgoing.join(',')}\n"
  end
end

Connectors = {}

i = 0
while i < inp.length
  line = inp[i]
  match = /^CONNECTOR\s+(\d+)/.match(line)
  unless match
    i = i + 1
    next
  end
  
  #puts "#{i}: #{inp[i]}"
  conn_num = match[1].to_i
  
  conn = Connectors[conn_num]
  conn = Connector.new(conn_num) unless conn
  
  i = i + 1
  # always in the first line after conn declaration
  from_link_num = inp[i].split[2].to_i
  
  # next comes the knot definitions
  # and the the to-link
  i = i + 1 until /TO LINK/.match(inp[i])
  
  to_link_num = inp[i].split[2].to_i
  
  from_link = Links.find { |link| link.number == from_link_num }
  
  if from_link # this is a known input link for the area
  #  puts "Found connector FROM #{from_link} TO #{to_link_num}"
    conn.add_incoming from_link
    conn.add_outgoing to_link_num
    
    Connectors[conn_num] = conn
  end
end

puts Connectors.values

puts "END"