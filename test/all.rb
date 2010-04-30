rundir = File.dirname($0)
rundir << '/' if rundir.length > 0
$:.unshift rundir + '../lib'

require 'test/unit/testsuite'
require 'path'
require 'stream'
require 'streamtosql'
require 'sequence'
require 'load'
