require 'bundler'
Bundler.require(:default, :test)

class Minitest::Test
  def assert_token(expected, actual)
    if expected.is_a?(Array)
      assert_equal expected,
        [actual.name, actual.value, actual.line, actual.column].slice(0...expected.size)
    else
      assert_equal expected, actual.name
    end
  end

  def assert_token_values(expected, actual)
    assert_equal expected, actual
      .reject { |t| t === :whitespace }
      .map { |t| t === :STRING ? t.value.inspect : t.value }
      .compact
  end
end
