# This class implements a cache.
# It stores data under qname-qclass-qtype tuples.
# Each tuple indexes a CacheData object (which
# stores a Message, and an expiration).
# If a new Message is stored to a tuple, it will
# overwrite the previous Message.
# When a Message is retrieved from the cache, the header
# and ttls will be "fixed" - i.e. AA cleared, etc.



#@TODO@ Max size for cache?
require 'singleton'
module Dnsruby
  class Cache
    @@cache = Hash.new
    def Cache.cache
      @@cache
    end
    def Cache.add(message)
      q = message.question[0]
      key = CacheKey.new(q.qname, q.qtype, q.qclass).to_s
      data = CacheData.new(message)
      @@cache[key] = data
    end
    # This method "fixes up" the response, so that the header and ttls are OK
    # The resolver will still need to copy the flags and ID across from the query
    def Cache.find(qname, qtype, qclass = Classes.IN)
      qn = Name.create(qname)
      qn.absolute = true
      key = CacheKey.new(qn, qtype, qclass).to_s
      data = @@cache[key]
      if (!data)
        return nil
      end
      if (data.expiration <= Time.now.to_i)
        @@cache.delete(key)
        return nil
      end
      return data.message
    end
    def Cache.delete(qname, qtype, qclass = Classes.IN)
      key = CacheKey.new(qname, qtype, qclass)
      @@cache.delete(key)
    end
    class CacheKey
      attr_accessor :qname, :qtype, :qclass
      def initialize(*args)
        self.qclass = Classes.IN
        if (args.length > 0)
          self.qname = Name.create(args[0])
          self.qname.absolute = true
          if (args.length > 1)
            self.qtype = Types.new(args[1])
            if (args.length > 2)
              self.qclass = Classes.new(args[2])
            end
          end
        end
      end
      def to_s
        return "#{qname.inspect} #{qclass} #{qtype}"
      end
    end
    class CacheData
      attr_reader :expiration
      def message=(m)
        @expiration = get_expiration(m)
        @message = m
      end
      def message
        q = @message.question()[0]
        m = Message.new(q.qname, q.qtype, q.qclass)
        m.header.aa = false # Anything else to do here?
        # Fix up TTLs!!
        offset = (Time.now - @time_stored).to_i
        sec_hash = @message.section_rrsets(true) # include the OPT record
        sec_hash.each {|section, rrsets|
          rrsets.each {|rrset|
            rrset.ttl = rrset.ttl - offset
            rrset.each { |rr|
              m.send("add_"+section.to_s, rr)
            }
          }
        }
        return m
      end
      def get_expiration(m)
        # Find the minimum ttl of any of the rrsets
        min_ttl = 9999999
        m.each_section {|section|
          section.rrsets.each {|rrset|
            if (rrset.ttl < min_ttl)
              min_ttl = rrset.ttl
            end
          }
        }
        if (min_ttl == 9999999)
          return 0
        end
        return (Time.now.to_i + min_ttl)
      end
      def initialize(*args)
        @expiration = 0
        @time_stored = Time.now.to_i
        self.message=(args[0])
      end
      def to_s
        return "#{self.message}"
      end
    end
  end
end