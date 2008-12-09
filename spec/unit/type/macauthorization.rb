#!/usr/bin/env ruby

require File.dirname(__FILE__) + '/../../spec_helper'

macauth_type = Puppet::Type.type(:macauthorization)

describe Puppet.type(:macauthorization), "when checking macauthorization objects" do
    
    before do
        authplist = {}
        authplist["rules"] = { "foorule" => "foo" }
        authplist["rights"] = { "fooright" => "foo" }
        provider_class = macauth_type.provider(macauth_type.providers[0])
        Plist.stubs(:parse_xml).with("/etc/authorization").returns(authplist)
        macauth_type.stubs(:defaultprovider).returns provider_class
    end
    
    after do
        macauth_type.clear
    end
        
    
    describe "when validating attributes" do
    
        parameters = [:name,]
        properties = [:auth_type, :allow_root, :authenticate_user, :auth_class, 
                      :comment, :group, :k_of_n, :mechanisms, :rule, 
                      :session_owner, :shared, :timeout, :tries]
    
        parameters.each do |parameter|
            it "should have a %s parameter" % parameter do
                macauth_type.attrclass(parameter).ancestors.should be_include(Puppet::Parameter)
            end
    
            it "should have documentation for its %s parameter" % parameter do
                macauth_type.attrclass(parameter).doc.should be_instance_of(String)
            end
        end
    
        properties.each do |property|
            it "should have a %s property" % property do
                macauth_type.attrclass(property).ancestors.should be_include(Puppet::Property)
            end
    
            it "should have documentation for its %s property" % property do
                macauth_type.attrclass(property).doc.should be_instance_of(String)
            end
        end
    
    end
    
    describe "when validating properties" do
        
        it "should have a default provider inheriting from Puppet::Provider" do
            macauth_type.defaultprovider.ancestors.should be_include(Puppet::Provider)
        end
    
        it "should be able to create an instance" do
            lambda {
                macauth_type.create(:name => 'foo')
            }.should_not raise_error
        end
            
        it "should support :present as a value to :ensure" do
            lambda {
                macauth_type.create(:name => "foo", :ensure => :present)
            }.should_not raise_error
        end
            
        it "should support :absent as a value to :ensure" do
            lambda {
                macauth_type.create(:name => "foo", :ensure => :absent)
            }.should_not raise_error
        end
    
    end

end