

Dir['*.rb'].sort.each do |rbfile|
  print "\\lstinputlisting[caption=#{rbfile.gsub('_','\\_')}]{../code/#{rbfile}}\r"
end