require File.dirname(__FILE__) + '/helper.rb'

class TestDefineConversions < Test::Unit::TestCase


  def setup
    initialize_context
  end

  def test_convert_to
    d = Decimal('1.1')
    x = d.convert_to(Rational)
    assert x.is_a?(Rational)
    assert_equal d.to_r, x

    d = Decimal('11')
    x = d.convert_to(Integer)
    assert x.is_a?(Integer)
    assert_equal d.to_i, x

    d = Decimal('11')
    x = d.convert_to(Float)
    assert x.is_a?(Float)
    assert_equal d.to_f, x
  end


  def test_big_decimal_conversions

    Decimal.local_context do

      Decimal.context.define_conversion_from(BigDecimal) do |x, context|
        Decimal(x.to_s) # or use x.split etc.
      end
      assert Decimal('0') == BigDecimal.new('0')
      assert_equal BigDecimal.new('0'), Decimal('0')
      assert_equal BigDecimal.new('1.2345'), Decimal('1.2345')
      assert_equal BigDecimal.new('-1.2345'), Decimal('-1.2345')
      assert_equal BigDecimal.new('1.2345'), Decimal('0.0012345000E3')
      assert_equal Decimal('7.1'), BigDecimal.new('7')+Decimal('0.1')
      assert_equal Decimal('7.1'), Decimal('7')+BigDecimal.new('0.1')
      assert_equal Decimal('1.1'), Decimal(BigDecimal.new('1.1'))
      assert Decimal(BigDecimal.new('1.1')).is_a?(Decimal)

      Decimal.context.define_conversion_to(BigDecimal) do |x|
        BigDecimal.new(x.to_s) # TODO: use x.split and handle special values
      end

      ['0.1', '-0.1', '0.0', '1234567.1234567', '-1234567.1234567', '1.234E7', '1.234E-7'].each do |n|
        f = BigDecimal.new(n)
        d = Decimal(n)
        c = d.convert_to(BigDecimal)
        assert c.is_a?(BigDecimal)
        assert_equal f, c
      end
    end

    assert_raise(TypeError) { Decimal('0') == BigDecimal.new('0') }
    assert_not_equal BigDecimal.new('0'), Decimal('0')
    assert_not_equal BigDecimal.new('1.2345'), Decimal('1.2345')
    assert_not_equal BigDecimal.new('-1.2345'), Decimal('-1.2345')
    assert_not_equal BigDecimal.new('1.2345'), Decimal('0.0012345000E3')
    assert_raise(TypeError) { BigDecimal.new('7')+Decimal('0.1') }
    assert_raise(TypeError) { Decimal('7')+BigDecimal.new('0.1') }
    assert_raise(TypeError) { Decimal(BigDecimal.new('1.1')) }

    ['0.1', '-0.1', '0.0', '1234567.1234567', '-1234567.1234567', '1.234E7', '1.234E-7'].each do |n|
      assert_raise(TypeError) { Decimal(n).convert_to(BigDecimal) }
    end

  end

  def test_float_conversions

    # Exact Float to Decimal conversion limited to context precision
    # => Decimal('0.1') != Decimal(0.1) unless precision is low enough
    Decimal.context.define_conversion_from(Float) do |x, context|
      s,e = Math.frexp(x)
      significand = Math.ldexp(s, Float::MANT_DIG).to_i
      exponent = e - Float::MANT_DIG
      # the number is (as a Rational) significand * exponent**Float::RADIX
      Decimal(significand*(Float::RADIX**exponent ))
    end

    assert_equal 0.0, Decimal('0')
    assert_equal Decimal('0'), 0.0
    assert_equal 1234.5, Decimal('1234.5')
    assert_equal Decimal('1234.5'), 1234.5
    assert_equal(-1234.5, Decimal('-1234.5'))
    assert_equal 1234.5, Decimal('0.0012345000E6')
    assert_equal Decimal('7.1'), 7.0+Decimal('0.1')
    Decimal.local_context(:precision=>12) do
      assert_equal Decimal('7.1'), Decimal('7')+0.1
    end
    assert_equal Decimal('11'), Decimal(11.0)
    assert Decimal(11.0).is_a?(Decimal)

  end

end