require 'forwardable'

module BinData
  class Sanitizer
    class << self
      def sanitize(obj, params)
        sanitizer = self.new
        klass, new_params = sanitizer.sanitize(obj.class, params)
        new_params
      end

      def type_exists?(type, endian = nil)
        lookup(type, endian)
      end

      # Returns the class matching a previously registered +name+.
      def lookup(name, endian)
        name = name.to_s
        klass = Registry.instance.lookup(name)
        if klass.nil? and endian != nil
          # lookup failed so attempt endian lookup
          if /^u?int\d{1,3}$/ =~ name
            new_name = name + ((endian == :little) ? "le" : "be")
            klass = Registry.instance.lookup(new_name)
          elsif ["float", "double"].include?(name)
            new_name = name + ((endian == :little) ? "_le" : "_be")
            klass = Registry.instance.lookup(new_name)
          end
        end
        klass
      end
    end

    def initialize
      @seen   = []
      @endian = nil
    end

    # Executes the given block with +endian+ set as the current endian.
    def with_endian(endian, &block)
      if endian != nil
        saved_endian = @endian
        @endian = endian
        yield
        @endian = saved_endian
      else
        yield
      end
    end

    def sanitize(type, params)
      if Class === type
        klass = type
      else
        klass = self.class.lookup(type, @endian)
        raise TypeError, "unknown type '#{type}'" if klass.nil?
      end

      params ||= {}
      if @seen.include?(klass)
        # This klass is defined recursively.  Remember the current endian
        # and delay sanitizing the parameters until later.
        if @endian != nil and klass.accepted_parameters.include?(:endian) and
            not params.has_key?(:endian)
          params = params.dup
          params[:endian] = @endian
        end
      else
        # subclasses of MultiValue may be defined recursively
        # TODO: define a class field instead
        possibly_recursive = (BinData.const_defined?(:MultiValue) and 
                              klass.ancestors.include?(BinData.const_get(:MultiValue)))
        @seen.push klass if possibly_recursive

        new_params = klass.sanitize_parameters(self, params)
        params = SanitizedParameters.new(klass, new_params)
      end

      [klass, params]
    end

  end

  # A BinData object accepts arbitrary parameters.  This class ensures that
  # the parameters have been sanitized, and categorizes them according to
  # whether they are BinData::Base.accepted_parameters or are extra.
  class SanitizedParameters
    extend Forwardable

    # Sanitize the given parameters.
    def initialize(klass, params, *args)
      @hash = params
      @accepted_parameters = {}
      @extra_parameters = {}

      # partition parameters into known and extra parameters
      @hash.each do |k,v|
        k = k.to_sym
        if v.nil?
          raise ArgumentError, "parameter :#{k} has nil value in #{klass}"
        end

        if klass.accepted_parameters.include?(k)
          @accepted_parameters[k] = v
        else
          @extra_parameters[k] = v
        end
      end
    end

    attr_reader :accepted_parameters, :extra_parameters

    def_delegators :@hash, :[], :has_key?, :include?, :keys
  end
end

