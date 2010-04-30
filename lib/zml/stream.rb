require 'rexml/document'
require 'rexml/streamlistener'


module ZML

# This is the inverse of an REXML StreamParser. You call methods tag_start,
# tag_end, comment etc, and it writes the corresponding XML to the given
# stream. In other words, it converts a method-call stream into an XML
# text stream.
#
# Perhaps REXML should have had this already :-)
#
# FIXME: add prettyprint (which respects xml:space in stream)

class StreamToXML
  include REXML::StreamListener  # in case we forgot any methods

  # 'out' is the stream to which the result is to be written. It can
  # be any object which supports the '<<' method to write a string.

  def initialize(out)
    @out = out
    # We buffer one element tag. This allows us to coalesce
    # tag_start, tag_end into <tag/>. However, because a document ends with
    # tag_end and optional whitespace and comments, we do not need to
    # provide a method to explicity flush what's in the buffer.
    @elem = nil
  end

  def tag_start(name, attrs)
    flushbuffer
    @elem = REXML::Element.new(name)
    @elem.add_attributes(attrs) if attrs
  end

  def tag_end(name)
    if @elem.instance_of? REXML::Element
      @elem.write(@out)   # writes <tag attr='val'/>
      @elem = nil
    else
      flushbuffer
      @out << "</#{name}>"
    end
  end

  def text(text)
    flushbuffer
    REXML::Text.new(text,true).write(@out)
  end

  def instruction(target, content=nil)
    flushbuffer
    REXML::Instruction.new(target, content).write(@out)
  end

  def comment(text)
    flushbuffer
    REXML::Comment.new(text).write(@out)
  end

  def xmldecl(version, encoding, standalone)
    flushbuffer
    REXML::XMLDecl.new(version, encoding, standalone).write(@out)
  end

  # The rest is legacy XML stuff which ZML doesn't use or need, but it's
  # here for completeness

  def cdata(content)
    flushbuffer 
    REXML::CData.new(content).write(@out)
  end

  # This is currently broken in REXML. StreamListener does have a 'doctype'
  # method, but it is never called anyway.

  def start_doctype(*args)
    flushbuffer
    @elem = REXML::DocType.new(args)  # yes, param _is_ an array
  end

  def end_doctype
    if @elem.instance_of? REXML::DocType
      @elem.write(@out)   # writes <!DOCTYPE foo>, no nested internal subset
      @elem = nil
    else
      flushbuffer
      @out << ']>'
    end
  end

  def attlistdecl(element_name, attributes, raw_content)
    flushbuffer
    @out << raw_content
  end

  def elementdecl(raw_content)
    flushbuffer
    @out << raw_content+">"
  end

  def entitydecl(*args)
    flushbuffer
    # We need to pass in a dummy first argument otherwise this doesn't work.
    # Ugh!
    REXML::Entity.new([:entitydecl]+args).write(@out)
  end

  def notationdecl(*content)
    flushbuffer
    @out << "<!NOTATION #{content.join(' ')}>"
  end

  # REXML::Parsers::StreamParser never calls this anyway

  def entity(content)
    flushbuffer
    @out << "%#{content};"
  end

private
  def flushbuffer
    if @elem.nil?
      return
    elsif @elem.instance_of? REXML::Element
      # write just the start tag
      t = ""
      @elem.write(t)
      t.sub!(/\/>\z/, '>')     # convert <.../> to <...>
      @out << t
    elsif @elem.instance_of? REXML::DocType
      t = ""
      @elem.write(t)
      t.sub!(/>\z/, ' [')     # <!DOCTYPE foo> becomes <!DOCTYPE foo [
      @out << t
    else
      @elem.write(@out)
    end
    @elem = nil
  end
end # class XMLwriter

# This class takes a stream of method calls (tag_start, tag_end etc) and
# builds an REXML::Document or REXML::Element tree from them, which you
# can get by calling 'result' when the stream has ended. Unfortunately
# I could not conveniently re-use REXML::Document#build, otherwise I might
# have decided just to use the PullParser API rather than the StreamListener
# API. In any case, the StreamListener API seems more "public".
#
# Perhaps REXML should have had this already :-)

