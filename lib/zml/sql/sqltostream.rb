require 'zml/path'

module ZML
module SQL

class SQLtoStream

  # This generates an output XML stream from database contents
  # (element and all children)
  # 'db' is an open DBIwrapper object. 'id' is the object which holds
  # the element/attribute/namespace id to name mappings.
  # 'out' is a stream object, or in fact any object which supports
  # the '<<' operator to write a string, to which the XML is written.
  #
  # The elements of the database are output 'on the fly' as rows are
  # read out of the SQL database; no complete image of the XML document
  # is built up in RAM.

  def initialize(db, id)
    @db = db
    @id = id
  end

  def run(out, path = [], namespaces = {})
    fix_trailing_space = @db.fix_trailing_space
    tags = []
    path.size.times do
      tags << nil
    end

    stack = []     # list of [depth, tag] pairs
    depth = -1

    # The 'left join' might not be especially efficient if an element has
    # a large text content and more than one attribute, because the text
    # content will be sent more than once. However it's probably
    # better than iterating through two DB handles concurrently (one for
    # elements, one for attributes) and ensures consistency.

    lastpath = nil
    tag, attrs, text = nil, {}, nil

    @db.execute(<<SQL, ZML::pathjoin(path)+'%') do |sth|
select e.path, e.elemid, e.content, a.attrid, a.value from elements e
  left join attributes a on e.path = a.path
  where e.path like ? order by e.path, a.attrid
SQL
      rowcount = 0
      sth.fetch do |r|
        path, elemid, content, attrid, value = *r

        if fix_trailing_space # for MySQL
          content.sub!(/\|\z/,'') if content.is_a? String
          value.sub!(/\|\z/,'') if value.is_a? String
        end

        if path != lastpath   # start of a new element
          out.tag_start(tag, attrs) if tag
          out.text(text) if text
          tag, attrs, text = nil, {}, nil

          depth = ZML::pathsplit(path).size
          while stack.size > 0 and depth <= stack[-1][0]
            edepth, etag = *stack.pop
            out.tag_end(etag)
          end

          case elemid
          when -1
            out.text(content)
          when -2
            out.comment(content)
          when -3
            if content =~ /\A([^ ]+) (.*)\z/m
              out.instruction($1, $2)
            else
              out.instruction(content)
            end
          else
            tag = @id.element_fullname(elemid)
            text = content if content
            if lastpath.nil?
              # Add all known namespaces, except 'xml:'
              @id.all_namespaces.each do |uri,ns|
                next if ns == 'xml'
                attrs["xmlns:#{ns}"] = uri
              end
            end
            stack.push [depth, tag]
          end
          lastpath = path
        end
        # Now add attribute, if any
        next unless attrid
        attrs[@id.attr_fullname(attrid)] = value
      end
    end

    # Flush out anything left
    out.tag_start(tag, attrs) if tag
    out.text(text) if text
    while stack.size > 0
      edepth, etag = *stack.pop
      out.tag_end(etag)
    end

    # Tidiness
    out.text("\n")
  end

end # class SQLtoStream

end # module SQL
end # module ZML
