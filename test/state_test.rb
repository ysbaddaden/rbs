require 'test_helper'

class RBS::StateTest < Minitest::Test
  def test_is
    refute state.is(:embed)

    assert state(:embed).is(:embed)
    refute state(:embed).is(:call)

    assert state(:embed, :call).is(:call)
    refute state(:call, :embed).is(:call)
  end

  def test_case_equality
    refute state === :embed

    assert state(:embed) === :embed
    refute state(:embed) === :call

    assert state(:embed, :call) === :call
    refute state(:embed, :call) === :embed
  end

  def state(*names)
    state = RBS::State.new
    names.each { |name| state << name }
    state
  end
end