class StreamToREXML
  include REXML::StreamListener  # in case we forgot any methods
  attr_reader :result

  # Create a new object for parsing a method stream. If 'is_document' is true
  # then you will get an REXML::Document containing the root element and
  # any surrounding comments, processing instructions etc; if it is false
  # will get a REXML::Element and any surrounding stuff will be silently
  # ignored. The default is to auto-detect, based on the presence or
  # absence of an <?xml ... ?> declaration at the start of the method stream.

  def initialize(is_document=nil, parent=nil)
    @result = nil
    @stack = [parent]
    @is_document = is_document
    if is_document
      @result = REXML::Document.new
      @stack.last.add(@result) if @stack.last
      @stack.push @result
    end
  end

  # In response to these method calls, the tree is built

  def tag_start(name, attrs)
    if name == 'zml:document'  # FIXME: pass in a namespace stack
      elem = REXML::Document.new
    else
      elem = REXML::Element.new(name)
    end
    elem.add_attributes(attrs) if attrs
    @result = elem unless @result
    @stack.last.add(elem) if @stack.last
    @stack.push elem
  end

  def tag_end(name)
    @stack.pop
  end

  def text(text)
    @stack.last.add(REXML::Text.new(text,true)) if @stack.last
  end

  def instruction(target, content=nil)
    @stack.last.add(REXML::Instruction.new(target, content)) if @stack.last
  end

  def comment(text)
    @stack.last.add(REXML::Comment.new(text)) if @stack.last
  end

  def xmldecl(*args)
    if @result.nil? and @is_document.nil?
      @result = REXML::Document.new
      @stack.last.add(@result) if @stack.last
      @stack.push @result
      @is_document = true
    end
    @stack.last.add(REXML::XMLDecl.new(*args)) if @stack.last
  end

  # The rest is legacy XML stuff which ZML doesn't use or need, but it's
  # here for completeness

  def cdata(content)
    @stack.last.add(REXML::CData.new(content)) if @stack.last
  end

  # Broken in REXML; StreamListener has a 'doctype' method but it is
  # never called. Besides, we need start/end_doctype to be able to
  # attach the internal subset to the correct place.

  def start_doctype(*args)
    # Note: first argument to DocType.new is an array
    elem = REXML::DocType.new(args)
    @stack.last.add(elem) if @stack.last
    @stack.push elem
  end

  def end_doctype
    @stack.pop
  end

  def attlistdecl(*args)
    # Note: first argument to AttlistDecl.new is an array
    @stack.last.add(REXML::AttlistDecl.new(args)) if @stack.last
  end

  def elementdecl(content)
    @stack.last.add(REXML::ElementDecl.new(content)) if @stack.last
  end

  def entitydecl(*args)
    @stack.last.add(REXML::Entity.new([:entitydecl]+args)) if @stack.last
  end

  def notationdecl(*content)
    @stack.last.add(REXML::NotationDecl.new(*content)) if @stack.last
  end

  # REXML::Parsers::StreamParser never calls this anyway

  def entity(content)
    # ??
    stack.last.add(REXML::Entity.new(content)) if @stack.last
  end
end # class REXMLbuilder

end # module ZML

# Now we have to work out whether we're running an old version of REXML
# whose stream parser doesn't support start_doctype/end_doctype

unless REXML::StreamListener.instance_methods.include?('start_doctype')

# We apply some minor fixes to REXML so that DOCTYPE declarations
# are passed through

module REXML # :nodoc:
	module Parsers # :nodoc:
		class StreamParser # :nodoc:
			def parse
				# entity string
				while true
					event = @parser.pull
					case event[0]
					when :end_document
						return
					when :start_element
						@listener.tag_start( event[1], event[2] )
					when :end_element
						@listener.tag_end( event[1] )
					when :text
						normalized = @parser.unnormalize( event[1] )
						@listener.text( normalized )
					when :processing_instruction
						@listener.instruction( *event[1,2] )
					when :comment, :start_doctype, :end_doctype, :attlistdecl, 
						:elementdecl, :entitydecl, :cdata, :notationdecl, :xmldecl
						@listener.send( event[0], *event[1..-1] )
					end
				end
			end
		end
	end
	module StreamListener # :nodoc:

		# These methods are called instead of the original 'doctype'
		# method in REXML::StreamListener
		def start_doctype name, pub_sys, long_name, uri
		end
		def end_doctype
		end

	end	
end

end # unless working version of REXML::StreamListener
