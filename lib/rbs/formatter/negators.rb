module RBS
  module Negators
    LOGICAL_OPERATOR = %i(&& ||)
    NEGATABLE_OPERATOR = %i(== != <= >= < >)

    def self.simple_negate(node)
      if negation?(node)
        node.argument
      else
        common_negate(node)
      end
    end

    def self.experimental_negate(node)
      if negation?(node)
        if logical?(node)
          negate_logical_expression(node)
        elsif negatable?(node)
          negate_binary_expression(node)
        else
          node.argument
        end
      elsif logical?(node)
        negate_logical_expression(node)
      elsif negatable?(node)
        negate_binary_expression(node)
      else
        common_negate(node)
      end
    end

    private

    def self.common_negate(node)
      if node === %i(identifier literal group_expression)
        Node.new(:unary_expression, operator: "!", argument: node)
      else
        Node.new(:unary_expression, operator: "!", argument: Node.new(:group_expression, expression: node))
      end
    end

    def self.negate_logical_expression(node)
      left = negate(node.left)
      right = negate(node.right)
      operator = node.operator == "&&" ? "||" : "&&"
      Node.new(:binary_expression, operator: operator, left: left, right: right)
    end

    def self.negate(node)
      if negation?(node)
        node.argument
      elsif logical?(node)
        negate_logical_expression(node)
      elsif negatable?(node)
        negate_binary_expression(node)
      else
        Node.new(:unary_expression, operator: "!", argument: node)
      end
    end

    def self.negate_binary_expression(node)
      right = if logical?(node.right)
                negate_logical_expression(node.right)
              elsif negatable?(node.right)
                negate_binary_expression(node.right)
              else
                node.right
              end
      operator = case node.operator
                 when "==" then "!="
                 when "!=" then "=="
                 when ">=" then "<"
                 when "<=" then ">"
                 when ">"  then "<="
                 when "<"  then ">="
                 else raise "unreachable code!"
                 end
      Node.new(:binary_expression, operator: operator, left: node.left, right: right)
    end

    def self.negation?(node)
      node === :unary_expression && node.operator == "!"
    end

    def self.logical?(node)
      node === :binary_expression && LOGICAL_OPERATOR.include?(node.operator.to_sym)
    end

    def self.negatable?(node)
      node === :binary_expression && NEGATABLE_OPERATOR.include?(node.operator.to_sym)
    end
  end
end
