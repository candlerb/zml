# This tests that our workaround for the interlocking issues in Sqlite works

require 'test/unit'
require 'zml/sql/dbiwrapper'

class SqliteLockTest < Test::Unit::TestCase
  FILENAME = "locktest.db"
  DBISTRING = "dbi:sqlite:#{FILENAME}"

  def setup
    File.delete(FILENAME) if FileTest.exists?(FILENAME)
    db = ZML::SQL::DBIwrapper.connect(DBISTRING)
    db.transaction do
      db.do("create table foo(bar varchar(250))")
      db.do("insert into foo(bar) values ('baz')")
    end
    db.disconnect
  end

  def test_autocommit_flag
    db = ZML::SQL::DBIwrapper.connect(DBISTRING)
    acf = db.instance_eval { @db['AutoCommit'] }
    assert(acf, "AutoCommit should be true")
    db.disconnect
  end

  def test_locking
    tstart = Time.now

    childpid = Process.fork do
      # child - grab an exclusive lock on the database for 3 seconds, then release
      db1 = ZML::SQL::DBIwrapper.connect(DBISTRING)
      db1.transaction do
        sleep 3
      end
      sleep 3  # keep the database open
      db1.disconnect
    end

    # parent
    db2 = ZML::SQL::DBIwrapper.connect(DBISTRING)
    # wait for child to get write-exclusive lock
    sleep 1
    # do a select - it should be retried until the child releases the lock
    res = nil
    assert_nothing_raised {
      res = db2.select_one("select * from foo")
    }
    assert(Time.now >= tstart + 3, "Child should hold lock for at least 3 seconds")
    # random retries are at intervals of between 0 and 1 seconds. So it could
    # be up to 4 seconds before we get here, which might be tstart+5 if
    # the start time was near the end of a second:
    #	|	|	|	|	|	|	|
    #          ^                                 ^
    #        start                              end
    assert(Time.now <= tstart + 5, "Child should hold lock for no more than 4 seconds")
    Process.waitpid(childpid)
  end

  def teardown
    File.delete(FILENAME)
  end
end
