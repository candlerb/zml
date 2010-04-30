require 'dbi'

module ZML
module SQL

# This class is a wrapper around a DBI::DatabaseHandle to try and hide
# the differences between the various SQL implementations

class DBIwrapper
attr_reader :fix_trailing_space

  def self.connect(*args)
    args[3] = args[3] ? args[3].dup : {}
    trace = args[3].delete('zmlsqltrace')

    case args[0]
    when /\Adbi:sqlite:/i
      db = DBIsqlite.new(*args)
    when /\Adbi:mysql:/i
      db = DBImysql.new(*args)
    when /\Adbi:pg:/i
      db = DBIpg.new(*args)
      db.instance_eval { @db['AutoCommit'] = false }
    else
      db = DBIwrapper.new(*args)
      db.instance_eval { @db['AutoCommit'] = false rescue nil }
    end
    db.zmlsqltrace(trace)
    db
  end

  # Make a connection. The arguments are the same as you pass to DBI::connect

  def initialize(*args)
    @trace = nil
    @db = ::DBI.connect(*args)

    # Some databases support a multiple insert syntax:
    #    INSERT INTO foo (bar,baz) values (1,2),(3,4),(5,6)
    # If so, set max_insert to a value greater than 1 and that number
    # of rows will be inserted in a single statement
    @max_insert = 1

    # Mysql is broken by stripping trailing spaces from columns when you
    # insert data. So as a workaround, for any column which ends with
    # space or '|', we add a trailing '|'.
    @fix_trailing_space = false
  end

  # Enable or disable tracing of SQL commands. Pass in a stream, like $stderr,
  # or nil to disable tracing (the default)

  def zmlsqltrace(io = nil)
    if io == true
      @trace = $stderr
    elsif io == false
      @trace = nil
    else
      @trace = io
    end
  end

  # Pass through the commands we need, with optional tracing

  def do(*args)
    @trace.puts "SQL do: #{args.inspect}" if @trace
    @db.do(*args)
  end

  def execute(*args,&blk)
    @trace.puts "SQL execute: #{args.inspect}" if @trace
    @db.execute(*args,&blk)
  end

  def select_one(*args)
    @trace.puts "SQL select_one: #{args.inspect}" if @trace
    res = @db.select_one(*args)
    @trace.puts "Result: #{res.inspect}" if @trace
    res
  end

  def transaction(*args,&blk)
    @trace.puts "<--- SQL transaction begin --->" if @trace
    res = @db.transaction(*args,&blk)
    @trace.puts "<--- SQL transaction commit --->" if @trace
    res
  end

  def disconnect
    @db.disconnect
  end

  # This command implements 'insert' in a more usable way. For those
  # databases which allow multiple rows to be inserted at once, we can take
  # advantage of it. Usage:
  #   insert("tablename",["col1","col2"],[["v1","v2"],["v3","v4"],...])

  def insert(table, col, rows)
    index = 0
    count = 0
    lastn = nil
    placeholder = "(?" + ",?"*(col.size-1) + ")"
    placeholder2 = "," + placeholder
    while index < rows.size
      n = rows.size - index
      n = @max_insert if n > @max_insert
      if n != lastn
        sql = "insert into #{table} (#{col.join(",")}) values #{placeholder}#{placeholder2*(n-1)}"
      end
      args = rows[index,n].flatten
      if @fix_trailing_space
        args.size.times do |i|
          if args[i].is_a? String and args[i] =~ /[|\s]\z/
            args[i] += "|"    # note, this creates a *new* string object
          end
        end
      end
      count += self.do(sql, *args)
      index += n
      lastn = n
    end
    count
  end

end # class DBIwrapper

# The Sqlite DBD is badly broken, so we have to patch around it here.
#
# The main problem is that if you open a connection with 'AutoCommit'=>false
# (which is the default, and what we want), then the DBD issues a
# 'begin transaction' command the instant that you open the connection. This
# is a really stupid thing to do, because it causes sqlite to get a
# *write exclusive* lock on the underlying file. No other client can open
# the file at all!
#
# If we set 'AutoCommit'=>true then this doesn't happen, but we lose
# transaction semantics, even if we call db.transaction { ... }, because
# commit/rollback become no-ops.
#
# Our workaround for now is:
# - when we connect, we set 'AutoCommit'=>true
# - inside 'transaction', we temporarily set AutoCommit=>false, perform
#   the transaction, then set it back to true
#
# However, in any case, it's a restriction of sqlite that if any client is
# in the middle of a transaction, then any other client (even one who
# already has the database open) will get a 'database is locked' error if
# they attempt to do a read from it. So we include a retry mechanism.
#
# Other problems with Sqlite DBD:
# - db.do "insert ...." should return the row count, but in fact it returns
#   nil. So we fix that here.
#
# Other problems with Sqlite itself:
# - the 'like' operator is always case-insensitive (which means we probably
#   shouldn't use it, but should use 'glob' or 'between' instead)

class DBIsqlite < DBIwrapper

  def initialize(*args)
    args[3]['AutoCommit'] = true
    retry_if_locked { super }
  end

  def transaction(*args,&blk)
    res = nil
    begin
      retry_if_locked { @db['AutoCommit'] = false }
      res = super
    ensure
      @db['AutoCommit'] = true
    end
    res
  end

  # Execute the statement and return the Row Processed Count correctly
  # (workaround bug in ruby-dbi <= 0.0.23)

  def do(*args)
    @trace.puts "SQL do: #{args.inspect}" if @trace
    count = nil
    retry_if_locked do
      @db.execute(*args) do |sth|
        count = sth.rows
      end
    end
    count
  end

  def execute(*args,&blk)
    retry_if_locked { super }
  end

  def select_one(*args)
    retry_if_locked { super }
  end

  # Retry a block a number of times if there is a 'locked' error

  def retry_if_locked(timeout = 10)
    deadline = Time.now + timeout
    begin
      yield
    rescue DBI::DatabaseError => e
      raise unless Time.now < deadline and e.message =~ /lock/i
      sleep rand
      retry
    end
  end
end # class DBIsqlite

class DBImysql < DBIwrapper
  def initialize(*args)
    super
    @db['AutoCommit'] = false   # DBI won't let us set this until after we've connected
    @max_insert = 10		# nice feature of mysql
    @fix_trailing_space = true	# bad feature of mysql
    @db
  end
end

# Fixes for the DBD:Pg interface. It is broken in 'execute', here:
#
#         if not SQL.query?(boundsql) and not @db['AutoCommit'] then
#           @db.start_transaction unless @db.in_transaction?
#         end
#
# The problem is that the DBD does not issue a "BEGIN" command until the
# first *non-query* statement. This means that "select .. for update"
# occurs outside of a transaction.

class DBIpg < DBIwrapper
  def transaction
    super do
      @db.instance_eval { @handle.instance_eval { start_transaction unless in_transaction? } }
      yield
    end
  end
end

end # module SQL
end # module ZML
