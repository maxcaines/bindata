# Implement Kernel#instance_exec for Ruby 1.8.6 and below
unless Object.respond_to? :instance_exec
  module Kernel
    # Taken from http://eigenclass.org/hiki/instance_exec
    def instance_exec(*args, &block)
      mname = "__instance_exec_#{Thread.current.object_id.abs}_#{object_id.abs}"
      Object.class_eval{ define_method(mname, &block) }
      begin
        ret = send(mname, *args)
      ensure
        Object.class_eval{ undef_method(mname) } rescue nil
      end
      ret
    end
  end
end

# Implement Object#tap for Ruby 1.8.6 and below
unless Object.method_defined? :tap
  Object.class_eval do
    def tap
      yield self
      self
    end
  end
end

module BinData
  class Base
    class << self
      def register(name, class_to_register)
        if class_to_register == self
          warn "#{caller[0]} `register(name, class_to_register)' is deprecated as of BinData 1.2.0.  Replace with `register_self'"
        elsif /inherited/ =~ caller[0]
          warn "#{caller[0]} `def self.inherited(subclass); register(subclass.name, subclass); end' is deprecated as of BinData 1.2.0.  Replace with `register_subclasses'"
        else
          warn "#{caller[0]} `register(name, class_to_register)' is deprecated as of BinData 1.2.0.  Replace with `register_class(class_to_register)'"
        end
        register_class(class_to_register)
      end
    end

    def _do_read(io)
      warn "#{caller[0]} `_do_read(io)' is deprecated as of BinData 1.3.0.  Replace with `do_read(io)'"
      do_read(io)
    end

    def _do_write(io)
      warn "#{caller[0]} `_do_write(io)' is deprecated as of BinData 1.3.0.  Replace with `do_write(io)'"
      do_write(io)
    end

    def _do_num_bytes
      warn "#{caller[0]} `_do_num_bytes' is deprecated as of BinData 1.3.0.  Replace with `do_num_bytes'"
      do_num_bytes
    end

    def _assign(val)
      warn "#{caller[0]} `_assign(val)' is deprecated as of BinData 1.3.0.  Replace with `assign(val)'"
      assign(val)
    end

    def _snapshot
      warn "#{caller[0]} `_snapshot' is deprecated as of BinData 1.3.0.  Replace with `snapshot'"
      snapshot
    end
  end

  class SingleValue
    class << self
      def inherited(subclass) #:nodoc:
        fail "BinData::SingleValue is deprecated.  Downgrade to BinData 0.11.1.\nYou will need to make changes to your code before you can use BinData >= 1.0.0"
      end
    end
  end

  class MultiValue
    class << self
      def inherited(subclass) #:nodoc:
        fail "BinData::MultiValue is deprecated.  Downgrade to BinData 0.11.1.\nYou will need to make changes to your code before you can use BinData >= 1.0.0"
      end
    end
  end
end
