require 'rexml/streamlistener'
require 'rexml/namespace'
require 'zml/path'

module ZML
module SQL

# This is the stream listener used to insert elements into the database.
# Input is a DBI handle, the path for the top element, and a hash of any
# namespaces currently in context ( prefix => uri )
#
# It assumes:
# - any required db.transaction has taken place outside
# - the assigned path for the top element is actually available
#   (i.e. has been allocated using the parent's "nextchild" field, or
#    any existing subtree with this path has been removed)
#
# After inserting an element and all its children, it's necessary to update
# the 'nextchild' field with the correct value. To make life more efficient
# we flush inserts in blocks of N, and keep the last M rows in memory.
#
# This also enables us to coalesce the sequence
#   tag_start text tag_end
# into a single insert, because an element and its (first) text child
# are stored in the same row.
#
# Here's an example operation, parsing the following document for
# insertion at path [1,3,7]
# ==============================================================
#   <foo><bar>text</bar>mixedtext<baz>moretext</baz></foo>
# ==============================================================
#
#    path = [1,3,7]
#  <foo>
#    create element 'foo' at 1,3,7
#    path = [1,3,7,0]
#  <bar>
#    create element 'bar' at 1,3,7,0
#    path = [1,3,7,0,0]
#  text
#    update element at 1,3,7,0
#  </bar>
#    path = [1,3,7,1]
#  mixedtext
#    create text element at 1,3,7,1
#    path = [1,3,7,2]
#  <baz>
#    create element 'baz' at 1,3,7,2
#    path = [1,3,7,2,0]
#  moretext
#    update element at 1,3,7,2
#  </baz>
#    path = [1,3,7,3]
#  </foo>
#    path = [1,3,7]
#    set nextchild = 3 at [1,3,7]
#
# Final result:
# path  elemid   text         nextchild
# ---------------------------------------
# 137   foo      nil              3
# 1370  bar      text             0
# 1371  -1       mixedtext        nil
# 1372  baz      moretext         0

