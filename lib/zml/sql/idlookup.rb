require 'dbi'
require 'rexml/namespace'

# TODO:
# - sequences (which are DB-specific)

module ZML
module SQL

# We maintain ancilliary tables of:
#
#   namespaces:   namespace id <-> namespace uri, local tag
#   element_tags: element id   <-> (namespace, element tag)
#   attr_tags:    attr id      <-> (namespace, attr tag)
#
# Whenever we see a namespace, element or attribute we have not seen before,
# then we reload the table (in case someone else has already inserted one),
# and if not, then we insert our own. If that fails because of uniqueness
# constraints, then it means someone else got there just before us, so we
# just reload again.
#
# An interesting question arises: are attributes specific to their element?
# e.g. with
#    <section title="bar">
#    <chapter title="foo">
# are the two 'title' attributes the same or different (because they are
# associated with different elements?) Note that they have no namespace
# associated with them, even if there is a default namespace in force.
#
# I have decided that they are the *same* attribute, and thus map to the
# same attrid, because it allows us to do searches like
#     .//@title
# without regard to the parent element type. Also, when we have attributes
# which *are* qualified by a namespace, like
#    <section zml:mixedcontent="false">
#    <chapter zml:mixedcontent="true">
# then we almost certainly *are* talking about the same attribute on
# two different elements.

class IdLookup
  def initialize(db)
    @db = db  # we assume AutoCommit=>true on this handle
    @nsid2uri_prefix = {}
    @uri2nsid = {}
    @nsid_tag2elemid = {}
    @elemid2nsid_tag = {}
    @nsid_tag2attrid = {}
    @attrid2nsid_tag = {}
  end

  def all_namespaces
    reload_ns
    @nsid2uri_prefix.to_a.sort.collect { |x,y| y }
  end

  def find_namespace_id(uri=nil, prefix=nil)
    return nil if uri.nil?
    r = @uri2nsid[uri]
    return r if r
    reload_ns
    r = @uri2nsid[uri]
    return r if r
    seq = @db.seq_get('sequences','name','namespace_id','nextval')
    begin
      @db.insert("namespaces",["nsid","uri","prefix"],[[seq,uri,nil]])
      # If the preferred prefix has not been used for a different uri, then
      # take it. Otherwise the uniqueness constraint will fail, and we'll
      # be left with nil, which is converted to "zns#{nsid}" later.
      @db.do("update namespaces set prefix=? where nsid=?",
          prefix, seq) unless prefix.nil? or prefix =~ /^zns\d+$/
    rescue DBI::IntegrityError
    end
    reload_ns
    r = @uri2nsid[uri]
    return r if r
    raise "Internal error in find_namespace_id"
  end

  def namespace_info(id=nil)
    return [nil, nil] if id.nil?
    r = @nsid2uri_prefix[id]
    return r if r
    reload_ns
    r = @nsid2uri_prefix[id]
    return r if r
    # This should never happen because DB referential integrity should ensure
    # that any namespace ID in the database always points to an entry in the
    # namespaces table
    raise "Internal error in namespace_info (namespace id=#{id.inspect})"
  end

  def find_element_id(tag, nsid = nil)
    r = @nsid_tag2elemid["#{nsid}*#{tag}"]
    return r if r
    reload_elemid
    r = @nsid_tag2elemid["#{nsid}*#{tag}"]
    return r if r
    seq = @db.seq_get('sequences','name','element_id','nextval')
    begin
      @db.insert("element_tags",["elemid","nsid","tag"],[[seq,nsid,tag]])
    rescue DBI::IntegrityError
    end
    reload_elemid
    r = @nsid_tag2elemid["#{nsid}*#{tag}"]
    return r if r
    raise "Internal error in find_element_id"
  end

  # Given a tag, "foo" or "ns:foo", and an array of namespace mappings
  # [{"ns"=>"http://foo/bar", "ns2"=>"http://bar/baz"], {...}]
  # then locate the element id. The namespace mappings are tried in order
  # (so unshift a new one onto the left-hand end).
  # A default namespace is given by {""=>"http://foo/bar"}

  def find_element(fulltag, namespaces=[])
    unless REXML::Namespace::NAMESPLIT =~ fulltag
      raise "Illegal tag: #{tag.inspect}"
    end
    prefix, tag = $1, $2
    prefix ||= ""
    uri = nil
    namespaces.each { |h| uri = h[prefix]; break if uri }
    unless uri or (prefix == "")
      raise "Unknown namespace prefix in this context: #{fulltag.inspect}"
    end
    nsid = find_namespace_id(uri, prefix)   # creates it in DB if necessary
    find_element_id(tag, nsid)              # creates it in DB if necessary
  end

  def element_fullname(id, default_ns = nil)
    r = @elemid2nsid_tag[id]
    unless r
      reload_elemid
      r = @elemid2nsid_tag[id]
    end
    unless r
      # This should never happen because DB referential integrity should ensure
      # that any element ID in the database always points to an entry in the
      # element_tags table
      raise "Internal error in element_fullname"
    end
    ns, tag = *r
    return "#{tag}" if ns == default_ns
    uri, prefix = namespace_info(ns)
    return "#{prefix}:#{tag}"
  end

  def find_attr_id(tag, nsid = nil)
    r = @nsid_tag2attrid["#{nsid}*#{tag}"]
    return r if r
    reload_attrid
    r = @nsid_tag2attrid["#{nsid}*#{tag}"]
    return r if r
    seq = @db.seq_get('sequences','name','attr_id','nextval')
    begin
      @db.insert("attr_tags",["attrid","nsid","tag"], [[seq,nsid,tag]])
    rescue DBI::IntegrityError
    end
    reload_attrid
    r = @nsid_tag2attrid["#{nsid}*#{tag}"]
    return r if r
    raise "Internal error in find_attr_id"
  end

  # Given a tag, "foo" or "ns:foo", and an array of namespace mappings
  # [{"ns"=>"http://foo/bar", "ns2"=>"http://bar/baz"], {...}]
  # then locate the element id. The namespace mappings are tried in order
  # (so unshift a new one onto the left-hand end).
  # A default namespace is given by {""=>"http://foo/bar"}

  def find_attr(fulltag, namespaces=[])
    unless REXML::Namespace::NAMESPLIT =~ fulltag
      raise "Illegal attr tag: #{fulltag.inspect}"
    end
    prefix, tag = $1, $2
    nsid = nil
    if prefix
      uri = nil
      namespaces.each { |h| uri = h[prefix]; break if uri }
      unless uri
        raise "Unknown namespace prefix in this context: #{fulltag.inspect}"
      end
      nsid = find_namespace_id(uri, prefix)   # creates it in DB if necessary
    end
    find_attr_id(tag, nsid)                   # creates it in DB if necessary
  end

  def attr_fullname(id)
    r = @attrid2nsid_tag[id]
    unless r
      reload_attrid
      r = @attrid2nsid_tag[id]
    end
    unless r
      # This should never happen because DB referential integrity should ensure
      # that any attr ID in the database always points to an entry in the
      # attr_tags table
      raise "Internal error in attr_fullname"
    end
    ns, tag = *r
    return "#{tag}" if ns.nil?
    uri, prefix = namespace_info(ns)
    return "#{prefix}:#{tag}"
  end

