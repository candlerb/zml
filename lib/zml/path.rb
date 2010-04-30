module ZML

Decode = {
	'0'	=> 0,
	'1'	=> 1,
	'2'	=> 2,
	'3'	=> 3,
	'4'	=> 4,
	'5'	=> 5,
	'6'	=> 6,
	'7'	=> 7,
	'8'	=> 8,
	'9'	=> 9,
	'A'	=> 10,
	'B'	=> 11,
	'C'	=> 12,
	'D'	=> 13,
	'E'	=> 14,
	'F'	=> 15,
	'G'	=> 16,
	'H'	=> 17,
	'I'	=> 18,
	'J'	=> 19,
	'K'	=> 20,
	'L'	=> 21,
	'M'	=> 22,
	'N'	=> 23,
	'O'	=> 24,
	'P'	=> 25,
	'Q'	=> 26,
	'R'	=> 27,
	'S'	=> 28,
	'T'	=> 29,
	'U'	=> 30,
	'V'	=> 31,
}
def self.pathsplit(str)
  return nil if str.nil?
  res = []
  rem = str.gsub(/[0-9A-V]|W[0-9A-V]{2}|X[0-9A-V]{4}|Y[0-9A-V]{6}|Z[0-9A-V]{8}/) do |v|
    d = Decode[v]
    unless d
      d = 0
      v[1..-1].each_byte do |b|
        d <<= 5
        d |= Decode[b.chr]
      end
    end
    res << d
    ""
  end
  raise "Path format error! #{str.inspect} (remainder #{rem.inspect})" unless rem == ""
  res
end

Encode = [
	'0','1','2','3','4','5','6','7',
	'8','9','A','B','C','D','E','F',
	'G','H','I','J','K','L','M','N',
	'O','P','Q','R','S','T','U','V',
]
def self.pathenc(val,n)
  res = ""
  n.times do
    res = Encode[val & 0x1f] + res
    val >>= 5
  end
  raise "Encoding error! #{val.inspect}" unless val == 0
  res
end

def self.pathjoin(arr)
  return nil if arr.nil?
  res = ""
  arr.each do |e|
    if e < 0
      raise "Negative path element not permitted: #{e.inspect}"
    elsif e < 0x20
      res << Encode[e]
    elsif e < 0x400
      res << "W#{pathenc(e,2)}"
    elsif e < 0x100000
      res << "X#{pathenc(e,4)}"
    elsif e < 0x40000000
      res << "Y#{pathenc(e,6)}"
    elsif e < 0x10000000000
      res << "Z#{pathenc(e,8)}"
    else
      raise "Path element too large: #{e.inspect}"
    end
  end
  res
end

end # module ZML
