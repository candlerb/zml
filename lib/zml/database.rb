module ZML

# This is a virtual base class for connecting to a ZML database

class Database
  def self.connect(dbistring, *args)
    case dbistring
    when /\Adbi:/i
      require 'zml/sql/database'
      return ZML::SQL::Database.new(dbistring, *args)
    else
      raise "Unknown database type: #{dbistring.inspect}"
    end
  end
end # class Database

end # module ZML
