#!/usr/local/bin/ruby -w

# This program demonstrates a bug in the Sqlite DBD. It raises exception:
#    database is locked(database is locked) (DBI::DatabaseError)
# when two processes try to open the database at the same time. (However,
# if you use the sqlite command line client, you'll see that this is
# perfectly OK)
#
# What is happening is:
# - the DBI handle is opened with AutoCommit=>false (which is fine)
# - in this mode, the DBD sends 'begin transaction' immediately to the
#   database
# - 'begin transaction' causes sqlite to obtain a write-exclusive lock
#   on the underlying file; no other client can connect!
#
# What I think we really want is:
#   db.transaction do
#     ... block of stuff
#   end
# DBI should send a 'begin transaction' before yielding the block, and
# a 'commit' at the end (or 'rollback' if there was an exception).
# Unfortunately, I think the underlying DBD API only supports 'commit'
# and 'rollback', no 'begin'.
#
# The workaround is annoying: set db['AutoCommit'=>true] when you are
# doing read-only operations, then just before a transaction set
# db['AutoCommit'=>false], yield the transaction, then set it true again.

require 'dbi'

opt1 = {}  # set opt1 = {'AutoCommit'=>true} and the locking problem goes away
opt2 = {}  # (but you lose transaction semantics!)

File.delete('foo') if FileTest.exists?('foo')

pid = Process.fork do
  db1 = DBI.connect('dbi:sqlite:foo',nil,nil,opt1)
  sleep 3
end

sleep 1
db2 = DBI.connect('dbi:sqlite:foo',nil,nil,opt2)

Process.waitpid(pid)
