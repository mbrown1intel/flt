require 'bigdecimal'
require 'forwardable'
require 'rational'
require 'monitor'


module FPNum


# BigDecimal-based Decimal implementation
module BD

# Decimal arbitrary precision floating point number.
class Decimal

  extend FPNum # allows use of unqualified FlagValues(), Flags()
  include BD # allows use of unqualified Decimal()

  ROUND_HALF_EVEN = BigDecimal::ROUND_HALF_EVEN
  ROUND_HALF_DOWN = BigDecimal::ROUND_HALF_DOWN
  ROUND_HALF_UP = BigDecimal::ROUND_HALF_UP
  ROUND_FLOOR = BigDecimal::ROUND_FLOOR
  ROUND_CEILING = BigDecimal::ROUND_CEILING
  ROUND_DOWN = BigDecimal::ROUND_DOWN
  ROUND_UP = BigDecimal::ROUND_UP
  ROUND_05UP = nil

  class Error < StandardError
  end

  class Exception < StandardError
    attr :context
    def initialize(context=nil)
      @context = context
    end
  end

  class InvalidOperation < Exception
  end

  class DivisionByZero < Exception
  end

  class DivisionImpossible < Exception
  end

  class DivisionUndefined < Exception
  end

  class Inexact < Exception
  end

  class Overflow < Exception
  end

  class Underflow < Exception
  end

  class Clamped < Exception
  end

  class InvalidContext < Exception
  end

  class Rounded < Exception
  end

  class Subnormal < Exception
  end

  class ConversionSyntax < InvalidOperation
  end

  EXCEPTIONS = FlagValues(Clamped, InvalidOperation, DivisionByZero, Inexact, Overflow, Underflow, Rounded, Subnormal, DivisionImpossible)

  def self.Flags(*values)
    FPNum::Flags(EXCEPTIONS,*values)
  end


  # The context defines the arithmetic context: rounding mode, precision,...
  # Decimal.context is the current (thread-local) context.
  class Context

    include BD # allows use of unqualified Decimal()

    def initialize(*options)

      if options.first.instance_of?(Context)
        base = options.shift
        copy_from base
      else
        @signal_flags = true # no flags updated if false
        @quiet = false # no traps or flags updated if ture        @ignored_flags = Decimal::Flags()
        @ignored_flags = Decimal::Flags()
        @traps = Decimal::Flags()
        @flags = Decimal::Flags()
      end
      assign options.first

    end

    attr_accessor :rounding, :emin, :emax, :flags, :traps, :quiet, :signal_flags, :ignored_flags, :capitals, :clamp

    def ignore_all_flags
      #@ignored_flags << EXCEPTIONS
      @ignored_flags.set!
    end
    def ignore_flags(*flags)
      #@ignored_flags << flags
      @ignored_flags.set(*flags)
    end
    def regard_flags(*flags)
      @ignored_flags.clear(*flags)
    end

    def etiny
      emin - precision + 1
    end
    def etop
      emax - precision + 1
    end

    def digits
      self.precision
    end
    def digits=(n)
      self.precision=n
    end
    def prec
      self.precision
    end
    def prec=(n)
      self.precision = n
    end
    def clamp?
      @clamp
    end
    def precision=(n)
      @precision = n
      @exact = false unless n==0
      update_precision
      n
    end
    def precision
      @precision
    end
    def exact=(v)
      @exact = v
      update_precision
      v
    end
    def exact
      @exact
    end
    def exact?
      @exact
    end


    def assign(options)
      if options
        @rounding = options[:rounding] unless options[:rounding].nil?
        @precision = options[:precision] unless options[:precision].nil?
        @traps = Decimal::Flags(options[:traps]) unless options[:traps].nil?
        @flags = Decimal::Flags(options[:flags]) unless options[:flags].nil?
        @ignored_flags = Decimal::Flags(options[:ignored_flags]) unless options[:ignored_flags].nil?
        @emin = options[:emin] unless options[:emin].nil?
        @emax = options[:emax] unless options[:emax].nil?
        @capitals = options[:capitals ] unless options[:capitals ].nil?
        @clamp = options[:clamp ] unless options[:clamp ].nil?
        @exact = options[:exact ] unless options[:exact ].nil?
        @quiet = options[:quiet ] unless options[:quiet ].nil?
        @signal_flags = options[:signal_flags ] unless options[:signal_flags ].nil?
        update_precision
      end
    end

    def copy_from(other)
      @rounding = other.rounding
      @precision = other.precision
      @traps = other.traps.dup
      @flags = other.flags.dup
      @ignored_flags = other.ignored_flags.dup
      @emin = other.emin
      @emax = other.emax
      @capitals = other.capitals
      @clamp = other.clamp
      @exact = other.exact
      @quiet = other.quiet
      @signal_flags = other.signal_flags
    end

    def dup
      Context.new(self)
    end


    def _fix_bd(x)
      x = as_bd(x)
      if x.finite? && !@exact
        compute { x*BigDecimal('1') }
      else
        x
      end
    end

    def add(x,y)
      compute { Decimal(as_bd(x)+as_bd(y)) }
    end
    def substract(x,y)
      compute { Decimal(as_bd(x)-as_bd(y)) }
    end
    def multiply(x,y)
      compute { Decimal(as_bd(x)*as_bd(y)) }
    end
    def divide(x,y)
      x = as_bd(x)
      y = as_bd(y)
      if exact? && x.finite? && y.finite?
        x_number_of_digits = x.split[1].size
        y_number_of_digits = y.split[1].size
        prec = x_number_of_digits + 4*y_number_of_digits
        compute {
          z = x.div(y, prec)
          raise Decimal::Inexact if z*y != x
          Decimal(z)
        }
      else
        compute { Decimal(x.div(y,@precision)) }
      end
    end

    def abs(x)
      compute { Decimal(as_bd(x).abs) }
    end

    def plus(x)
      Decimal(x)._fix(self)
    end

    def minus(x)
      compute { Decimal(-as_bd(x)) }
    end

    def to_string(x)
      as_bd(x).to_s('F')
    end


    def reduce(x)
      # nop: BigDecimals are always in reduced form
      Decimal(x)
    end

    # Adjusted exponent of x returned as a Decimal value.
    def logb(x)
      compute { Decimal(Decimal(x).adjusted_exponent) }
    end

    # x*(radix**y) y must be an integer
    def scaleb(x, y)
      i = y.to_i
      if i
        compute { Decimal(as_bd(x) * (BigDecimal('10')**y.to_i)) }
      else
        nan
      end
    end

    # Exponent in relation to the significand as an integer
    # normalized to precision digits. (minimum exponent)
    def normalized_integral_exponent(x)
      x = Decimal(x)
      x.integral_exponent - (precision - x.number_of_digits)
    end

    # Significand normalized to precision digits
    # x == normalized_integral_significand(x) * radix**(normalized_integral_exponent)
    def normalized_integral_significand(x)
      x = Decimal(x)
      x.integral_significand*(10**(precision - x.number_of_digits))
    end

    def to_normalized_int_scale(x)
      x = Decimal(x)
      [x.sign*normalized_integral_significand(x), normalized_integral_exponent(x)]
    end


    # TO DO:
    # Ruby-style:
    #  ** power
    # GDAS
    #  quantize, rescale: cannot be done with BigDecimal
    #  power
    #  exp log10 ln
    #  remainder_near

    def sqrt(x)
      x = Decimal(x)
      if exact?
        prec = (x.number_of_digits << 1) + 1
        x = x._value
        y,z = compute{ v=x.sqrt(prec); [v,v*v] }
        raise Decimal::Inexact if z!=x
        Decimal(y)
      else
        compute { Decimal(x._value.sqrt(@precision)) }
      end
    end

    # Ruby-style integer division.
    def div(x,y)
      compute { Decimal(as_bd(x).div(as_bd(y))) }
    end
    # Ruby-style modulo.
    def modulo(x,y)
      compute { Decimal(as_bd(x).modulo(as_bd(y))) }
    end
    # Ruby-style integer division and modulo.
    def divmod(x,y)
      compute { as_bd(x).divmod(as_bd(y)).map{|z| Decimal(z)} }
    end

    # General Decimal Arithmetic Specification integer division
    def divide_int(x,y)
      # compute { Decimal(x._value/y._value).truncate }
      compute(:rounding=>ROUND_DOWN) { Decimal((as_bd(x)/as_bd(y)).truncate) }
    end
    # General Decimal Arithmetic Specification remainder
    def remainder(x,y)
      compute { Decimal(as_bd(x).remainder(as_bd(y))) }
    end
    # General Decimal Arithmetic Specification remainder-near
    def remainder_near(x,y)
      compute do
        if exact?
          # TO DO....
          raise Decimal::Inexact
        else
          x,y = as_bd(x),as_bd(y)
          z = (x.div(y, @precision)).round
          Decimal(x - y*z)
        end
      end
    end


    def zero(sign=+1)
      Decimal.zero(sign)
    end
    def infinity(sign=+1)
      Decimal.infinity(sign)
    end
    def nan
      Decimal.nan
    end


    def compare(x,y)
      cmp = x<=>y
      cmp.nil? ? nan : Decimal(cmp)
    end

    def copy_abs(x)
      Decimal(as_bd(x).abs)
    end

    def copy_negate(x)
      Decimal(-as_bd(x))
    end

    def copy_sign(x,y)
      x,y = as_bd(x).abs,as_bd(y)
      Decimal(y<0 ? -x : x)
    end

    def rescale(x,exp)
      Decimal(x)
    end

    def quantize(x,y)
      Decimal(x)
    end

    def same_quantum?(x,y)
      true
    end

    def to_integral_value(x)
      i = x.to_i
      if i
        Decimal(x.to_i)
      else
        nan
      end
    end

    def to_integral_exact(x)
      i = x.to_i
      if i
        Decimal(x.to_i)
      else
        nan
      end
    end

    def integral?(x)
      Decimal(x).integral?
    end

    def fma(x,y,z)
      exact_context = self.dup
      exact_context.exact = true
      product = exact_context.multiply(x,y)
      add(product,z)
    end

    def Context.round(x, opt={})
      opt = { :places=>opt } if opt.kind_of?(Integer)
      r = opt[:rounding] || :half_up
      as_int = false
      if v=(opt[:precision] || opt[:significant_digits])
        places = v - x.adjusted_exponent - 1
      elsif v=(opt[:places])
        places = v
      else
        places = 0
        as_int = true
      end
      result = x._value.round(places, big_decimal_rounding(r))
      return as_int ? result.to_i : Decimal.new(result)
    end

    def to_s
      inspect
    end
    def inspect
      "<#{self.class}:\n" +
      instance_variables.map { |v| "  #{v}: #{eval(v.to_s)}"}.join("\n") +
      ">\n"
    end

    protected

    @@compute_lock = Monitor.new
    # Use of BigDecimal is done in blocks passed to this method, which sets
    # the rounding mode and precision defined in the context.
    # Since the BigDecimal rounding mode and precision is a global resource,
    # a lock must be used to prevent other threads from modifiying it.
    UPDATE_FLAGS = true

    def compute(options={})
      rnd = Context.big_decimal_rounding(options[:rounding] || @rounding)
      prc = options[:precision] || options[:digits] || @precision
      trp = Decimal.Flags(options[:traps] || @traps)
      quiet = options[:quiet] || @quiet
      result = nil
      @@compute_lock.synchronize do
        keep_limit = BigDecimal.limit(prc)
        keep_round_mode = BigDecimal.mode(BigDecimal::ROUND_MODE, rnd)
        BigDecimal.mode BigDecimal::ROUND_MODE, rnd
        keep_exceptions = BigDecimal.mode(BigDecimal::EXCEPTION_ALL)
        if (trp.any? || @signal_flags) && !quiet
          BigDecimal.mode(BigDecimal::EXCEPTION_ALL, true)
          BigDecimal.mode(BigDecimal::EXCEPTION_INFINITY, true)
          BigDecimal.mode(BigDecimal::EXCEPTION_UNDERFLOW, true)
        else
          BigDecimal.mode(BigDecimal::EXCEPTION_ALL, false)
          BigDecimal.mode(BigDecimal::EXCEPTION_INFINITY, false)
          BigDecimal.mode(BigDecimal::EXCEPTION_UNDERFLOW, false)
        end
        begin
          result = yield
        rescue FloatDomainError=>err
          case err.message
            when "(VpDivd) Divide by zero"
              @flags << DivisionByZero
              raise DivisionByZero if trp[DivisionByZero]
              BigDecimal.mode(BigDecimal::EXCEPTION_ZERODIVIDE, false)
              retry # to set the result value
            when "exponent overflow", "Computation results to 'Infinity'", "Computation results to '-Infinity'", "Exponent overflow"
              @flags << Overflow
              raise Overflow if trp[Overflow]
              BigDecimal.mode(BigDecimal::EXCEPTION_OVERFLOW, false)
              retry # to set the result value
            when "(VpDivd) 0/0 not defined(NaN)", "Computation results to 'NaN'(Not a Number)", "Computation results to 'NaN'",  "(VpSqrt) SQRT(NaN or negative value)",
                  "(VpSqrt) SQRT(negative value)"
              @flags << InvalidOperation
              raise InvalidOperation if trp[InvalidOperation]
              #BigDecimal.mode(BigDecimal::EXCEPTION_NaN, false)
              #retry # to set the result value
              BigDecimal.mode(BigDecimal::EXCEPTION_ALL, false)
              result = nan
            when "BigDecimal to Float conversion"
              @flags << InvalidOperation
              raise InvalidOperation if trp[InvalidOperation]
              BigDecimal.mode(BigDecimal::EXCEPTION_ALL, false)
              result = nan
            when "Exponent underflow"
              @flags << Underflow
              raise Underflow if trp[Underflow]
              BigDecimal.mode(BigDecimal::EXCEPTION_UNDERFLOW, false)
              retry # to set the result value
          end
        end
        BigDecimal.limit keep_limit
        BigDecimal.mode BigDecimal::ROUND_MODE, keep_round_mode
        [BigDecimal::EXCEPTION_NaN, BigDecimal::EXCEPTION_INFINITY, BigDecimal::EXCEPTION_UNDERFLOW,
         BigDecimal::EXCEPTION_OVERFLOW, BigDecimal::EXCEPTION_ZERODIVIDE].each do |exc|
           value =  ((keep_exceptions & exc)!=0)
           BigDecimal.mode(exc, value)
        end
      end
      if result.instance_of?(Decimal)
        if result.finite?
          e =  result.adjusted_exponent
          if e>@emax
            #result = infinity(result.sign)
            result = nan
            @flags << Overflow if @signal_flags && !quiet
            raise Overflow if trp[Overflow]
          elsif e<@emin
            result = zero(result.sign)
            @flags << Underflow if @signal_flags && !quiet
            raise Underflow if trp[Underflow]
          end
        elsif @signal_flags && !quiet
          @flags << InvalidOperation if result.nan?
        end
      end
      result
    end

    def update_precision
      if @exact || @precision==0
        @exact = true
        @precision = 0
        @traps << Inexact
        @ignored_flags[Inexact] = false
      else
        @traps[Inexact] = false
      end
    end

    def as_bd(x)
      case x
      when Decimal
        x._value
      when BigDecimal
        x
      when Integer
        BigDecimal(x.to_s)
      when Rational
        Decimal.new(x)._value
      else
        raise TypeError, "Unable to convert #{x.class} to Decimal" if error
      end
    end

    ROUNDING_MODES_NAMES = {
      :half_even=>ROUND_HALF_EVEN,
      :half_up=>ROUND_HALF_UP,
      :half_down=>ROUND_HALF_DOWN,
      :floor=>ROUND_FLOOR,
      :ceiling=>ROUND_CEILING,
      :down=>ROUND_DOWN,
      :up=>ROUND_UP,
      :up05=>ROUND_05UP
    }
    ROUNDING_MODES = [
      ROUND_HALF_EVEN,
      ROUND_HALF_DOWN,
      ROUND_HALF_UP,
      ROUND_FLOOR,
      ROUND_CEILING,
      ROUND_DOWN,
      ROUND_UP,
      ROUND_05UP
    ]
    def Context.big_decimal_rounding(m)
      mode = m
      if mode.kind_of?(Symbol)
        mode = ROUNDING_MODES_NAMES[mode]
      end
      raise Error,"Invalid rounding mode #{m.inspect}"  unless mode && ROUNDING_MODES.include?(mode)
      mode
    end

  end


  # the DefaultContext is the base for new contexts; it can be changed.
  DefaultContext = Decimal::Context.new(
                             :exact=>false, :precision=>28, :rounding=>:half_even,
                             :emin=> -999999999, :emax=>+999999999,
                             :flags=>[],
                             :traps=>[DivisionByZero, Overflow, InvalidOperation],
                             :ignored_flags=>[],
                             :capitals=>true,
                             :clamp=>true)

  BasicContext = Decimal::Context.new(DefaultContext,
                             :precision=>9, :rounding=>:half_up,
                             :traps=>[DivisionByZero, Overflow, InvalidOperation, Clamped, Underflow],
                             :flags=>[])

  ExtendedContext = Decimal::Context.new(DefaultContext,
                             :precision=>9, :rounding=>:half_even,
                             :traps=>[], :flags=>[], :clamp=>false)


  # Context constructor; if an options hash is passed, the options are
  # applied to the default context; if a Context is passed as the first
  # argument, it is used as the base instead of the default context.
  def Decimal.Context(*args)
    case args.size
      when 0
        base = DefaultContext
      when 1
        arg = args.first
        if arg.instance_of?(Context)
          base = arg
          options = nil
        elsif arg.instance_of?(Hash)
          base = DefaultContext
          options = arg
        else
          raise TypeError,"invalid argument for Decimal.Context"
        end
      when 2
        base = args.first
        options = args.last
      else
        raise ARgumentError,"wrong number of arguments (#{args.size} for 0, 1 or 2)"
    end

    if options.nil? || options.empty?
      base
    else
      Context.new(base, options)
    end

  end

  # Define a context by passing either a Context object or a (possibly empty)
  # hash of options to alter de current context.
  def Decimal.define_context(*options)
    if options.size==1 && options.first.instance_of?(Context)
      options.first
    else
      Context(Decimal.context, *options)
    end
  end


  # The current context (thread-local).
  def Decimal.context
    Thread.current['FPNum::BD::Decimal.context'] ||= DefaultContext.dup
  end

  # Change the current context (thread-local).
  def Decimal.context=(c)
    Thread.current['FPNum::BD::Decimal.context'] = c.dup
  end

  # Defines a scope with a local context. A context can be passed which will be
  # set a the current context for the scope. Changes done to the current context
  # are reversed when the scope is exited.
  def Decimal.local_context(c=nil)
    keep = context.dup
    if c.kind_of?(Hash)
      Decimal.context.assign c
    else
      Decimal.context = c unless c.nil?
    end
    result = yield Decimal.context
    Decimal.context = keep
    result
  end

  def zero(sign=+1)
  end
  def infinity(sign=+1)
    compute(:quiet=>true) { Decimal(BigDecimal(sign.to_s)/BigDecimal('0')) }
  end
  def nan
    compute(:quiet=>true) { Decimal(BigDecimal('0')/BigDecimal('0')) }
  end

  def Decimal._sign_symbol(sign)
    sign<0 ? '-' : '+'
  end

  def Decimal.zero(sign=+1)
    Decimal.new("#{_sign_symbol(sign)}0")
  end
  def Decimal.infinity(sign=+1)
    Decimal.new("#{_sign_symbol(sign)}Infinity")
  end
  def Decimal.nan()
    Decimal.new('NaN')
  end

  def initialize(*args)
    context = nil
    if args.size>0 && args.last.instance_of?(Context)
      context ||= args.pop
    elsif args.size>1 && args.last.instance_of?(Hash)
      context ||= args.pop
    elsif args.size==1 && args.last.instance_of?(Hash)
      arg = args.last
      args = [arg[:sign], args[:coefficient], args[:exponent]]
      context ||= arg # TO DO: remove sign, coeff, exp form arg
    end

    context = Decimal.define_context(context)

    case args.size
    when 3
      @value = BigDecimal.new("#{_sign_symbol(args[0])}#{args[1]}E#{args[2]}")

    when 1
      arg = args.first
      case arg

      when BigDecimal
        @value = arg

      when Decimal
        @value = arg._value
      when Integer
        @value = BigDecimal.new(arg.to_s)

      when Rational
        if !context.exact? || ((arg.numerator % arg.denominator)==0)
          num = arg.numerator.to_s
          den = arg.denominator.to_s
          prec = context.exact? ? num.size + 4*den.size : context.precision
          @value = BigDecimal.new(num).div(BigDecimal.new(den), prec)
        else
          raise Inexact
        end

      when String
        arg = arg.to_s.sub(/Inf(?:\s|\Z)/i, 'Infinity')
        @value = BigDecimal.new(arg.to_s)

      when Array
        @value = BigDecimal.new("#{_sign_symbol(arg[0])}#{arg[1]}E#{arg[2]}")

      else
        raise TypeError, "invalid argument #{arg.inspect}"
      end
    else
      raise ArgumentError, "wrong number of arguments (#{args.size} for 1 or 3)"
    end

  end

  def _value # :nodoc:
    @value
  end

  def coerce(other)
    case other
      when Decimal,Integer,Rational
        [Decimal(other),self]
      else
        super
    end
  end

  def _bin_op(op, meth, other, context=nil)
    case other
      when Decimal,Integer,Rational
        other = Decimal.new(other) unless other.instance_of?(Decimal)
        Decimal.define_context(context).send meth, self, other
      else
        x, y = other.coerce(self)
        x.send op, y
    end
  end
  private :_bin_op

  def -@(context=nil)
    Decimal.define_context(context).minus(self)
  end

  def +@(context=nil)
    Decimal.define_context(context).plus(self)
  end

  def +(other, context=nil)
    _bin_op :+, :add, other, context
  end

  def -(other, context=nil)
    _bin_op :-, :substract, other, context
  end

  def *(other, context=nil)
    _bin_op :*, :multiply, other, context
  end

  def /(other, context=nil)
    _bin_op :/, :divide, other, context
  end

  def %(other, context=nil)
    _bin_op :%, :modulo, other, context
  end


  def add(other, context=nil)
    Decimal.define_context(context).add(self,other)
  end

  def substract(other, context=nil)
    Decimal.define_context(context).substract(self,other)
  end

  def multiply(other, context=nil)
    Decimal.define_context(context).multiply(self,other)
  end

  def divide(other, context=nil)
    Decimal.define_context(context).divide(self,other)
  end

  def abs(context=nil)
    Decimal.define_context(context).abs(self)
  end

  def plus(context=nil)
    Decimal.define_context(context).plus(self)
  end

  def minus(context=nil)
    Decimal.define_context(context).minus(self)
  end

  def sqrt(context=nil)
    Decimal.define_context(context).sqrt(self)
  end

  def div(other, context=nil)
    Decimal.define_context(context).div(self,other)
  end

  def modulo(other, context=nil)
    Decimal.define_context(context).modulo(self,other)
  end

  def divmod(other, context=nil)
    Decimal.define_context(context).divmod(self,other)
  end

  def divide_int(other, context=nil)
    Decimal.define_context(context).divide_int(self,other)
  end

  def remainder(other, context=nil)
    Decimal.define_context(context).remainder(self,other)
  end

  def remainder_near(other, context=nil)
    Decimal.define_context(context).remainder_near(self,other)
  end

  def reduce(context=nil)
    Decimal.define_context(context).reduce(self)
  end

  def logb(context=nil)
    Decimal.define_context(context).logb(self)
  end

  def scaleb(s, context=nil)
    Decimal.define_context(context).scaleb(self, s)
  end

  def compare(other, context=nil)
    Decimal.define_context(context).compare(self, other)
  end

  def copy_abs(context=nil)
    Decimal.define_context(context).copy_abs(self)
  end
  def copy_negate(context=nil)
    Decimal.define_context(context).copy_negate(self)
  end
  def copy_sign(other,context=nil)
    Decimal.define_context(context).copy_sign(self,other)
  end
  def rescale(exp,context=nil)
    Decimal.define_context(context).rescale(self,exp)
  end
  def quantize(other,context=nil)
    Decimal.define_context(context).quantize(self,other)
  end
  def same_quantum?(other,context=nil)
    Decimal.define_context(context).same_quantum?(self,other)
  end
  def to_integral_value(context=nil)
    Decimal.define_context(context).to_integral_value(self)
  end
  def to_integral_exact(context=nil)
    Decimal.define_context(context).to_integral_exact(self)
  end

  def fma(other, third, context=nil)
    Decimal.define_context(context).fma(self, other, third)
  end

  def round(opt={})
    Context.round(self, opt)
  end

  def ceil(opt={})
    opt[:rounding] = :ceiling
    round opt
  end

  def floor(opt={})
    opt[:rounding] = :floor
    round opt
  end

  def truncate(opt={})
    opt[:rounding] = :down
    round opt
  end

  def to_i
    @value.to_i
  end

  def to_s(context=nil)
    Decimal.define_context(context).to_string(self)
  end

  def inspect
    "Decimal('#{self}')"
  end

  def <=>(other)
    case other
      when Decimal,Integer,Rational
        self._value <=> Decimal(other)._value
      else
        if defined? other.coerce
          x, y = other.coerce(self)
          x <=> y
        else
          nil
        end
      end
  end
  def ==(other)
    (self<=>other) == 0
  end
  include Comparable

  extend Forwardable
  [:infinite?, :nan?, :zero?, :nonzero?].each do |m|
    def_delegator :@value, m, m
  end
  def finite?
    _value.finite? || _value.zero?
  end

  def special?
    !finite?
  end


  # Exponent of the magnitude of the most significant digit of the operand
  def adjusted_exponent
    @value.exponent - 1
  end

  def scientific_exponent
    adjusted_exponent
  end
  # Exponent as though the significand were a fraction (the decimal point before its first digit)
  def fractional_exponent
    # scientific_exponent + 1
    @value.exponent
  end

  # Number of digits in the significand
  def number_of_digits
    @value.split[1].size
  end

  # Significand as an integer
  def integral_significand
    @value.split[1].to_i
  end

  # Exponent of the significand as an integer
  def integral_exponent
    fractional_exponent - number_of_digits
  end

  # +1 / -1 (also for zero and infinity); nil for NaN
  def sign
    if nan?
      nil
    else
      @value.sign < 0 ? -1 : +1
    end
  end

  def to_int_scale
    if special?
      nil
    else
      [sign*integral_significand, integral_exponent]
    end
  end

  def _fix(context)
    Decimal.new(context._fix_bd(@value))
  end

  def integral?
    @value.frac == 0
  end

  def _convert(x, error=true)
    case x
    when Decimal
      x
    when Integer, Rational
      Decimal(x)
    else
      raise TypeError, "Unable to convert #{x.class} to Decimal" if error
      nil
    end
  end


  private

  def _fix!(context)
    @value = context._fix_bd(@value) if @value.finite?
  end




end

# Decimal constructor
def Decimal(v)
  case v
    when Decimal
      v
    else
      Decimal.new(v)
  end
end
module_function :Decimal

end
end
