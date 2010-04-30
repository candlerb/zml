#!/usr/local/bin/ruby -w

# Create a new database for ZML to keep its tables in

require 'dbi'
require 'zml/sql/dbiwrapper'

module ZML
module SQL

  # Create or reinitialise a ZML database. If manager_args is nil, then only
  # drop table/create table will be done. If manager_args is non-nil,
  # then this supplies an administrative account which is used to create
  # the database and username referred to in the dbi_args

  def self.initdb(dbi_args, manager_args = nil)
    case dbi_args[0]
    when /\Adbi:sqlite:([^:]+)/i
      if manager_args
        File.unlink($1) rescue nil
      end
      createtables(dbi_args)

    when /\Adbi:mysql:([^:]+)/i
      if manager_args
        dbh = DBIwrapper.connect(*manager_args)
        database, username, password = $1, dbi_args[1], dbi_args[2]
        begin
          dbh.do("create database #{database}")
        rescue DBI::DatabaseError => e
          raise e unless e.message =~ /exist/i
          STDERR.puts "#{e}"
          STDERR.puts "but continuing anyway (assuming it already exists)"
        end
        dbh.do("grant all on #{database}.* to #{username}@localhost")
        dbh.do("set password for #{username}@localhost = PASSWORD('#{password}')")
        dbh.disconnect
        dbh = nil
      end
      createtables(dbi_args, {
	'tableopt'=>'TYPE=InnoDB', # needed for foreign key and transactions
	'fk_needs_index'=>true,
	'content'=>'MEDIUMTEXT',   # 'MEDIUMTEXT CHARACTER SET UTF8',
      })

    when /\Adbi:pg:([^:]+)/i
      if manager_args
        dbh = DBIwrapper.connect(*manager_args)
        # More DBI stupidity here. If 'AutoCommit'=>false then any
        # command sent to the backend is prefixed by 'BEGIN;' - and
        # that makes the ALTER USER command fail with
        #   ERROR:  current transaction is aborted, queries ignored until
        #   end of transaction block
        # So we have to turn AutoCommit back on here.
        dbh.instance_eval { @db['AutoCommit'] = true }

        database, username, password = $1, dbi_args[1], dbi_args[2]
        begin
          dbh.do("CREATE USER #{username}")
        rescue DBI::DatabaseError => e
          raise e unless e.message =~ /exist/i
          STDERR.puts "#{e}"
          STDERR.puts "but continuing anyway (assuming it already exists)"
        end
        dbh.do("ALTER USER #{username} WITH PASSWORD ?", password)
        begin
          dbh.do("CREATE DATABASE #{database} OWNER=#{username}")
        rescue DBI::DatabaseError => e
          raise e unless e.message =~ /exist/i
          STDERR.puts "#{e}"
          STDERR.puts "but continuing anyway (assuming it already exists)"
        end
        dbh.disconnect
        dbh = nil
      end
      createtables(dbi_args, {
	'content' => 'TEXT',
      })

    else
      raise "Unknown DBI type '#{dbi_args[0]}'"
      # 'CREATE DATABASE' is not a SQL92 standard command.
      # However you can still create the database manually, and then call
      # ZML::SQL.createtables, passing in the appropriate options for
      # your database
    end
  end

  # Create all the tables, given a set of dbi parameters. This is
  # effectively a private method, because it's initdb which knows which
  # options to pass in for each database type. However you can call it
  # directly if you want to experiment with a database backend which
  # initdb doesn't know about.
  #
  # NOTE: this first drops any existing tables, and therefore
  # will destroy data!

  def self.createtables(dbi_args, opt={})

    varchar = opt['varchar'] || 'VARCHAR(250)'  # paths, elem names, attr names
    intkey = opt['intkey'] || 'INTEGER'
    content = opt['content'] || 'LONG VARCHAR'  # text, comment, attr values
    tableopt = opt['tableopt']
    fk_needs_index = opt['fk_needs_index']

    db = DBIwrapper.connect(*dbi_args)

    ['sequences','attributes','elements','attr_tags','element_tags','namespaces'].each do |t|
      begin
        db.transaction do
          db.do "DROP TABLE #{t}"
        end
      rescue DBI::DatabaseError => e
        #STDERR.puts "#{e} (ignoring)"
      end
    end

    # We have to wrap all this in db.transaction because we are now running
    # with AutoCommit off. Both mysql and pgsql will timeout waiting for
    # this transaction to complete otherwise.

    db.transaction do

      db.do <<SQL
