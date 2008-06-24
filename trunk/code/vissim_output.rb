# module included by classes that need to write
# their output to a vissim network files
# they must define to_vissim and section_header
module VissimOutput 
  def write inpfile = Default_network
    section_contents = to_vissim # make sure this can be successfully generated before opening the network file!
    inp = IO.readlines(inpfile)
    section_start = (0...inp.length).to_a.find{|i| inp[i] =~ section_header} + 1
    section_end = (section_start...inp.length).to_a.find{|i| inp[i] =~ /-- .+ --/ } - 1 
    File.open(inpfile, "w") do |file| 
      file << inp[0..section_start]
      file << "\n#{section_contents}\n"
      file << inp[section_end..-1]
    end
    puts "Wrote#{respond_to?(:length) ? " #{length}" : ''} #{self.class} to '#{inpfile}'"
  end
end
