require 'zml/sql/dbiwrapper'

module ZML
module SQL
class DBIwrapper

  # Databases tend to handle sequences in different ways. Also, we need
  # lots of sequences - one in every element node - to give the index of the
  # next child to be added. So we handle sequences using SQL commands:
  # in principle,
  #   select value from table where id = X for update;
  #   update sequence set value = (n+1) where id = X and value = (n);
  # If the latter returns a row processed count of 1 then we know we were
  # successful and the value belongs to us.
  #
  # However major care is needed for when two transactions occur
  # concurrently (and there is a separate test/sequence.rb specifically
  # for this case), and so we get into the area of row locking.
  #
  # We use 'select .. for update' to get the current value of a sequence
  # and acquire a row lock; that prevents any other reader from accessing
  # the row until the first transaction has committed.
  #
  # SQLite does not support 'select .. for update' at all, but it doesn't
  # matter because 'BEGIN TRANSACTION' completely serialises access to
  # the database anyway.

  def seq_get(table, keycol, keyid, col, nextproc = nil)
    nextproc ||= proc { |x| x.to_i.succ }
    v = nil
    10.times do
      transaction do
        v = select_one("select #{col} from #{table} where #{keycol}=? #{for_update}", keyid)
        if v.nil? or v.size != 1
          raise "Error in seq_get (#{table}/#{keycol}/#{keyid}); v=#{v.inspect}), no such element or sequence?"
        end
        v = v[0]
        v2 = nextproc.call(v)
        # STDERR.puts "v=#{v}, v2=#{v2}"
        if v == v2
          raise "Internal error in seq_get (v = v2 = #{v.inspect})"
        end
        c = self.do("update #{table} set #{col}=? where #{keycol}=? and #{col}=?",
		v2, keyid, v)
        if c == 1
          yield v if block_given?   # this is intended for unit testing only
        elsif c == 0
          # Hmm, someone else updated it before us; row locking doesn't work
          STDERR.puts "WARNING: Row locking does not work in seq_get"
          v = nil
        else
          raise "Internal error in seq_get (c=#{c.inspect})"
        end
      end
      return v if v
      sleep rand
    end
    raise "Unable to grab a sequence value (#{table}/#{keycol}/#{keyid})"
  end

  def for_update
    " for update"
  end
end # class DBIwrapper

class DBIsqlite < DBIwrapper
  # SQLite does not support "select ... for update"
  def for_update
    ""
  end
end

end # module SQL
end # module ZML
