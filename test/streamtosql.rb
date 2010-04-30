# Test the database writing; given a tag stream, what rows get written

require 'test/unit'
require 'zml/sql/streamtosql'

class DummyDB
  attr_reader :data
  def initialize(*tabs)
    @data = {}   # tablename => rows
    tabs.each { |t| @data[t] = [] }
  end
  def insert(table, colnames, data)
    @data[table] += data
    return data.size    
  end
  def do(*args)
    case args[0]
    when "update elements set nextchild=? where path=? and nextchild=?"
      elements = @data['elements']
      newval, path, oldval = *args[1..-1]
      e = elements.find { |row| row[0] == path }
      raise "Couldn't find path #{path}" unless e
      raise "Old value wrong" if oldval != e[3]
      e[3] = newval
    else
      raise "Unknown SQL: #{args[0]}"
    end
  end
end

class DummyID
  def find_element(fulltag, namespaces=[])
    fulltag
  end
  def find_attr(fulltag, namespaces=[])
    fulltag
  end
end

class SqlToStreamTest < Test::Unit::TestCase

  # simple tag stream
  SEQ1 = [
    [:tag_start, "foo", []],
    [:text, "abc"],
    [:text, "def"],  # should be coalesced with previous
    [:text, nil],    # should be ignored
    [:cdata, "ghi"], # should be coalesced with previous
    [:text, "jkl"],  # ditto
    [:tag_end, "foo"],
  ]

  # expected results
  RES1 = {
    'elements' => [
      ['137', '13', 'foo', 0, 'abcdefghijkl'],
    ],
    'attributes' => [
    ],
  }

  def test1
    check(SEQ1, RES1, [1,3,7])
  end

  # check white space handling
  SEQ2 = [
    [:text, "      "],          # ignored always (outside root element)
    [:tag_start, "foo", []],
    [:text, "\n    "],
    [:tag_start, "bar", []],
    [:text, "   text1   "],
    [:tag_end, "bar"],
    [:text, "\n      "],
    [:tag_start, "baz", []],
    [:text, "   text2   "],
    [:tag_end, "baz"],
    [:text, "\n   "],
    [:tag_end, "foo"],
    [:text, "      "],          # ignored always
  ]
  # With space stripping
  RES2 = {
    'elements' => [
	['137', '13', 'foo', 2, nil],
        ['1370', '137', 'bar', 0, 'text1'],
	['1371', '137', 'baz', 0, 'text2'],
    ],
    'attributes' => [
    ],
  }
  # With space preservation
  RES2P = {
    'elements' => [
	['137', '13', 'foo', 4, "\n    "],
        ['1370', '137', 'bar', 0, '   text1   '],
	['1371', '137', -1, nil, "\n      "],
	['1372', '137', 'baz', 0, '   text2   '],
	['1373', '137', -1, nil, "\n   "],
    ],
    'attributes' => [
    ],
  }

  def test2
    check(SEQ2, RES2, [1,3,7])
  end

  def test2a
    check(SEQ2, RES2P, [1,3,7], {}, true)
  end

  # Now try using xml:space attributes, which should override it
  def test2b
    seq2b = deepcopy(SEQ2)
    res2b = deepcopy(RES2)
    seq2b[1][2] << ['xml:space','default']
    res2b['attributes'] << ['137','xml:space','default']
    check(seq2b, res2b, [1,3,7], {}, false)
    check(seq2b, res2b, [1,3,7], {}, true)
  end

  def test2c
    seq2c = deepcopy(SEQ2)
    res2c = deepcopy(RES2P)
    seq2c[1][2] << ['xml:space','preserve']
    res2c['attributes'] << ['137','xml:space','preserve']
    check(seq2c, res2c, [1,3,7], {}, false)
    check(seq2c, res2c, [1,3,7], {}, true)
  end

  # Mixed content and attributes
  SEQ3 = [
    [:tag_start, "book", [['xml:space','preserve'],['foo','bar']]],
    [:text, "This is a piece of "],
    [:tag_start, "b", []],
    [:text, "mixed content"],
    [:tag_end, "b"],
    [:text, " with "],
    [:tag_start, "i", []],
    [:text, "two "],
    [:tag_start, "u", []],
    [:text, "levels"],
    [:tag_end, "u"],
    [:text, " of nesting"],
    [:tag_end, "b"],
    [:text, " as a demonstration of mixed content\n"],
    [:tag_end, "book"],
  ]
  RES3 = {
    'elements' => [
	['137', '13', 'book', 4, "This is a piece of "],
        ['1370', '137', 'b', 0, "mixed content"],
	['1371', '137', -1, nil, " with "],
        ['1372', '137', 'i', 2, "two "],
        ['13720', '1372', 'u', 0, "levels"],
        ['13721', '1372', -1, nil, " of nesting"],
	['1373', '137', -1, nil, " as a demonstration of mixed content\n"],
    ],
    'attributes' => [
	['137', 'xml:space', 'preserve'],
	['137', 'foo', 'bar'],
    ],
  }
    
  def test3
    check(SEQ3, RES3, [1,3,7])
  end

  def check(tagstream, expected, *params)
    dummydb = DummyDB.new('elements','attributes')
    dummydb.instance_eval { @minbuffer = 2 }
    dummyid = DummyID.new
    x = ZML::SQL::StreamToSQL.new(dummydb, dummyid, *params)
    tagstream.each do |ts|
      x.send(*ts)
    end
    assert_equal(expected, dummydb.data)
  end

  def deepcopy(x)
    Marshal.load(Marshal.dump(x))
  end
end
