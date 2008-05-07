module VissimOutput 
  def write
    section_contents = to_vissim # make sure this can be successfully generated
    FileUtils.cp Default_network, "#{ENV['TEMP']}\\#{Network_name}#{rand}" # backup
    inp = IO.readlines(Default_network)
    section_start = (0...inp.length).to_a.find{|i| inp[i] =~ section_header} + 1
    section_end = (section_start...inp.length).to_a.find{|i| inp[i] =~ /-- .+ --/ } - 1 
    File.open(Default_network, "w") do |file| 
      file << inp[0..section_start]
      file << "\n#{section_contents}\n"
      file << inp[section_end..-1]
    end
    puts "Wrote #{self.class} to '#{Default_network}'"
  end
end
