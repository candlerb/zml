require 'test/unit'
require 'zml/path'

class PathTest < Test::Unit::TestCase

  # the 'nil' case is here because if you have the root node, path = [],
  # and try to find its parent using path[0..-2], then you get nil, and
  # that's what we put into the database.

  Cases = [
	[nil,		nil],
	["",		[]],
	["12",		[1,2]],
	["W134",	[0x23,4]],
	["W134X6789A",	[0x23,4,0x31d09,10]],
	["VU",		[0x1f, 0x1e]],
	["ZVVVVVVVV0",	[0x10000000000-1, 0]],
  ]

  # Check correct decoding and encoding of path strings
  def test1
    Cases.each do |c|
      a = ZML::pathsplit(c[0])
      assert_equal(c[1], a)
      b = ZML::pathjoin(a)
      assert_equal(c[0], b)
    end
  end

  Bad_cases = [
	"/",
	"W1",
	"W4W44",
	"0-1",
  ]

  # Check bad cases
  def test2
    Bad_cases.each do |c|
      assert_raises(RuntimeError) { ZML::pathsplit(c) }
    end    
    assert_raises(RuntimeError) { ZML::pathjoin([-1]) }
    assert_raises(RuntimeError) { ZML::pathjoin([0x10000000000]) }
  end
end
