require 'bindata/io'
require 'bindata/lazy'
require 'bindata/params'
require 'bindata/registry'
require 'bindata/sanitize'
require 'stringio'

module BinData
  # Error raised when unexpected results occur when reading data from IO.
  class ValidityError < StandardError ; end

  # This is the abstract base class for all data objects.
  #
  # == Parameters
  #
  # Parameters may be provided at initialisation to control the behaviour of
  # an object.  These params are:
  #
  # [<tt>:onlyif</tt>]        Used to indicate a data object is optional.
  #                           if false, calls to #read or #write will not
  #                           perform any I/O, #num_bytes will return 0 and
  #                           #snapshot will return nil.  Default is true.
  # [<tt>:check_offset</tt>]  Raise an error if the current IO offset doesn't
  #                           meet this criteria.  A boolean return indicates
  #                           success or failure.  Any other return is compared
  #                           to the current offset.  The variable +offset+
  #                           is made available to any lambda assigned to
  #                           this parameter.  This parameter is only checked
  #                           before reading.
  # [<tt>:adjust_offset</tt>] Ensures that the current IO offset is at this
  #                           position before reading.  This is like
  #                           <tt>:check_offset</tt>, except that it will
  #                           adjust the IO offset instead of raising an error.
  class Base

    class << self

      # Instantiates this class and reads from +io+, returning the newly
      # created data object.
      def read(io)
        data = self.new
        data.read(io)
        data
      end

      def recursive?
        # data objects do not self reference by default
        false
      end

      AcceptedParameters.define_all_accessors(self, :internal, :bindata)

      def accepted_internal_parameters
        internal = AcceptedParameters.get(self, :internal)
        internal.all
      end

      def sanitize_parameters!(sanitizer, params)
        internal = AcceptedParameters.get(self, :internal)
        internal.sanitize_parameters!(sanitizer, params)
      end

      #-------------
      private

      def warn_replacement_parameter(params, bad_key, suggested_key)
        if params.has_key?(bad_key)
          warn ":#{bad_key} is not used with #{self}.  " +
               "You probably want to change this to :#{suggested_key}"
        end
      end

      def register(name, class_to_register)
        RegisteredClasses.register(name, class_to_register)
      end
    end

    bindata_optional_parameters :check_offset, :adjust_offset
    bindata_default_parameters :onlyif => true
    bindata_mutually_exclusive_parameters :check_offset, :adjust_offset

    # Creates a new data object.
    #
    # +params+ is a hash containing symbol keys.  Some params may
    # reference callable objects (methods or procs).  +parent+ is the
    # parent data object (e.g. struct, array, choice) this object resides
    # under.
    def initialize(params = {}, parent = nil)
      @params = Sanitizer.sanitize(self.class, params)
      @parent = parent
    end

    attr_reader :parent

    # Returns all the custom parameters supplied to this data object.
    def custom_parameters
      @params.custom_parameters
    end

    # Reads data into this data object.
    def read(io)
      io = BinData::IO.new(io) unless BinData::IO === io

      do_read(io)
      done_read
      self
    end

    def do_read(io)
      if eval_param(:onlyif)
        check_or_adjust_offset(io)
        clear
        _do_read(io)
      end
    end

    def done_read
      if eval_param(:onlyif)
        _done_read
      end
    end
    protected :do_read, :done_read

    # Writes the value for this data to +io+.
    def write(io)
      io = BinData::IO.new(io) unless BinData::IO === io

      do_write(io)
      io.flush
      self
    end

    def do_write(io)
      if eval_param(:onlyif)
        _do_write(io)
      end
    end
    protected :do_write

    # Returns the number of bytes it will take to write this data.
    def num_bytes(what = nil)
      num = do_num_bytes(what)
      num.ceil
    end

    def do_num_bytes(what = nil)
      if eval_param(:onlyif)
        _do_num_bytes(what)
      else
        0
      end
    end
    protected :do_num_bytes

    # Assigns the value of +val+ to this data object.  Note that +val+ will
    # always be deep copied to ensure no aliasing problems can occur.
    def assign(val)
      if eval_param(:onlyif)
        _assign(val)
      end
    end

    # Returns a snapshot of this data object.
    # Returns nil if :onlyif is false
    def snapshot
      if eval_param(:onlyif)
        _snapshot
      else
        nil
      end
    end

    # Returns the string representation of this data object.
    def to_binary_s
      io = StringIO.new
      write(io)
      io.rewind
      io.read
    end

    # Return a human readable representation of this data object.
    def inspect
      snapshot.inspect
    end

    # Return a string representing this data object.
    def to_s
      snapshot.to_s
    end

    # Returns a user friendly name of this object for debugging purposes.
    def debug_name
      if parent
        parent.debug_name_of(self)
      else
        "obj"
      end
    end

    # Returns the offset of this object wrt to its most distant ancestor.
    def offset
      if parent
        parent.offset_of(self)
      else
        0
      end
    end

    def ==(other)
      # double dispatch
      other == snapshot
    end

    def eql?(other)
      # double dispatch
      other.eql?(snapshot)
    end

    def hash
      snapshot.hash
    end
    # TODO test these

    #---------------
    private

    def check_or_adjust_offset(io)
      if has_param?(:check_offset)
        check_offset(io)
      elsif has_param?(:adjust_offset)
        adjust_offset(io)
      end
    end

    def check_offset(io)
      actual_offset = io.offset
      expected = eval_param(:check_offset, :offset => actual_offset)

      if not expected
        raise ValidityError, "offset not as expected for #{debug_name}"
      elsif actual_offset != expected and expected != true
        raise ValidityError,
              "offset is '#{actual_offset}' but " +
              "expected '#{expected}' for #{debug_name}"
      end
    end

    def adjust_offset(io)
      actual_offset = io.offset
      expected = eval_param(:adjust_offset)
      if actual_offset != expected
        begin
          seek = expected - actual_offset
          io.seekbytes(seek)
          warn "adjusting stream position by #{seek} bytes" if $VERBOSE
        rescue
          raise ValidityError,
                "offset is '#{actual_offset}' but couldn't seek to " +
                "expected '#{expected}' for #{debug_name}"
        end
      end
    end

    ###########################################################################
    # Available to subclasses

    # Returns the value of the evaluated parameter.  +key+ references a
    # parameter from the +params+ hash used when creating the data object.
    # +values+ contains data that may be accessed when evaluating +key+.
    # Returns nil if +key+ does not refer to any parameter.
    def eval_param(key, values = nil)
      LazyEvaluator.eval(no_eval_param(key), self, values)
    end

    # Returns the parameter from the +params+ hash referenced by +key+.
    # Use this method if you are sure the parameter is not to be evaluated.
    # You most likely want #eval_param.
    def no_eval_param(key)
      @params.internal_parameters[key]
    end

    # Returns whether +key+ exists in the +params+ hash used when creating
    # this data object.
    def has_param?(key)
      @params.internal_parameters.has_key?(key)
    end

    # Available to subclasses
    ###########################################################################

    ###########################################################################
    # To be implemented by subclasses

    # Resets the internal state to that of a newly created object.
    def clear
      raise NotImplementedError
    end

    # Returns true if the object has not been changed since creation.
    def clear?(*args)
      raise NotImplementedError
    end

    # Returns the debug name of +child+.  This only needs to be implemented
    # by objects that contain child objects.
    def debug_name_of(child)
      raise NotImplementedError
    end

    # Returns the offset of +child+.  This only needs to be implemented
    # by objects that contain child objects.
    def offset_of(child)
      raise NotImplementedError
    end

    # Reads the data for this data object from +io+.
    def _do_read(io)
      raise NotImplementedError
    end

    # Trigger function that is called after #do_read.
    def _done_read
      raise NotImplementedError
    end

    # Writes the value for this data to +io+.
    def _do_write(io)
      raise NotImplementedError
    end

    # Returns the number of bytes it will take to write this data.
    def _do_num_bytes(what)
      raise NotImplementedError
    end

    # Assigns the value of +val+ to this data object.  Note that +val+ will
    # always be deep copied to ensure no aliasing problems can occur.
    def _assign(val)
      raise NotImplementedError
    end

    # Returns a snapshot of this data object.
    def _snapshot
      raise NotImplementedError
    end

    # Set visibility requirements of methods to implement
    public :clear, :clear?, :debug_name_of, :offset_of
    private :_do_read, :_done_read, :_do_write, :_do_num_bytes, :_assign, :_snapshot

def single_value?
  warn "#single_value? is deprecated.  It should no longer be needed"
  false
end
public :single_value?

    # End To be implemented by subclasses
    ###########################################################################
  end
end
