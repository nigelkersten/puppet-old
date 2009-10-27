#!/usr/bin/env ruby

require File.dirname(__FILE__) + '/../../spec_helper'
require 'puppet/indirector/queue'

class Puppet::Indirector::Queue::TestClient
end

class FooExampleData
    attr_accessor :name

    def self.pson_create(pson)
        new(pson['data'].to_sym)
    end

    def initialize(name = nil)
        @name = name if name
    end

    def render(format = :pson)
        to_pson
    end

    def to_pson(*args)
        {:type => self.class.to_s, :data => name}.to_pson(*args)
    end
end

describe Puppet::Indirector::Queue do
    confine "PSON library is missing; cannot test queueing" => Puppet.features.pson?

    before :each do
        @model = mock 'model'
        @indirection = stub 'indirection', :name => :my_queue, :register_terminus_type => nil, :model => @model
        Puppet::Indirector::Indirection.stubs(:instance).with(:my_queue).returns(@indirection)
        @store_class = Class.new(Puppet::Indirector::Queue) do
            def self.to_s
                'MyQueue::MyType'
            end
        end
        @store = @store_class.new

        @subject_class = FooExampleData
        @subject = @subject_class.new
        @subject.name = :me

        Puppet.settings.stubs(:value).returns("bogus setting data")
        Puppet.settings.stubs(:value).with(:queue_type).returns(:test_client)
        Puppet::Util::Queue.stubs(:queue_type_to_class).with(:test_client).returns(Puppet::Indirector::Queue::TestClient)

        @request = stub 'request', :key => :me, :instance => @subject
    end

    it "should require PSON" do
        Puppet.features.expects(:pson?).returns false

        lambda { @store_class.new }.should raise_error(ArgumentError)
    end

    it 'should use the correct client type and queue' do
        @store.queue.should == :my_queue
        @store.client.should be_an_instance_of(Puppet::Indirector::Queue::TestClient)
    end

    describe "when saving" do
        it 'should render the instance using pson' do
            @subject.expects(:render).with(:pson)
            @store.client.stubs(:send_message)
            @store.save(@request)
        end

        it "should send the rendered message to the appropriate queue on the client" do
            @subject.expects(:render).returns "mypson"

            @store.client.expects(:send_message).with(:my_queue, "mypson")

            @store.save(@request)
        end

        it "should catch any exceptions raised" do
            @store.client.expects(:send_message).raises ArgumentError

            lambda { @store.save(@request) }.should raise_error(Puppet::Error)
        end
    end

    describe "when subscribing to the queue" do
        before do
            @store_class.stubs(:model).returns @model
        end

        it "should use the model's Format support to intern the message from pson" do
            @model.expects(:convert_from).with(:pson, "mymessage")

            @store_class.client.expects(:subscribe).yields("mymessage")
            @store_class.subscribe {|o| o }
        end

        it "should yield each interned received message" do
            @model.stubs(:convert_from).returns "something"

            @subject_two = @subject_class.new
            @subject_two.name = :too

            @store_class.client.expects(:subscribe).with(:my_queue).multiple_yields(@subject, @subject_two)

            received = []
            @store_class.subscribe do |obj|
                received.push(obj)
            end

            received.should == %w{something something}
        end

        it "should log but not propagate errors" do
            @store_class.client.expects(:subscribe).yields("foo")
            @store_class.expects(:intern).raises ArgumentError
            Puppet.expects(:err)
            @store_class.subscribe {|o| o }
        end
    end
end

