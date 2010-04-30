#!/usr/local/bin/ruby -w
$managerdb=['dbi:pg:template1', 'pgsql', '']
$zmldb=['dbi:pg:zmltest', 'zmluser', 'zmlpass']

# Uncomment to see SQL statements being sent
#$managerdb[3] = {'zmlsqltrace'=>$stderr}
#$zmldb[3] = {'zmlsqltrace'=>$stderr}

require 'all'
