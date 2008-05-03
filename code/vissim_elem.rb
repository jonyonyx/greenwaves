class VissimElem
  attr_reader :number, :name
  def initialize number; @number = number; end
  def type; self.class.to_s.split('::').last; end
  def to_s; "#{type} #{@number}#{@name and @name != '' ? " '#{@name}'" : ''}"; end
  def hash; @number + type.hash; end
  def eql?(other); other.instance_of?(VissimElem) and @number == other.number; end
  def <=>(other); @number <=> other.number; end
  def update opts; opts.each{|k,v| instance_variable_set("@#{k}",v)}; end
end
