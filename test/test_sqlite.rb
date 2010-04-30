#!/usr/local/bin/ruby -w
$managerdb=nil
$zmldb=['dbi:sqlite:zmltest.db']
# Uncomment to see SQL statements being sent
#$zmldb[3] = {'zmlsqltrace'=>$stderr}

require 'all'
require 'locking'
