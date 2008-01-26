# 
# To change this template, choose Tools | Templates
# and open the template in the editor.
 

require 'win32ole'

puts "BEGIN"

vissim = WIN32OLE.new('VISSIM.Vissim')
sim = vissim.Simulation

vissim.exit

puts "END"
