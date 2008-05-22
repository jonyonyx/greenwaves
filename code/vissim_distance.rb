class Vissim
  def velocity(fromsc, tosc)
    80 / 3.6 # 80km/t
  end
  # Finds the distance from the arterial signal head(s) in this controller
  # to the downstream stop-line of othersc
  def distance fromsc,tosc
    return 0.0 if fromsc == tosc
    
    # determine which sc is in the downstream
    from_direction = get_from_direction(fromsc,tosc)
    
    from_links = fromsc.served_arterial_links(from_direction)
    to_links = tosc.served_arterial_links(from_direction)
    
    routes = from_links.map{|from_link|find_routes(from_link, to_links)}.flatten
    raise "Found no routes from #{from_links} to #{to_links}!" if routes.empty?
    raise "Found multiple routes (#{routes.size}) from #{from_links} to #{to_links}:\n#{routes.map{|r|r.to_vissim}.join("\n")}" if routes.size > 1
    route = routes.first
#    puts "Measuring length of route #{route}"
#    for rs in route.road_segments
#      puts "#{rs}: #{rs.length}"
#    end
    # Find the signal heads we measure distance between so
    # that the at-position can be subtracted from the position link lengths
    
    from_link, to_link = route.start, route.exit
    heads = {from_link => [], to_link => []}
    
    ObjectSpace.each_object(SignalController::SignalGroup::SignalHead) do |head|
#      puts "Examining #{head}.."
      heads[head.position_link] << head if heads.keys.include?(head.position_link)
    end
    
#    puts "Found heads:"
#    for link,head_list in heads
#      puts link
#      puts head_list
#    end
#    
    # Now have all the heads at the start and end of the route.
    # They should be pretty close to each other, but we take the mean to
    # be fair.
    avg_at_from = heads[from_link].map{|h|h.at}.mean
    avg_at_to = heads[to_link].map{|h|h.at}.mean
    
#    puts "Avg from #{avg_at_from}"
#    puts "Avg to #{avg_at_to}"
#    puts "Route length #{route.length}"
    
    # Routes length includes from and to links length.
    # Correct this now.
    (route.length - avg_at_from - to_link.length + avg_at_to).round
  end
end