class StreamToSQL
  include REXML::StreamListener

  def initialize(db, id, path, namespaces = {}, preserve_space = false)
    # The DBIwrapper handle to the database
    @db = db
    # The object which handles ancilliary lookups (namespace id, elem id etc)
    @id = id

    # where we are inserting into the database, as child indexes [a, b, c]
    @path = path

    # tag nesting depth
    @depth = 0

    # buffered SQL inserts
    @buffer = []        # [[pathstr, parent, elemid, nextchild, content], ...]
    @index = {}         # pathstr => buffer entry

    # namespace context; an array of hashes. Search these in order
    # when trying to map prefix to uri
    @namespaces = [namespaces.dup]

    # The xml: prefix is used for xml:space and xml:lang, and must be
    # available for use without any explicit declaration.
    @namespaces[0]['xml'] ||= 'http://www.w3.org/XML/1998/namespace'

    # flush parameters
    @minbuffer = 25   # have between this and twice this elements buffered

    # default for xml:space (perhaps inherited from an ancestor)
    @preserve_space = [preserve_space]

    # generate only a single warning about comments/text outside the
    # root element
    @warned = false
  end

  def flush(n = @buffer.size-@minbuffer)
    n = @buffer.size if n > @buffer.size

    # Write the elements, note the attributes
    args = []
    av = []
    n.times do |i|
      b = @buffer.shift
      args << b[0..4]
      if b[5]
        av += b[5].collect { |attrid,val| [b[0], attrid, val] }
      end
    end
    count = @db.insert('elements',
	['path','parent','elemid','nextchild','content'],args)
    raise "Internal error in flush (count=#{count.inspect}, expected #{n})" if count != n

    # Write the attributes (must be done after the corresponding elements
    # because of RI constraints)
    @db.insert('attributes',['path','attrid','value'],av)

    # rebuild index
    @index = {}
    @buffer.each do |b|
      @index[b[0]] = b
    end
  end

  def tag_start(tag, attrs)
    # Process any namespace declarations
    h = {}
    attrs.delete_if do |label, value|
      if label == "xmlns"
        h[""] = value   # default namespace
        true
      elsif label =~ /\Axmlns:(.+)\z/
        h[$1] = value
      else
        false
      end
    end
    @namespaces.unshift h

    # Process xml:space (push the new value onto our stack)
    ps = @preserve_space[0]   # default to retaining the status quo
    attrs.each do |label, value|
      next unless label == 'xml:space'
      case value
      when 'preserve'
        ps = true
      when 'default'
        ps = false
      else
        STDERR.puts "Unknown value for xml:space ignored #{attrs['xml:space'].inspect}"
      end
      break
    end
    @preserve_space.unshift ps

    # Parse remaining attributes
    # NOTE: Referential Integrity means we can't insert attributes until
    # the corresponding element has been inserted. So we stick them in
    # a field in the buffer
    av = attrs.collect do |label, value|
      [@id.find_attr(label, @namespaces), value]
    end

    elemid = @id.find_element(tag, @namespaces)
    generate(ZML::pathjoin(@path), ZML::pathjoin(@path[0..-2]), elemid, 0, nil, av)

    flush if @buffer.size >= @minbuffer*2
    @path.push 0   # path of next child
    @depth += 1
  end

  def text(t)
    t = t.to_s

    # ZML's default white-space handling is to strip leading and trailing
    # white space from character data
    unless @preserve_space[0]
      t = t.sub(/\A\s+/,'').sub(/\s+\z/,'')  # NOTE: \A...\z, not ^...$
    end
    return if t.size == 0

    if @depth > 0 and @path[-1] == 0
      # This text has come immediately after an opening tag, so we can
      # just stick it in with the element itself. Because of the highwater/
      # lowwater stuff, we know that there must be at least one row in the
      # buffer, so it's just the last one we need to modify.
      @buffer[-1][4] ||= ""
      @buffer[-1][4] << t

    elsif @depth > 0 and @buffer[-1][2] == -1 and @buffer[-1][0] == ZML::pathjoin(@path)
      # Text immediately after another text item; coalesce them
      @buffer[-1][4] << t

    else
      # Create a new row to hold the text (which is a no-op if it is
      # only whitespace and we have xml:space='default')
      insert_textitem(-1, t)
    end
  end

  def tag_end(tag)
    @namespaces.shift
    @preserve_space.shift
    nextchild = @path.pop
    if nextchild > 0 and @path
      # Update the nextchild value in the parent
      p = ZML::pathjoin(@path)
      if @index[p]
        @index[p][3] = nextchild
      else
        count = @db.do("update elements set nextchild=? where path=? and nextchild=0", nextchild, p)
        raise "Internal error updating nextchild" unless count == 1
      end
    end
    @depth -= 1
    if @depth == 0
      # finished!
      flush(@buffer.size)
    else
      @path[-1] += 1
    end
  end

  def cdata(t)
    text(t)
  end

  def comment(t)
    insert_textitem(-2, t)
  end

  def instruction(name, t)
    insert_textitem(-3, "#{name}#{t}")
  end

  # For now we ignore start_doctype, end_doctype, entitydecl etc.
  # Workaround bug in REXML::StreamListener
  def entitydecl(*args)
  end

private
  def insert_textitem(elemid, text)
    if @depth == 0
      if !@warned and text =~ /[^\s]/
        STDERR.puts "Warning: comment or text outside root element ignored"
        @warned = true
      end
      return
    end
    generate(ZML::pathjoin(@path), ZML::pathjoin(@path[0..-2]), elemid, nil, text, nil)
    @path[-1] += 1
    flush if @buffer.size >= @minbuffer*2
  end

  def generate(*row)
    @buffer.push row
    @index[row[0]] = row
  end
end # class Loader


if __FILE__ == $0

require 'stringio'
require 'rexml/document'
class DummySQL # :nodoc:
  def method_missing(*args)
    STDERR.puts args.inspect
    return args[3].size if args[0] == :insert
  end
end

class DummyID # :nodoc:
  def find_element(tag, namespaces=[])
    case tag
    when 'foo'
      return 1
    when 'bar'
      return 2
    when 'baz'
      return 3
    end
    nil
  end
end

src = "<foo><bar>text</bar>mixedtext<baz>moretext</baz></foo>"

REXML::Document.parse_stream(
	StringIO.new(src),
	StreamToSQL.new(DummySQL.new, DummyID.new, [1,3,7])
)
 
end #if

end # module SQL
end # module ZML
