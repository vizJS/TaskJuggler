#!/usr/bin/env ruby -w
# encoding: UTF-8
#
# = LogicalOperation.rb -- The TaskJuggler III Project Management Software
#
# Copyright (c) 2006, 2007, 2008, 2009 by Chris Schlaeger <cs@kde.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of version 2 of the GNU General Public License as
# published by the Free Software Foundation.
#

require 'TjException'

class TaskJuggler

  # A LogicalOperation is the basic building block for a LogicalExpression. A
  # logical operation has one or two operands and an operator. The operands can
  # be LogicalOperation objects, fixed values or references to project data. The
  # LogicalOperation can be evaluated in a certain context. This contexts
  # determines the actual values of the project data references.
  # The evaluation is done by calling LogicalOperation#eval. The result must be
  # of a type that responds to all the operators that are used in the eval
  # method.
  class LogicalOperation

    attr_reader :operand1
    attr_accessor :operand2, :operator

    # Create a new LogicalOperation object. _opnd1_ is the mandatory operand.
    # The @operand2 and the @operator can be set later.
    def initialize(opnd1, operator = nil, opnd2 = nil)
      @operand1 = opnd1
      @operand2 = opnd2
      @operator = operator
    end

    # Evaluate the expression in a given context represented by _expr_ of type
    # LogicalExpression. The result must be of a type that responds to all the
    # operators of this function.
    def eval(expr)
      case @operator
      when nil
        if @operand1.respond_to?(:eval)
          # An operand can be a fixed value or another term. This could be a
          # LogicalOperation, LogicalFunction or anything else that provides
          # an appropriate eval() method.
          return @operand1.eval(expr)
        else
          return @operand1
        end
      when '~'
        return !coerceBoolean(@operand1.eval(expr), expr)
      when '>', '>=', '=', '<', '<=', '!='
        # Evaluate the operation for all 2 operand operations that can be
        # either interpreted as date, numbers or Strings.
        opnd1 = @operand1.eval(expr)
        opnd2 = @operand2.eval(expr)
        if opnd1.is_a?(TjTime)
          res= evalBinaryOperation(opnd1, operator, opnd2) do |o|
            coerceTime(o, expr)
          end
          return res
        elsif opnd1.is_a?(Fixnum) || opnd1.is_a?(Float) || opnd1.is_a?(Bignum)
          return evalBinaryOperation(opnd1, operator, opnd2) do |o|
            coerceNumber(o, expr)
          end
        elsif opnd1.is_a?(String)
          return evalBinaryOperation(opnd1, operator, opnd2) do |o|
            coerceString(o, expr)
          end
        else
          expr.error("First operand of a binary operation must be a date, " +
                     "a number or a string: #{opnd1}")
        end
      when '&'
        return coerceBoolean(@operand1.eval(expr), expr) &&
               coerceBoolean(@operand2.eval(expr), expr)
      when '|'
        return coerceBoolean(@operand1.eval(expr), expr) ||
               coerceBoolean(@operand2.eval(expr), expr)
      else
        expr.error("Unknown operator #{@operator} in logical expression")
      end
    end

    # Convert the operation into a textual representation. This function is used
    # for error reporting and debugging.
    def to_s
      if @operator.nil?
        "#{@operand1.to_s}"
      elsif @operand2.nil?
        "#{@operator}(#{@operand1.is_a?(String) ?
                       "'" + @operand1 + "'" : @operand1})"
      else
        "(#{@operand1.is_a?(String) ? "'" + @operand1 + "'" :
                                            @operand1} #{@operator} #{
            @operand2.is_a?(String) ? "'" + @operand2 + "'" : @operand2})"
      end
    end

  private

    # We need to do binary operator evaluation with various coerce functions.
    # This function does the evaluation of _opnd1_ and _opnd2_ with the
    # operation specified by _operator_. The operands are first coerced into
    # the proper format by calling the block.
    def evalBinaryOperation(opnd1, operator, opnd2)
      case operator
      when '>'
        return yield(opnd1) > yield(opnd2)
      when '>='
        return yield(opnd1) >= yield(opnd2)
      when '='
        return yield(opnd1) == yield(opnd2)
      when '<'
        return yield(opnd1) < yield(opnd2)
      when '<='
        return yield(opnd1) <= yield(opnd2)
      when '!='
        return yield(opnd1) != yield(opnd2)
      else
        raise "Operator error"
      end
    end

    # Force the _val_ into a boolean value.
    def coerceBoolean(val, expr)
      # First the obvious ones.
      return val if val.class == TrueClass || val.class == FalseClass
      # An empty String means false, else true.
      return !val.empty if val.is_a?(String)
      # In TJP logic 'non 0' means false.
      return val != 0 if val.is_a?(Fixnum) || val.is_a?(Bignum)

      expr.error("Operand #{val} can't be evaluated to true or false.")
    end

    # Force the _val_ into a number. In case this fails, an exception is raised.
    def coerceNumber(val, expr)
      unless val.is_a?(Fixnum) || val.is_a?(Float) || val.is_a?(Bignum)
        expr.error("Operand #{val} of type #{val.class} must be a number.")
      end
      val
    end

    # Force the _val_ into a String. In case this fails, an exception is raised.
    def coerceString(val, expr)
      unless val.respond_to?('to_s')
        expr.error("Operand #{val} of type #{val.class} can't be converted " +
                   "into a string")
      end
      val
    end

    # Force the _val_ into a String. In case this fails, an exception is raised.
    def coerceTime(val, expr)
      unless val.is_a?(TjTime)
        expr.error("Operand #{val} of type #{val.class} can't be converted " +
                   "into a date")
      end
      val
    end

  end

  # This class handles operands that are property attributes. They are
  # addressed by attribute ID and scenario index. The expression provides the
  # property reference.
  class LogicalAttribute < LogicalOperation

    def initialize(attribute, scenario)
      @scenarioIdx = scenario
      super
    end

    # To evaluate a property attribute we use the Query mechanism to retrieve
    # the value.
    def eval(expr)
      project = expr.property.project
      report = project.reportContext.report
      queryAttrs = {
        'project' => expr.property.project,
        'property' => expr.property,
        'loadUnit' => report.get('loadUnit'),
        'numberFormat' => report.get('numberFormat'),
        'currencyFormat' => report.get('currencyFormat'),
        'scenarioIdx' => @scenarioIdx,
        'attributeId' => @operand1,
        'start' => report.get('start'),
        'end' => report.get('end'),
        'costAccount' => report.get('costAccount'),
        'revenueAccount' => report.get('revenueAccount')
      }
      query = Query.new(queryAttrs)
      query.process
      # The logical expressions are mostly about comparing values. So we use
      # the sortableResult of the Query. This creates some challenges for load
      # values, as the user is not accustomed to the internal representation
      # of those.
      # Convert nil results into empty Strings if necessary
      query.sortableResult || ''
    end

    # Used for debugging and error reporting.
    def to_s # :nodoc
      "#{@scenarioIdx}.#{@operand1.to_s}"
    end

  end

  # This class handles operands that represent flags. The operation evaluates
  # to true if the property provided by the expression has the flag assigned.
  class LogicalFlag < LogicalOperation

    def initialize(opnd)
      super
    end

    # Return true if the property has the flag assigned.
    def eval(expr)
      expr.property['flags', 0].include?(@operand1)
    end

    # Used for debugging and error reporting.
    def to_s # :nodoc:
      @operand1
    end

  end

end

