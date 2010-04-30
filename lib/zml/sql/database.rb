require 'rexml/document'
require 'rexml/streamlistener'
require 'zml/database'
require 'zml/path'
require 'zml/stream'
require 'zml/sql/dbiwrapper'
require 'zml/sql/idlookup'
require 'zml/sql/streamtosql'
require 'zml/sql/sqltostream'
require 'zml/sql/sequence'

module ZML
module SQL
class Database < ::ZML::Database
  def initialize(dbistring, *args)
    @db = DBIwrapper.connect(dbistring, *args)
    # Normally we have a second DB connection for IdLookup, which allows
    # it to commit information to the auxilliary tables while a main
    # transaction is in progress. The exception is SQLite, which does not
    # allow two concurrent accesses to the same database :-(
    if dbistring =~ /\Adbi:sqlite:/i
      @id = IdLookup.new(@db)
    else
      db2 = DBIwrapper.connect(dbistring, *args)
      db2.instance_eval { @db['AutoCommit'] = true rescue nil }
      @id = IdLookup.new(db2)
    end
  end

  def disconnect
    @db.disconnect
    @id = nil
    @db = nil
  end

  # Generate an XML stream from database contents

  def fetch_xml(out, pathstr=nil)
    streamgen = SQLtoStream.new(@db, @id)
    streamgen.run(StreamToXML.new(out), ZML.pathsplit(pathstr) || [])
  end

  # Reload an entire subtree from an XML stream, ignoring any schema
  # constraints. If replace=false, then the stream will be added as a child
  # of the given path. Otherwise, it will completely replace this path.

  def store_xml(inp, pathstr=nil, replace=false)
    pathstr ||= ''
    path = ZML.pathsplit(pathstr)

    # Allocate a new child path
    unless replace
      child = @db.seq_get('elements','path', pathstr, 'nextchild')
      path.push child
      pathstr = ZML.pathjoin(path)
    end

    @db.transaction do
      if replace
        @db.do("delete from attributes where path like ?", pathstr+"%")
        @db.do("delete from elements where path like ?", pathstr+"%")
      end
      l = StreamToSQL.new(@db, @id, path)
      REXML::Document.parse_stream(inp, l)
    end
    pathstr   # result is the path of the node we created or replaced
  end

  # For test harness only
  def dbi_database_handle
    @db
  end

end # class DBIdatabase

end # module SQL
end # module ZML
