#!/usr/bin/env ruby

require File.dirname(__FILE__) + '/../../spec_helper'

require 'puppet/transaction/event'

describe Puppet::Transaction::Event do
    [:previous_value, :desired_value, :property, :resource, :name, :message, :node, :version, :file, :line, :tags].each do |attr|
        it "should support #{attr}" do
            event = Puppet::Transaction::Event.new
            event.send(attr.to_s + "=", "foo")
            event.send(attr).should == "foo"
        end
    end

    it "should always convert the property to a string" do
        Puppet::Transaction::Event.new(:property => :foo).property.should == "foo"
    end

    it "should always convert the resource to a string" do
        Puppet::Transaction::Event.new(:resource => :foo).resource.should == "foo"
    end

    it "should produce the message when converted to a string" do
        event = Puppet::Transaction::Event.new
        event.expects(:message).returns "my message"
        event.to_s.should == "my message"
    end

    it "should support 'status'" do
        event = Puppet::Transaction::Event.new
        event.status = "success"
        event.status.should == "success"
    end

    it "should fail if the status is not to 'noop', 'success', or 'failure" do
        event = Puppet::Transaction::Event.new
        lambda { event.status = "foo" }.should raise_error(ArgumentError)
    end

    it "should support tags" do
        Puppet::Transaction::Event.ancestors.should include(Puppet::Util::Tagging)
    end

    it "should create a timestamp at its creation time" do
        Puppet::Transaction::Event.new.time.should be_instance_of(Time)
    end

    describe "when sending logs" do
        before do
            Puppet::Util::Log.stubs(:new)
        end

        it "should set the level to the resources's log level if the event status is 'success' and a resource is available" do
            resource = stub 'resource'
            resource.expects(:[]).with(:loglevel).returns :myloglevel
            Puppet::Util::Log.expects(:create).with { |args| args[:level] == :myloglevel }
            Puppet::Transaction::Event.new(:status => "success", :resource => resource).send_log
        end

        it "should set the level to 'notice' if the event status is 'success' and no resource is available" do
            Puppet::Util::Log.expects(:new).with { |args| args[:level] == :notice }
            Puppet::Transaction::Event.new(:status => "success").send_log
        end

        it "should set the level to 'notice' if the event status is 'noop'" do
            Puppet::Util::Log.expects(:new).with { |args| args[:level] == :notice }
            Puppet::Transaction::Event.new(:status => "noop").send_log
        end

        it "should set the level to 'err' if the event status is 'failure'" do
            Puppet::Util::Log.expects(:new).with { |args| args[:level] == :err }
            Puppet::Transaction::Event.new(:status => "failure").send_log
        end

        it "should set the 'message' to the event log" do
            Puppet::Util::Log.expects(:new).with { |args| args[:message] == "my message" }
            Puppet::Transaction::Event.new(:message => "my message").send_log
        end

        it "should set the tags to the event tags" do
            Puppet::Util::Log.expects(:new).with { |args| args[:tags] == %w{one two} }
            Puppet::Transaction::Event.new(:tags => %w{one two}).send_log
        end

        [:file, :line, :version].each do |attr|
            it "should pass the #{attr}" do
                Puppet::Util::Log.expects(:new).with { |args| args[attr] == "my val" }
                Puppet::Transaction::Event.new(attr => "my val").send_log
            end
        end

        it "should use the source description as the source if one is set" do
            Puppet::Util::Log.expects(:new).with { |args| args[:source] == "/my/param" }
            Puppet::Transaction::Event.new(:source_description => "/my/param", :resource => "Foo[bar]", :property => "foo").send_log
        end

        it "should use the property as the source if one is available and no source description is set" do
            Puppet::Util::Log.expects(:new).with { |args| args[:source] == "foo" }
            Puppet::Transaction::Event.new(:resource => "Foo[bar]", :property => "foo").send_log
        end

        it "should use the property as the source if one is available and no property or source description is set" do
            Puppet::Util::Log.expects(:new).with { |args| args[:source] == "Foo[bar]" }
            Puppet::Transaction::Event.new(:resource => "Foo[bar]").send_log
        end
    end
end
