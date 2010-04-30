#!/usr/local/bin/ruby -w

# This program demonstrates a bug in the Sqlite DBD: DBH#do should
# return the row processed count, but it returns nil

# When run with dbi-0.0.23 this program gives:
# Oops! count1=nil

require 'dbi'

File.delete('foo') if FileTest.exists?('foo')
db = DBI.connect('dbi:sqlite:foo')
db['AutoCommit'] = true

db.do('create table foo(bar varchar(200))')

count1 = db.do('insert into foo (bar) values (?)','abc')
STDERR.puts "Oops! count1=#{count1.inspect}" if count1 != 1

# workaround
count2 = nil
db.execute('insert into foo (bar) values (?)','def') do |sth|
  count2 = sth.rows
end
STDERR.puts "Oops! count2=#{count2.inspect}" if count2 != 1

