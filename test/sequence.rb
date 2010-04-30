require 'test/unit'
require 'zml/sql/initdb'
require 'zml/sql/sequence'

# We need to check that sequences work even if two concurrent transactions
# try to use them

class SeqTest < Test::Unit::TestCase
  def test_sequence

    ZML::SQL::initdb($zmldb, $managerdb)
    db = ZML::SQL::DBIwrapper.connect(*$zmldb)

    db.transaction do
      db.do("delete from sequences where name='test'") rescue nil
      c = db.insert('sequences',['name','nextval'],[['test',0]])
      assert_equal(1, c, "insert into sequences failed")
    end
    db.disconnect

    inc = proc { |x| sleep 2; x.to_i.succ }

    childpid = Process.fork do
      db2 = ZML::SQL::DBIwrapper.connect(*$zmldb)
      v1 = db2.seq_get('sequences', 'name', 'test', 'nextval', inc) { sleep 2 }
      STDERR.puts "AAAAAARRRGGGGHHHHH!" if v1.to_i != 0   # FIXME: use a pipe
      sleep 2
      db2.disconnect
      exit
    end
    sleep 1
    db = ZML::SQL::DBIwrapper.connect(*$zmldb)
    v2 = db.seq_get('sequences', 'name', 'test', 'nextval', inc)
    assert_equal(1, v2.to_i, "Bad sequence value retrieved")
    Process.wait(childpid)
  end
end
