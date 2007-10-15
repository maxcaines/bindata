module BinData
  # The enviroment in which a lazily evaluated lamba is called.  These lambdas
  # are those that are passed to data objects as parameters.  Each lambda
  # has access to the following:
  #
  # parent:: the environment of the parent data object
  # params:: any extra parameters that have been passed to the data object.
  #          The value of a parameter is either a lambda, a symbol or a
  #          literal value (such as a Fixnum).
  #
  # Unknown methods are resolved in the context of the parent environment,
  # first as keys in the extra parameters, and secondly as methods in the
  # parent data object.  This makes the lambda easier to read as we just write
  # <tt>field</tt> instead of <tt>obj.field</tt>.
  class LazyEvalEnv
    # An empty hash shared by all instances
    @@empty_hash = Hash.new.freeze

    # Creates a new environment.  +parent+ is the environment of the
    # parent data object.
    def initialize(parent = nil)
      @parent = parent
      @variables = @@empty_hash
      @overrides = @@empty_hash
    end
    attr_reader :parent, :params
    attr_accessor :data_object

    # only accessible by another LazyEvalEnv
    protected :data_object

    def params=(p)
      @params = p.empty? ? @@empty_hash : p
    end

    # Add a variable with a pre-assigned value to this environment.  +sym+
    # will be accessible as a variable for any lambda evaluated
    # with #lazy_eval.
    def add_variable(sym, value)
      if @variables.equal?(@@empty_hash)
        @variables = {}
      end
      @variables[sym.to_sym] = value
    end

    # TODO: offset_of needs to be better thought out
    def offset_of(sym)
      @parent.data_object.offset_of(sym)
    rescue
      nil
    end

    # Returns the data_object for the parent environment.
    def parent_data_object
      @parent.nil? ? nil : @parent.data_object
    end

    # Evaluates +obj+ in the context of this environment.  Evaluation
    # recurses until it yields a value that is not a symbol or lambda.
    # +overrides+ is an optional +params+ like hash
    def lazy_eval(obj, overrides = nil)
      @overrides = overrides if overrides
      if obj.is_a? Symbol
        # treat :foo as lambda { foo }
        obj = __send__(obj)
      elsif obj.respond_to? :arity
        obj = instance_eval(&obj)
      end
      @overrides = @@empty_hash
      obj
    end

    def method_missing(symbol, *args)
      if @overrides.include?(symbol)
        @overrides[symbol]
      elsif @variables.include?(symbol)
        @variables[symbol]
      elsif @parent
        obj = symbol
        if @parent.params and @parent.params.has_key?(symbol)
          obj = @parent.params[symbol]
        elsif @parent.data_object and @parent.data_object.respond_to?(symbol)
          obj = @parent.data_object.__send__(symbol, *args)
        end
        @parent.lazy_eval(obj)
      else
        super
      end
    end
  end
end
