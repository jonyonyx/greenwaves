class VissimElem
  attr_reader :number,:name  
  def initialize number,attributes
    @number = number
    update attributes
  end
  def update attributes
    @name = attributes['NAME']
  end
  def type; self.class.to_s; end
  def to_s
    "#{type} #{@number}#{@name and @name != '' ? " '#{@name}'" : ''}"
  end
  def hash; @number + type.hash; end
  def eql?(other); self.class == other.class and @number == other.number; end
  def <=>(other)
    @number <=> other.number
  end
end