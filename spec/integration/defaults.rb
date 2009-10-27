#!/usr/bin/env ruby

require File.dirname(__FILE__) + '/../spec_helper'

require 'puppet/defaults'

describe "Puppet defaults" do
        include Puppet::Util::Execution
    after { Puppet.settings.clear }

    describe "when setting the :factpath" do
        it "should add the :factpath to Facter's search paths" do
            Facter.expects(:search).with("/my/fact/path")

            Puppet.settings[:factpath] = "/my/fact/path"
        end
    end

    describe "when setting the :certname" do
        it "should fail if the certname is not downcased" do
            lambda { Puppet.settings[:certname] = "Host.Domain.Com" }.should raise_error(ArgumentError)
        end
    end

    describe "when configuring the :crl" do
        it "should warn if :cacrl is set to false" do
            Puppet.expects(:warning)
            Puppet.settings[:cacrl] = 'false'
        end
    end

    it "should have a clientyamldir setting" do
        Puppet.settings[:clientyamldir].should_not be_nil
    end

    it "should have different values for the yamldir and clientyamldir" do
        Puppet.settings[:yamldir].should_not == Puppet.settings[:clientyamldir]
    end

    # See #1232
    it "should not specify a user or group for the clientyamldir" do
        Puppet.settings.setting(:clientyamldir).owner.should be_nil
        Puppet.settings.setting(:clientyamldir).group.should be_nil
    end

    it "should use the service user and group for the yamldir" do
        Puppet.settings.stubs(:service_user_available?).returns true
        Puppet.settings.setting(:yamldir).owner.should == Puppet.settings[:user]
        Puppet.settings.setting(:yamldir).group.should == Puppet.settings[:group]
    end

    # See #1232
    it "should not specify a user or group for the rundir" do
        Puppet.settings.setting(:rundir).owner.should be_nil
        Puppet.settings.setting(:rundir).group.should be_nil
    end

    it "should specify that the host private key should be owned by the service user" do
        Puppet.settings.stubs(:service_user_available?).returns true
        Puppet.settings.setting(:hostprivkey).owner.should == Puppet.settings[:user]
    end

    it "should specify that the host certificate should be owned by the service user" do
        Puppet.settings.stubs(:service_user_available?).returns true
        Puppet.settings.setting(:hostcert).owner.should == Puppet.settings[:user]
    end

    it "should use a bind address of ''" do
        Puppet.settings[:bindaddress].should == ""
    end

    [:factdest].each do |setting|
        it "should force the :factdest to be a directory" do
            Puppet.settings[setting].should =~ /\/$/
        end
    end

    [:modulepath, :factpath].each do |setting|
        it "should configure '#{setting}' not to be a file setting, so multi-directory settings are acceptable" do
            Puppet.settings.setting(setting).should be_instance_of(Puppet::Util::Settings::Setting)
        end
    end

    it "should add /usr/sbin and /sbin to the path if they're not there" do
        withenv("PATH" => "/usr/bin:/usr/local/bin") do
            Puppet.settings[:path] = "none" # this causes it to ignore the setting
            ENV["PATH"].split(File::PATH_SEPARATOR).should be_include("/usr/sbin")
            ENV["PATH"].split(File::PATH_SEPARATOR).should be_include("/sbin")
        end
    end

    it "should default to pson for the preferred serialization format" do
        Puppet.settings.value(:preferred_serialization_format).should == "pson"
    end

    describe "when enabling storeconfigs" do
        before do
            Puppet::Resource::Catalog.stubs(:cache_class=)
            Puppet::Node::Facts.stubs(:cache_class=)
            Puppet::Node.stubs(:cache_class=)

            Puppet.features.stubs(:rails?).returns true
        end

        it "should set the Catalog cache class to :active_record" do
            Puppet::Resource::Catalog.expects(:cache_class=).with(:active_record)
            Puppet.settings[:storeconfigs] = true
        end

        it "should not set the Catalog cache class to :active_record if asynchronous storeconfigs is enabled" do
            Puppet::Resource::Catalog.expects(:cache_class=).with(:active_record).never
            Puppet.settings.expects(:value).with(:async_storeconfigs).returns true
            Puppet.settings[:storeconfigs] = true
        end

        it "should set the Facts cache class to :active_record" do
            Puppet::Node::Facts.expects(:cache_class=).with(:active_record)
            Puppet.settings[:storeconfigs] = true
        end

        it "should set the Node cache class to :active_record" do
            Puppet::Node.expects(:cache_class=).with(:active_record)
            Puppet.settings[:storeconfigs] = true
        end

        it "should fail if rails is not available" do
            Puppet.features.stubs(:rails?).returns false
            lambda { Puppet.settings[:storeconfigs] = true }.should raise_error
        end
    end

    describe "when enabling asynchronous storeconfigs" do
        before do
            Puppet::Resource::Catalog.stubs(:cache_class=)
            Puppet::Node::Facts.stubs(:cache_class=)
            Puppet::Node.stubs(:cache_class=)
            Puppet.features.stubs(:rails?).returns true
        end

        it "should set storeconfigs to true" do
            Puppet.settings[:async_storeconfigs] = true
            Puppet.settings[:storeconfigs].should be_true
        end

        it "should set the Catalog cache class to :queue" do
            Puppet::Resource::Catalog.expects(:cache_class=).with(:queue)
            Puppet.settings[:async_storeconfigs] = true
        end

        it "should set the Facts cache class to :active_record" do
            Puppet::Node::Facts.expects(:cache_class=).with(:active_record)
            Puppet.settings[:storeconfigs] = true
        end

        it "should set the Node cache class to :active_record" do
            Puppet::Node.expects(:cache_class=).with(:active_record)
            Puppet.settings[:storeconfigs] = true
        end
    end

    describe "when enabling thin storeconfigs" do
        before do
            Puppet::Resource::Catalog.stubs(:cache_class=)
            Puppet::Node::Facts.stubs(:cache_class=)
            Puppet::Node.stubs(:cache_class=)
            Puppet.features.stubs(:rails?).returns true
        end

        it "should set storeconfigs to true" do
            Puppet.settings[:thin_storeconfigs] = true
            Puppet.settings[:storeconfigs].should be_true
        end
    end

    it "should have a setting for determining the configuration version and should default to an empty string" do
        Puppet.settings[:config_version].should == ""
    end
    
    describe "when enabling reports" do
        it "should use the default server value when report server is unspecified" do
            Puppet.settings[:server] = "server"
            Puppet.settings[:report_server].should == "server"
        end
        
        it "should use the default masterport value when report port is unspecified" do
            Puppet.settings[:masterport] = "1234"
            Puppet.settings[:report_port].should == "1234"
        end

        it "should set report_server when reportserver is set" do
            Puppet.settings[:reportserver] = "reportserver"
            Puppet.settings[:report_server].should == "reportserver"
        end
        
        it "should use report_port when set" do
            Puppet.settings[:masterport] = "1234"
            Puppet.settings[:report_port] = "5678"
            Puppet.settings[:report_port].should == "5678"
        end
        
        it "should prefer report_server over reportserver" do
            Puppet.settings[:reportserver] = "reportserver"
            Puppet.settings[:report_server] = "report_server"
            Puppet.settings[:report_server].should == "report_server"
        end
    end
end
