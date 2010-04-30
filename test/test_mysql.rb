#!/usr/local/bin/ruby -w
$managerdb=['dbi:mysql:mysql', 'root', '']
$zmldb=['dbi:mysql:zmltest', 'zmluser', 'zmlpass']

# Uncomment to see SQL statements being sent
#$managerdb[3] = {'zmlsqltrace'=>$stderr}
#$zmldb[3] = {'zmlsqltrace'=>$stderr}

require 'all'
