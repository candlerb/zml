require 'test/unit'
require 'zml/sql/initdb'
require 'zml/database'
require 'stringio'
require 'rexml/document'

# Test the initialisation of a new database, the import and export of
# various test XML documents

class MyException < StandardError
end

class InitTest < Test::Unit::TestCase

DOC1 = <<DOC1
<zml:root xmlns:zml='http://www.linnet.org/xmlns/zml' xml:space='preserve'>
  <test>   This is a test of <b>&lt;mixed content&gt;</b> in XML
   and any &entityreference; should just be stored as-is
   |<!-- Vertical bar is to test mysql space padding
         Now check processing instructions -->
    <?php flurble
      boing?>
    <!-- Done now -->
  </test>
</zml:root>
DOC1

DOC2 = DOC1.sub(/<\/zml:root>\n/,'') + <<DOC2
<foo>child1</foo><bar><baz>child2</baz></bar></zml:root>
DOC2

  def test_load
    # Drop the database if it already exists, create a new one, and
    # create all the tables
    assert_nothing_raised {
      ZML::SQL::initdb($zmldb, $managerdb)
      @zml = ZML::Database.connect(*$zmldb)
    }

    check_transactions(@zml.dbi_database_handle)

    # Load an XML document
    assert_nothing_raised {
      @zml.store_xml(StringIO.new(DOC1), nil, true)
    }

    # Dump it back out
    result = ""
    assert_nothing_raised {
      @zml.fetch_xml(StringIO.new(result))
    }

    # In this case, the two documents should be exactly identical,
    # including all whitespace. (Actually there could be minor differences -
    # attr='foo' versus attr="foo", or attributes returned in a different
    # order - but we choose our test case carefully!)
    assert_equal(DOC1, result)

    # Check the number of rows in the 'elements' and 'attributes' tables.
    # Of course, this needs to be changed if the test XML is changed.
    # It's to confirm that we've not added any spurious rows etc.
    # Beware: sqlite returns ["11"], pgsql returns [11]
    c = @zml.dbi_database_handle.select_one('select count(*) from elements')[0].to_i
    assert_equal(11, c, "rows in elements table")
    c = @zml.dbi_database_handle.select_one('select count(*) from attributes')[0].to_i
    assert_equal(1, c, "rows in attributes table")

    # Now load DOC1 again, this time with a spurious comments/text outside
    # the root element, which should just generate a warning

    result = ""
    assert_nothing_raised {
      ZML::SQL::initdb($zmldb)
      @zml = ZML::Database.connect(*$zmldb)  # because id table changed
      @zml.store_xml(StringIO.new("<!--ignore this-->" + DOC1 + "message"), nil, true)
      @zml.fetch_xml(StringIO.new(result))
    }
    assert_equal(DOC1, result)

    # Append two children
    result = ""
    np1 = np2 = nil
    assert_nothing_raised {
      np1 = @zml.store_xml(StringIO.new("<foo>child1</foo>\nIGNORED"))
      np2 = @zml.store_xml(StringIO.new("<bar><baz>child2</baz></bar>\nIGNORED"))
      @zml.fetch_xml(StringIO.new(result))
    }
    assert_equal("2", np1, "Allocated path")
    assert_equal("3", np2, "Allocated path")
    assert_equal(DOC2, result)
  end

  def check_transactions(db)
    c1 = db.select_one("select count(*) from namespaces")
    begin
      db.transaction do
        db.insert('namespaces',['nsid','uri'],[[-1,'http://example.com/']])
        raise MyException.new
      end
    rescue MyException
    end
    c2 = db.select_one("select count(*) from namespaces")
    assert_equal(c1, c2, "Transaction rollback is not working!")
  end
end
