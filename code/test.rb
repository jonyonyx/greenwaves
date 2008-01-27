# 
# To change this template, choose Tools | Templates
# and open the template in the editor.
 

require 'csv'
require 'const'

puts "BEGIN"

puts CSV.readlines("#{Vissim_dir}compositions.csv",';').inspect

puts "END"