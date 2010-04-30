require 'test/unit'
require 'zml/stream'

# Note: REXML has some issues parsing items outside the document
# root element, where it's not consistent about handling whitespace
# (typically discarding it when parsing, rather than passing it to the
# application), and when converting <!ATTLIST>/<!ELEMENT> etc declarations
# to strings, where it sometimes sticks on newlines of its own accord.
# Admittedly, this internal DTD subset stuff is just SGML legacy crap, and
# the world would be a happier place if the writers of XML had had the
# courage to rip it all out.
#
# As a result, some of these tests are very sensitive to where you put
# whitespace.

class TestXMLwriter < Test::Unit::TestCase
  DOC1 = <<XML
<?xml version='1.0' encoding='UTF-8'?><!DOCTYPE hello [<!ELEMENT greeting (#PCDATA)><!ATTLIST tag1
    zml:foo CDATA #REQUIRED
    zml:bar CDATA #IMPLIED><!NOTATION foo SYSTEM 'bar'><!ENTITY % schemaAttrs "xmlns:hfp CDATA #IMPLIED">]><!-- a comment --><greeting xmlns:ex='http://example.com/'>
  <?php wibble?>
  Here is some <b>mixed</b> text, and an &entityref;
  <tag1 zml:foo='bar' zml:bar='baz'>
    <ex:tag2>foo</ex:tag2>
    <ex:tag2>bar</ex:tag2>
    <![CDATA[a>b<c]]><emptytag attr='foo'/>
  </tag1>
</greeting>
XML

  # parse the document into a method call stream, and use XMLwriter
  # to generate back the original XML
  def test1
    rtext = ""
    parser = ZML::StreamToXML.new(rtext)
    REXML::Document.parse_stream(DOC1, parser)

    # The results should be byte-by-byte equal. (Actually, there might
    # be differences like attr='val' versus attr="val", or ordering of
    # the attributes, but we choose our test case carefully!)
    assert_equal(DOC1, rtext)
  end

  # parse the document into a method call stream, and construct
  # an REXML::Document from the stream

  def test2
    parser = ZML::StreamToREXML.new
    REXML::Document.parse_stream(DOC1, parser)
    res = parser.result
    assert(res.instance_of?(REXML::Document), "Result should be REXML::Document")

    # Now we have to check it's the same. We don't have a convenient method
    # to walk down two trees checking they are equal. Unfortunately, just
    # getting REXML to write it back out and comparing with the source
    # doesn't work properly; it inserts newlines at places of its own
    # chosing, e.g. after <!ELEMENT ...> and after <!DOCTYPE ... [
    # So, we reparse the source XML and get REXML to write that out too!

    rtext = ""
    res.write(rtext)
    should = ""
    REXML::Document.new(DOC1).write(should)
    assert_equal(should, rtext)
  end

  # same, but make an REXML::Element. Everything outside the root
  # element will be ignored.

  def test3
    parser = ZML::StreamToREXML.new(false)
    REXML::Document.parse_stream(DOC1, parser)
    res = parser.result
    assert(res.instance_of?(REXML::Element), "Result should be REXML::Element")

    rtext = ""
    res.write(rtext)

    # Restrict to the root element only
    # (REXML handles whitespace correctly within this, so we don't need
    # to mess around too much here)
    md = /\A.*?(<([a-zA-Z0-9:_]+)[^>]*>.*<\/\2>).*\z/m.match(DOC1)
    assert(md)
    assert_equal(md[1], rtext)
  end
end
