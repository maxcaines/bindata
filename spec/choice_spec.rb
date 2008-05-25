#!/usr/bin/env ruby

require File.expand_path(File.dirname(__FILE__)) + '/spec_common'
require 'bindata/choice'
require 'bindata/int'
require 'bindata/lazy'
require 'bindata/struct'

describe "Instantiating a Choice" do
  it "should ensure mandatory parameters are supplied" do
    args = {}
    lambda { BinData::Choice.new(args) }.should raise_error(ArgumentError)
    args = {:selection => 1}
    lambda { BinData::Choice.new(args) }.should raise_error(ArgumentError)
    args = {:choices => []}
    lambda { BinData::Choice.new(args) }.should raise_error(ArgumentError)
  end

  it "should fail if a given type is unknown" do
    args = {:choices => [:does_not_exist], :selection => 0}
    lambda { BinData::Choice.new(args) }.should raise_error(TypeError)
  end
end

describe "A Choice with several choices" do
  before(:each) do
    # allow specifications to select the choice
    BinData::LazyEvalEnv.class_eval { attr_accessor :choose }
    BinData::Choice.class_eval { attr_reader :env }

    @data = BinData::Choice.new(:choices => [[:int8, {:initial_value => 3}],
                                             [:int16le, {:initial_value => 5}],
                                             :int8,
                                             [:struct,
                                              {:fields =>[[:int8, :a]]}],
                                             [:int8, {:initial_value => 7}]],
                                :selection => :choose)
    @env = @data.env
  end

  it "should be able to select the choice" do
    @env.choose = 0
    @data.value.should eql(3)
    @env.choose = 1
    @data.value.should eql(5)
    @env.choose = 2
    @data.value.should eql(0)
    @env.choose = 3
    @data.a.should eql(0)
    @env.choose = 4
    @data.value.should eql(7)
  end

  it "should not be able to select an invalid choice" do
    @env.choose = -1
    lambda { @data.value }.should raise_error(IndexError)
    @env.choose = 5
    lambda { @data.value }.should raise_error(IndexError)
  end

  it "should be able to interact directly with the choice" do
    @env.choose = 0
    @data.value = 17
    @data.value.should eql(17)
  end

  it "should handle missing methods correctly" do
    @env.choose = 0

    @data.should respond_to(:value)
    @data.should_not respond_to(:does_not_exist)
    lambda { @data.does_not_exist }.should raise_error(NoMethodError)
  end

  it "should delegate methods to the selected single choice" do
    @env.choose = 1
    @data.value = 17

    @data.find_obj_for_name("does_not_exist").should be_nil
    @data.num_bytes.should eql(2)
    @data.field_names.should be_empty
    @data.value.should eql(17)

    io = StringIO.new
    @data.write(io)

    @data.clear
    @data.clear?.should be_true
    @data.value.should eql(5)

    io.rewind
    @data.read(io)
    @data.value.should eql(17)

    @data.snapshot.should eql(17)
  end

  it "should delegate methods to the selected complex choice" do
    @env.choose = 3
    @data.find_obj_for_name("a").should_not be_nil
    @data.field_names.should eql(["a"])
    @data.num_bytes.should eql(1)
  end
end

