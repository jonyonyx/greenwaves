
module VissimOutput 
  def write
    section_contents = to_vissim # make sure this can be successfully generated before opening the network file!
    network = Default_network
    inp = IO.readlines(network)
    section_start = (0...inp.length).to_a.find{|i| inp[i] =~ section_header} + 1
    section_end = (section_start...inp.length).to_a.find{|i| inp[i] =~ /-- .+ --/ } - 1 
    File.open(network, "w") do |file| 
      file << inp[0..section_start]
      file << "\n#{section_contents}\n"
      file << inp[section_end..-1]
    end
    puts "Wrote#{respond_to?(:length) ? " #{length}" : ''} #{self.class} to '#{network}'"
  end
end