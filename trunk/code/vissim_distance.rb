class Vissim
  # Finds the distance from the arterial signal head(s) in this controller
  # to the downstream stop-line of othersc
  def distance fromsc,tosc
    return 0.0 if fromsc == tosc
    
    # determine which sc is in the downstream
    from_direction = (fromsc.number < tosc.number) ? 
      ARTERY[:sc1][:from_direction] : ARTERY[:sc2][:from_direction]
    
    from_links = fromsc.served_arterial_links(from_direction)
    to_links = tosc.served_arterial_links(from_direction)
    
    routes = from_links.map{|from_link|find_routes(from_link, to_links)}.flatten
    raise "Found no routes from #{from_links} to #{to_links}!" if routes.empty?
    raise "Found multiple routes (#{routes.size}) from #{from_links} to #{to_links}:\n#{routes.map{|r|r.to_vissim}.join("\n")}" if routes.size > 1
    routes.first.length
  end
end
