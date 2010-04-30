require 'getoptlong'

module ZML

# Common code for the command-line utility programs

module Command

  DEFAULT_DATABASE='dbi:sqlite:temp.db'

  def self.parse_options(*opts)
    result = {}
    opts += [
	[ "--help", "-h", GetoptLong::NO_ARGUMENT ],
	[ "--quiet", "-q", GetoptLong::NO_ARGUMENT ],
	[ "--filename", "-f", GetoptLong::REQUIRED_ARGUMENT ],
	[ "--path", "-p", GetoptLong::REQUIRED_ARGUMENT ],
	[ "--trace", "-t", GetoptLong::NO_ARGUMENT ],
	[ "--yes", "-y", GetoptLong::NO_ARGUMENT ],
    ]
    getopt = GetoptLong.new(*opts.collect {|i| i[0..2]} )
    getopt.each do |opt,arg|
      res = opts.find { |r| r[0] == opt }
      next unless res
      index = opt[2..-1].intern
      if res[2] == GetoptLong::NO_ARGUMENT
        result[index] = true
      else
        result[index] = arg
      end
      return if index == :help
    end

    # left-over arguments are the zml database
    $zmldb = ARGV[0..2] if ARGV.size > 0
    $zmldb ||= []

    unless $zmldb[0]
      print "Database [#{DEFAULT_DATABASE}]: "
      $zmldb[0] = STDIN.gets.chomp
      $zmldb[0] = DEFAULT_DATABASE if $zmldb[0] == ''
    end

    unless $zmldb[0] =~ /\Adbi:sqlite:/i
      unless $zmldb[1]
        print "Username: "
        $zmldb[1] = STDIN.gets.chomp
      end
      unless $zmldb[2]
        print "Password: "
        $zmldb[2] = STDIN.gets.chomp
      end
    end
    if result[:trace]
      $zmldb[3] ||= {}
      $zmldb[3]['zmlsqltrace'] = true
    end

    result
  end

  def self.final_confirmation(opt)
    unless opt[:yes]
      print <<EOS
**********************************************************
* THIS WILL ERASE ANY EXISTING ZML DATA IN THIS DATABASE *
**********************************************************
EOS
      print "Last chance - are you sure you wish to continue? (y/n) "
      ans = STDIN.gets.chomp
      unless ans =~ /\Ay/i
        puts "Aborted, phew"
        exit
      end
    end
  end

end # module Command
end # module ZML