CREATE TABLE namespaces (
  nsid #{intkey} NOT NULL PRIMARY KEY,
  uri #{varchar} NOT NULL,
  prefix #{varchar},

  CONSTRAINT ns_uri UNIQUE(uri),
  CONSTRAINT ns_prefix UNIQUE(prefix)
)#{tableopt}
SQL

      db.do <<SQL
CREATE TABLE element_tags (
  elemid #{intkey} NOT NULL PRIMARY KEY,
  nsid #{intkey},
  tag #{varchar} NOT NULL,

  CONSTRAINT et_nsid FOREIGN KEY(nsid) REFERENCES namespaces(nsid),
  CONSTRAINT et_tag UNIQUE(nsid,tag)
)#{tableopt}
SQL

      db.do <<SQL
CREATE TABLE attr_tags (
  attrid #{intkey} NOT NULL PRIMARY KEY,
  nsid #{intkey},   -- may be null, most attributes not associated with ns
  tag #{varchar} NOT NULL,

  CONSTRAINT at_nsid FOREIGN KEY(nsid) REFERENCES namespaces(nsid),
  CONSTRAINT at_tag UNIQUE(nsid,tag)
)#{tableopt}
SQL

      db.do <<SQL
CREATE TABLE elements (
  path #{varchar} NOT NULL PRIMARY KEY,
  parent #{varchar},
  elemid #{intkey} NOT NULL,
  nextchild #{intkey},  -- can be null for text or comment elements
  content #{content},

  #{fk_needs_index && "INDEX(elemid),"}
  CONSTRAINT el_id FOREIGN KEY(elemid) REFERENCES element_tags(elemid),
  #{fk_needs_index && "INDEX(parent),"}
  CONSTRAINT el_parent FOREIGN KEY(parent) REFERENCES elements(path)
)#{tableopt}
SQL

      db.do <<SQL
CREATE TABLE attributes (
  path #{varchar} NOT NULL,
  attrid #{intkey} NOT NULL,
  value #{content} NOT NULL,

  CONSTRAINT at_pk PRIMARY KEY(path,attrid),
  CONSTRAINT at_path FOREIGN KEY(path) REFERENCES elements(path),
  #{fk_needs_index && "INDEX at_idpath (attrid,path),"}
  CONSTRAINT at_id FOREIGN KEY(attrid) REFERENCES attr_tags(attrid)
)#{tableopt}
SQL

      db.do <<SQL
CREATE TABLE sequences (
  name #{varchar} NOT NULL PRIMARY KEY,
  nextval #{intkey} NOT NULL
)#{tableopt}
SQL

      # We want this index for everyone, however sqlite does not allow
      # 'INDEX' within a 'CREATE TABLE' (must use separate 'CREATE INDEX')
      fk_needs_index or db.do <<SQL
CREATE INDEX at_idpath ON attributes(attrid,path)
SQL

      # Because of foreign key constraints, we must insert dummy element rows for
      # element id -1 (text node), -2 (comment), -3 (processing instruction)
      db.insert('element_tags',['elemid','tag'],
	[[-1,'TEXT'],[-2,'COMMENT'],[-3,'PI']])

      # We need some initial sequences
      db.insert('sequences',['name','nextval'],
	[['namespace_id',0],['element_id',0],['attr_id',0]])

    end # db.transaction do
    nil
  end

end # module SQL
end # module ZML
