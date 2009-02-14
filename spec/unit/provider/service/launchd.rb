#!/usr/bin/env ruby
# 
# Unit testing for the launchd service provider
#

require File.dirname(__FILE__) + '/../../../spec_helper'

require 'puppet'

provider_class = Puppet::Type.type(:service).provider(:launchd)

describe provider_class do

    before :each do
        # Create a mock resource
        @resource = stub 'resource'
        
        @provider = provider_class.new
        @joblabel = "com.foo.food"
        @jobplist = {}

        # A catch all; no parameters set
        @resource.stubs(:[]).returns(nil)

        # But set name, ensure and enable
        @resource.stubs(:[]).with(:name).returns @joblabel
        @resource.stubs(:[]).with(:ensure).returns :enabled
        @resource.stubs(:[]).with(:enable).returns :true
        @resource.stubs(:ref).returns "Service[#{@joblabel}]"

        # stub out the provider methods that actually touch the filesystem
        # or execute commands
        @provider.stubs(:plist_from_label).returns([@joblabel, @jobplist])    
        @provider.stubs(:execute).returns("")
        @provider.stubs(:resource).returns @resource
    end

    it "should have a start method for #{@provider.object_id}" do
        @provider.should respond_to(:start)
    end
    
    it "should have a stop method" do
        @provider.should respond_to(:stop)
    end
    
    it "should have an enabled? method" do
        @provider.should respond_to(:enabled?)
    end
    
    it "should have an enable method" do
        @provider.should respond_to(:enable)
    end
    
    it "should have a disable method" do
        @provider.should respond_to(:disable)
    end
    
    it "should have a status method" do
        @provider.should respond_to(:status)
    end
    
    
    describe "when checking status" do
        it "should call the external command 'launchctl list' once" do
            @provider.expects(:launchctl).with(:list).returns("rotating-strawberry-madonnas")
            @provider.status
        end
        it "should return stopped if not listed in launchctl list output" do
            @provider.stubs(:launchctl).with(:list).returns("rotating-strawberry-madonnas")
            assert_equal @provider.status, :stopped
        end
        it "should return running if listed in launchctl list output" do
            @provider.stubs(:launchctl).with(:list).returns(@joblabel)
            assert_equal @provider.status, :running
        end
    end
    
    describe "when starting the service" do
        it "should look for the relevant plist once" do
            @provider.expects(:plist_from_label).once
            @provider.start
        end
        it "should execute 'launchctl load' once without writing to the plist if the job is enabled" do
            @provider.stubs(:enabled?).returns :true
            @provider.expects(:execute).with([:launchctl, :load, @resource[:name]]).once
            @provider.start
        end
        it "should execute 'launchctl load' with writing to the plist once if the job is disabled" do
            @provider.stubs(:enabled?).returns :false
            @provider.expects(:execute).with([:launchctl, :load, "-w", @resource[:name]]).once
            @provider.start
        end
        it "should disable the job once if the job is disabled and should be disabled at boot" do
            @provider.stubs(:enabled?).returns :false
            @resource.stubs(:[]).with(:enable).returns :false
            @provider.expects(:disable).once
            @provider.start
        end
    end
    
    describe "when stopping the service" do
        it "should look for the relevant plist once" do
            @provider.expects(:plist_from_label).once
            @provider.stop
        end
        it "should execute 'launchctl unload' once without writing to the plist if the job is disabled" do
            @provider.stubs(:enabled?).returns :false
            @provider.expects(:execute).with([:launchctl, :unload, @resource[:name]]).once
            @provider.stop
        end
        it "should execute 'launchctl unload' with writing to the plist once if the job is enabled" do
            @provider.stubs(:enabled?).returns :true
            @provider.expects(:execute).with([:launchctl, :unload, "-w", @resource[:name]]).once
            @provider.stop
        end
        it "should enable the job once if the job is enabled and should be enabled at boot" do
            @provider.stubs(:enabled?).returns :true
            @resource.stubs(:[]).with(:enable).returns :true
            @provider.expects(:enable).once
            @provider.stop
        end
    end
    
    describe "when enabling the service" do
        it "should look for the relevant plist once" do
            @provider.expects(:plist_from_label).once
            @provider.stop
        end
        it "should check if the job is enabled once" do
            @provider.expects(:enabled?).once
            @provider.stop
        end
    end
    
    describe "when disabling the service" do
        it "should look for the relevant plist once" do
            @provider.expects(:plist_from_label).once
            @provider.stop
        end
    end
    
 end