private
  def reload_ns
    #@db ||= DBI.connect(*@db_params)
    @nsid2uri_prefix = {}
    @uri2nsid = {}
    @db.execute("select nsid, uri, prefix from namespaces") do |sth|
      sth.fetch do |r|
        @nsid2uri_prefix[r[0]] = [r[1], r[2]]
        @uri2nsid[r[1]] = r[0]
      end
    end
  end

  def reload_elemid
    #@db ||= DBI.connect(*@db_params)
    @nsid_tag2elemid = {}
    @elemid2nsid_tag = {}
    @db.execute("select elemid, nsid, tag from element_tags") do |sth|
      sth.fetch do |r|
        @elemid2nsid_tag[r[0]] = [r[1], r[2]]
        @nsid_tag2elemid["#{r[1]}*#{r[2]}"] = r[0]
      end
    end
  end

  def reload_attrid
    #@db ||= DBI.connect(*@db_params)
    @nsid_tag2attrid = {}
    @attrid2nsid_tag = {}
    @db.execute("select attrid, nsid, tag from attr_tags") do |sth|
      sth.fetch do |r|
        @attrid2nsid_tag[r[0]] = [r[1], r[2]]
        @nsid_tag2attrid["#{r[1]}*#{r[2]}"] = r[0]
      end
    end
  end

end

end # module SQL
end # module ZML
