#!/usr/bin/env ruby

require File.dirname(__FILE__) + '/../../spec_helper'

require 'puppet/network/rights'

describe Puppet::Network::Rights do
    before do
        @right = Puppet::Network::Rights.new
    end

    [:allow, :deny, :restrict_method, :restrict_environment, :restrict_authenticated].each do |m|
        it "should have a #{m} method" do
            @right.should respond_to(m)
        end

        describe "when using #{m}" do
            it "should delegate to the correct acl" do
                acl = stub 'acl'
                @right.stubs(:[]).returns(acl)

                acl.expects(m).with("me")

                @right.send(m, 'thisacl', "me")
            end
        end
    end

    it "should throw an error if type can't be determined" do
        lambda { @right.newright("name") }.should raise_error
    end

    describe "when creating new namespace ACLs" do

        it "should throw an error if the ACL already exists" do
            @right.newright("[name]")

            lambda { @right.newright("[name]") }.should raise_error
        end

        it "should create a new ACL with the correct name" do
            @right.newright("[name]")

            @right["name"].key.should == :name
        end

        it "should create an ACL of type Puppet::Network::AuthStore" do
            @right.newright("[name]")

            @right["name"].should be_a_kind_of(Puppet::Network::AuthStore)
        end
    end

    describe "when creating new path ACLs" do
        it "should not throw an error if the ACL already exists" do
            @right.newright("/name")

            lambda { @right.newright("/name")}.should_not raise_error
        end

        it "should throw an error if the acl uri path is not absolute" do
            lambda { @right.newright("name")}.should raise_error
        end

        it "should create a new ACL with the correct path" do
            @right.newright("/name")

            @right["/name"].should_not be_nil
        end

        it "should create an ACL of type Puppet::Network::AuthStore" do
            @right.newright("/name")

            @right["/name"].should be_a_kind_of(Puppet::Network::AuthStore)
        end
    end

    describe "when creating new regex ACLs" do
        it "should not throw an error if the ACL already exists" do
            @right.newright("~ .rb$")

            lambda { @right.newright("~ .rb$")}.should_not raise_error
        end

        it "should create a new ACL with the correct regex" do
            @right.newright("~ .rb$")

            @right.include?(".rb$").should_not be_nil
        end

        it "should be able to lookup the regex" do
            @right.newright("~ .rb$")

            @right[".rb$"].should_not be_nil
        end

        it "should be able to lookup the regex by its full name" do
            @right.newright("~ .rb$")

            @right["~ .rb$"].should_not be_nil
        end

        it "should create an ACL of type Puppet::Network::AuthStore" do
            @right.newright("~ .rb$").should be_a_kind_of(Puppet::Network::AuthStore)
        end
    end

    describe "when checking ACLs existence" do
        it "should return false if there are no matching rights" do
            @right.include?("name").should be_false
        end

        it "should return true if a namespace rights exist" do
            @right.newright("[name]")

            @right.include?("name").should be_true
        end

        it "should return false if no matching namespace rights exist" do
            @right.newright("[name]")

            @right.include?("notname").should be_false
        end

        it "should return true if a path right exists" do
            @right.newright("/name")

            @right.include?("/name").should be_true
        end

        it "should return false if no matching path rights exist" do
            @right.newright("/name")

            @right.include?("/differentname").should be_false
        end

        it "should return true if a regex right exists" do
            @right.newright("~ .rb$")

            @right.include?(".rb$").should be_true
        end

        it "should return false if no matching path rights exist" do
            @right.newright("~ .rb$")

            @right.include?(".pp$").should be_false
        end
    end

    describe "when checking if right is allowed" do
        before :each do
            @right.stubs(:right).returns(nil)

            @pathacl = stub 'pathacl', :acl_type => :regex, :"<=>" => 1, :line => 0, :file => 'dummy'
            Puppet::Network::Rights::Right.stubs(:new).returns(@pathacl)
        end

        it "should delegate to fail_on_deny" do
            @right.expects(:fail_on_deny).with("namespace", :node => "host.domain.com", :ip => "127.0.0.1")

            @right.allowed?("namespace", "host.domain.com", "127.0.0.1")
        end

        it "should return true if fail_on_deny doesn't fail" do
            @right.stubs(:fail_on_deny)
            @right.allowed?("namespace", :args).should be_true
        end

        it "should return false if fail_on_deny raises an AuthorizationError" do
            @right.stubs(:fail_on_deny).raises(Puppet::Network::AuthorizationError.new("forbidden"))
            @right.allowed?("namespace", :args1, :args2).should be_false
        end

        it "should first check namespace rights" do
            acl = stub 'acl', :acl_type => :name, :key => :namespace
            Puppet::Network::Rights::Right.stubs(:new).returns(acl)

            @right.newright("[namespace]")
            acl.expects(:match?).returns(true)
            acl.expects(:allowed?).with { |node,ip,h| node == "node" and ip == "ip" }.returns(true)

            @right.fail_on_deny("namespace", { :node => "node", :ip => "ip" } )
        end

        it "should then check for path rights if no namespace match" do
            acl = stub 'nmacl', :acl_type => :name, :key => :namespace, :"<=>" => -1, :line => 0, :file => 'dummy'
            acl.stubs(:match?).returns(false)
            Puppet::Network::Rights::Right.stubs(:new).with("[namespace]").returns(acl)

            @right.newright("[namespace]")
            @right.newright("/path/to/there", 0, nil)

            @pathacl.stubs(:match?).returns(true)

            acl.expects(:allowed?).never
            @pathacl.expects(:allowed?).returns(true)

            @right.fail_on_deny("/path/to/there", {})
        end

        it "should pass the match? return to allowed?" do
            @right.newright("/path/to/there")

            @pathacl.expects(:match?).returns(:match)
            @pathacl.expects(:allowed?).with { |node,ip,h| h[:match] == :match }.returns(true)

            @right.fail_on_deny("/path/to/there", {})
        end

        describe "with namespace acls" do
            it "should raise an error if this namespace right doesn't exist" do
                lambda{ @right.fail_on_deny("namespace") }.should raise_error
            end
        end

        describe "with path acls" do
            before :each do
                @long_acl = stub 'longpathacl', :name => "/path/to/there", :acl_type => :regex, :line => 0, :file => 'dummy'
                Puppet::Network::Rights::Right.stubs(:new).with("/path/to/there", 0, nil).returns(@long_acl)

                @short_acl = stub 'shortpathacl', :name => "/path/to", :acl_type => :regex, :line => 0, :file => 'dummy'
                Puppet::Network::Rights::Right.stubs(:new).with("/path/to", 0, nil).returns(@short_acl)

                @long_acl.stubs(:"<=>").with(@short_acl).returns(0)
                @short_acl.stubs(:"<=>").with(@long_acl).returns(0)
            end

            it "should select the first match" do
                @right.newright("/path/to/there", 0)
                @right.newright("/path/to", 0)

                @long_acl.stubs(:match?).returns(true)
                @short_acl.stubs(:match?).returns(true)

                @long_acl.expects(:allowed?).returns(true)
                @short_acl.expects(:allowed?).never

                @right.fail_on_deny("/path/to/there/and/there", {})
            end

            it "should select the first match that doesn't return :dunno" do
                @right.newright("/path/to/there", 0, nil)
                @right.newright("/path/to", 0, nil)

                @long_acl.stubs(:match?).returns(true)
                @short_acl.stubs(:match?).returns(true)

                @long_acl.expects(:allowed?).returns(:dunno)
                @short_acl.expects(:allowed?).returns(true)

                @right.fail_on_deny("/path/to/there/and/there", {})
            end

            it "should not select an ACL that doesn't match" do
                @right.newright("/path/to/there", 0)
                @right.newright("/path/to", 0)

                @long_acl.stubs(:match?).returns(false)
                @short_acl.stubs(:match?).returns(true)

                @long_acl.expects(:allowed?).never
                @short_acl.expects(:allowed?).returns(true)

                @right.fail_on_deny("/path/to/there/and/there", {})
            end

            it "should not raise an AuthorizationError if allowed" do
                @right.newright("/path/to/there", 0)

                @long_acl.stubs(:match?).returns(true)
                @long_acl.stubs(:allowed?).returns(true)

                lambda { @right.fail_on_deny("/path/to/there/and/there", {}) }.should_not raise_error(Puppet::Network::AuthorizationError)
            end

            it "should raise an AuthorizationError if the match is denied" do
                @right.newright("/path/to/there", 0, nil)

                @long_acl.stubs(:match?).returns(true)
                @long_acl.stubs(:allowed?).returns(false)

                lambda{ @right.fail_on_deny("/path/to/there", {}) }.should raise_error(Puppet::Network::AuthorizationError)
            end

            it "should raise an AuthorizationError if no path match" do
                lambda { @right.fail_on_deny("/nomatch", {}) }.should raise_error(Puppet::Network::AuthorizationError)
            end
        end

        describe "with regex acls" do
            before :each do
                @regex_acl1 = stub 'regex_acl1', :name => "/files/(.*)/myfile", :acl_type => :regex, :line => 0, :file => 'dummy'
                Puppet::Network::Rights::Right.stubs(:new).with("~ /files/(.*)/myfile", 0, nil).returns(@regex_acl1)

                @regex_acl2 = stub 'regex_acl2', :name => "/files/(.*)/myfile/", :acl_type => :regex, :line => 0, :file => 'dummy'
                Puppet::Network::Rights::Right.stubs(:new).with("~ /files/(.*)/myfile/", 0, nil).returns(@regex_acl2)

                @regex_acl1.stubs(:"<=>").with(@regex_acl2).returns(0)
                @regex_acl2.stubs(:"<=>").with(@regex_acl1).returns(0)
            end

            it "should select the first match" do
                @right.newright("~ /files/(.*)/myfile", 0)
                @right.newright("~ /files/(.*)/myfile/", 0)

                @regex_acl1.stubs(:match?).returns(true)
                @regex_acl2.stubs(:match?).returns(true)

                @regex_acl1.expects(:allowed?).returns(true)
                @regex_acl2.expects(:allowed?).never

                @right.fail_on_deny("/files/repository/myfile/other", {})
            end

            it "should select the first match that doesn't return :dunno" do
                @right.newright("~ /files/(.*)/myfile", 0)
                @right.newright("~ /files/(.*)/myfile/", 0)

                @regex_acl1.stubs(:match?).returns(true)
                @regex_acl2.stubs(:match?).returns(true)

                @regex_acl1.expects(:allowed?).returns(:dunno)
                @regex_acl2.expects(:allowed?).returns(true)

                @right.fail_on_deny("/files/repository/myfile/other", {})
            end

            it "should not select an ACL that doesn't match" do
                @right.newright("~ /files/(.*)/myfile", 0)
                @right.newright("~ /files/(.*)/myfile/", 0)

                @regex_acl1.stubs(:match?).returns(false)
                @regex_acl2.stubs(:match?).returns(true)

                @regex_acl1.expects(:allowed?).never
                @regex_acl2.expects(:allowed?).returns(true)

                @right.fail_on_deny("/files/repository/myfile/other", {})
            end

            it "should not raise an AuthorizationError if allowed" do
                @right.newright("~ /files/(.*)/myfile", 0)

                @regex_acl1.stubs(:match?).returns(true)
                @regex_acl1.stubs(:allowed?).returns(true)

                lambda { @right.fail_on_deny("/files/repository/myfile/other", {}) }.should_not raise_error(Puppet::Network::AuthorizationError)
            end

            it "should raise an error if no regex acl match" do
                lambda{ @right.fail_on_deny("/path", {}) }.should raise_error(Puppet::Network::AuthorizationError)
            end

            it "should raise an AuthorizedError on deny" do
                lambda { @right.fail_on_deny("/path", {}) }.should raise_error(Puppet::Network::AuthorizationError)
            end

        end
    end

    describe Puppet::Network::Rights::Right do
        before :each do
            @acl = Puppet::Network::Rights::Right.new("/path",0, nil)
        end

        describe "with path" do
            it "should say it's a regex ACL" do
                @acl.acl_type.should == :regex
            end

            it "should match up to its path length" do
                @acl.match?("/path/that/works").should_not be_nil
            end

            it "should match up to its path length" do
                @acl.match?("/paththatalsoworks").should_not be_nil
            end

            it "should return nil if no match" do
                @acl.match?("/notpath").should be_nil
            end
        end

        describe "with regex" do
            before :each do
                @acl = Puppet::Network::Rights::Right.new("~ .rb$",0, nil)
            end

            it "should say it's a regex ACL" do
                @acl.acl_type.should == :regex
            end

            it "should match as a regex" do
                @acl.match?("this should work.rb").should_not be_nil
            end

            it "should return nil if no match" do
                @acl.match?("do not match").should be_nil
            end
        end

        it "should allow all rest methods by default" do
            @acl.methods.should == Puppet::Network::Rights::Right::ALL
        end

        it "should allow only authenticated request by default" do
            @acl.authentication.should be_true
        end

        it "should allow modification of the methods filters" do
            @acl.restrict_method(:save)

            @acl.methods.should == [:save]
        end

        it "should stack methods filters" do
            @acl.restrict_method(:save)
            @acl.restrict_method(:destroy)

            @acl.methods.should == [:save, :destroy]
        end

        it "should raise an error if the method is already filtered" do
            @acl.restrict_method(:save)

            lambda { @acl.restrict_method(:save) }.should raise_error
        end

        it "should allow setting an environment filters" do
            Puppet::Node::Environment.stubs(:new).with(:environment).returns(:env)

            @acl.restrict_environment(:environment)

            @acl.environment.should == [:env]
        end

        ["on", "yes", "true", true].each do |auth|
            it "should allow filtering on authenticated requests with '#{auth}'" do
                @acl.restrict_authenticated(auth)

                @acl.authentication.should be_true
            end
        end

        ["off", "no", "false", false].each do |auth|
            it "should allow filtering on unauthenticated requests with '#{auth}'" do
                @acl.restrict_authenticated(auth)

                @acl.authentication.should be_false
            end
        end

        ["all", "any", :all, :any].each do |auth|
            it "should not use request authenticated state filtering with '#{auth}'" do
                @acl.restrict_authenticated(auth)

                @acl.authentication.should be_nil
            end
        end

        describe "when checking right authorization" do
            it "should return :dunno if this right is not restricted to the given method" do
                @acl.restrict_method(:destroy)

                @acl.allowed?("me","127.0.0.1", { :method => :save } ).should == :dunno
            end

            it "should return allow/deny if this right is restricted to the given method" do
                @acl.restrict_method(:save)
                @acl.allow("127.0.0.1")

                @acl.allowed?("me","127.0.0.1", { :method => :save }).should be_true
            end

            it "should return :dunno if this right is not restricted to the given environment" do
                Puppet::Node::Environment.stubs(:new).returns(:production)

                @acl.restrict_environment(:production)

                @acl.allowed?("me","127.0.0.1", { :method => :save, :environment => :development }).should == :dunno
            end

            it "should return :dunno if this right is not restricted to the given request authentication state" do
                @acl.restrict_authenticated(true)

                @acl.allowed?("me","127.0.0.1", { :method => :save, :authenticated => false }).should == :dunno
            end

            it "should return allow/deny if this right is restricted to the given request authentication state" do
                @acl.restrict_authenticated(false)
                @acl.allow("127.0.0.1")

                @acl.allowed?("me","127.0.0.1", { :authenticated => false }).should be_true
            end

            it "should interpolate allow/deny patterns with the given match" do
                @acl.expects(:interpolate).with(:match)

                @acl.allowed?("me","127.0.0.1", { :method => :save, :match => :match, :authenticated => true })
            end

            it "should reset interpolation after the match" do
                @acl.expects(:reset_interpolation)

                @acl.allowed?("me","127.0.0.1", { :method => :save, :match => :match, :authenticated => true })
            end

            # mocha doesn't allow testing super...
            # it "should delegate to the AuthStore for the result" do
            #     @acl.method(:save)
            #
            #     @acl.expects(:allowed?).with("me","127.0.0.1")
            #
            #     @acl.allowed?("me","127.0.0.1", :save)
            # end
        end
    end

end
