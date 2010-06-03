#!/usr/bin/env ruby

require File.dirname(__FILE__) + '/../../../../spec_helper'
require 'puppet/network/http/rack' if Puppet.features.rack?
require 'puppet/network/http/rack/rest'

describe "Puppet::Network::HTTP::RackREST" do
    confine "Rack is not available" => Puppet.features.rack?

    it "should include the Puppet::Network::HTTP::Handler module" do
        Puppet::Network::HTTP::RackREST.ancestors.should be_include(Puppet::Network::HTTP::Handler)
    end

    describe "when initializing" do
        it "should call the Handler's initialization hook with its provided arguments" do
            Puppet::Network::HTTP::RackREST.any_instance.expects(:initialize_for_puppet).with(:server => "my", :handler => "arguments")
            Puppet::Network::HTTP::RackREST.new(:server => "my", :handler => "arguments")
        end
    end

    describe "when serving a request" do
        before :all do
            @model_class = stub('indirected model class')
            Puppet::Indirector::Indirection.stubs(:model).with(:foo).returns(@model_class)
            @handler = Puppet::Network::HTTP::RackREST.new(:handler => :foo)
        end

        before :each do
            @response = Rack::Response.new()
        end

        def mk_req(uri, opts = {})
            env = Rack::MockRequest.env_for(uri, opts)
            Rack::Request.new(env)
        end

        describe "and using the HTTP Handler interface" do
            it "should return the HTTP_ACCEPT parameter as the accept header" do
                req = mk_req('/', 'HTTP_ACCEPT' => 'myaccept')
                @handler.accept_header(req).should == "myaccept"
            end

            it "should return the CONTENT_TYPE parameter as the content type header" do
                req = mk_req('/', 'CONTENT_TYPE' => 'mycontent')
                @handler.content_type_header(req).should == "mycontent"
            end

            it "should use the REQUEST_METHOD as the http method" do
                req = mk_req('/', :method => 'mymethod')
                @handler.http_method(req).should == "mymethod"
            end

            it "should return the request path as the path" do
                req = mk_req('/foo/bar')
                @handler.path(req).should == "/foo/bar"
            end

            it "should return the request body as the body" do
                req = mk_req('/foo/bar', :input => 'mybody')
                @handler.body(req).should == "mybody"
            end

            it "should set the response's content-type header when setting the content type" do
                @header = mock 'header'
                @response.expects(:header).returns @header
                @header.expects(:[]=).with('Content-Type', "mytype")

                @handler.set_content_type(@response, "mytype")
            end

            it "should set the status and write the body when setting the response for a request" do
                @response.expects(:status=).with(400)
                @response.expects(:write).with("mybody")

                @handler.set_response(@response, "mybody", 400)
            end

            describe "when result is a File" do
                before :each do
                    stat = stub 'stat', :size => 100
                    @file = stub 'file', :stat => stat, :path => "/tmp/path"
                    @file.stubs(:is_a?).with(File).returns(true)
                end

                it "should set the Content-Length header" do
                    @response.expects(:[]=).with("Content-Length", 100)

                    @handler.set_response(@response, @file, 200)
                end

                it "should return a RackFile adapter as body" do
                    @response.expects(:body=).with { |val| val.is_a?(Puppet::Network::HTTP::RackREST::RackFile) }

                    @handler.set_response(@response, @file, 200)
                end
            end
        end

        describe "and determining the request parameters" do
            it "should include the HTTP request parameters, with the keys as symbols" do
                req = mk_req('/?foo=baz&bar=xyzzy')
                result = @handler.params(req)
                result[:foo].should == "baz"
                result[:bar].should == "xyzzy"
            end

            it "should CGI-decode the HTTP parameters" do
                encoding = CGI.escape("foo bar")
                req = mk_req("/?foo=#{encoding}")
                result = @handler.params(req)
                result[:foo].should == "foo bar"
            end

            it "should convert the string 'true' to the boolean" do
                req = mk_req("/?foo=true")
                result = @handler.params(req)
                result[:foo].should be_true
            end

            it "should convert the string 'false' to the boolean" do
                req = mk_req("/?foo=false")
                result = @handler.params(req)
                result[:foo].should be_false
            end

            it "should convert integer arguments to Integers" do
                req = mk_req("/?foo=15")
                result = @handler.params(req)
                result[:foo].should == 15
            end

            it "should convert floating point arguments to Floats" do
                req = mk_req("/?foo=1.5")
                result = @handler.params(req)
                result[:foo].should == 1.5
            end

            it "should YAML-load and CGI-decode values that are YAML-encoded" do
                escaping = CGI.escape(YAML.dump(%w{one two}))
                req = mk_req("/?foo=#{escaping}")
                result = @handler.params(req)
                result[:foo].should == %w{one two}
            end

            it "should not allow the client to set the node via the query string" do
                req = mk_req("/?node=foo")
                @handler.params(req)[:node].should be_nil
            end

            it "should not allow the client to set the IP address via the query string" do
                req = mk_req("/?ip=foo")
                @handler.params(req)[:ip].should be_nil
            end

            it "should pass the client's ip address to model find" do
                req = mk_req("/", 'REMOTE_ADDR' => 'ipaddress')
                @handler.params(req)[:ip].should == "ipaddress"
            end

            it "should set 'authenticated' to false if no certificate is present" do
                req = mk_req('/')
                @handler.params(req)[:authenticated].should be_false
            end
        end

        describe "with pre-validated certificates" do

            it "should use the :ssl_client_header to determine the parameter when looking for the certificate" do
                Puppet.settings.stubs(:value).returns "eh"
                Puppet.settings.expects(:value).with(:ssl_client_header).returns "myheader"
                req = mk_req('/', "myheader" => "/CN=host.domain.com")
                @handler.params(req)
            end

            it "should retrieve the hostname by matching the certificate parameter" do
                Puppet.settings.stubs(:value).returns "eh"
                Puppet.settings.expects(:value).with(:ssl_client_header).returns "myheader"
                req = mk_req('/', "myheader" => "/CN=host.domain.com")
                @handler.params(req)[:node].should == "host.domain.com"
            end

            it "should use the :ssl_client_header to determine the parameter for checking whether the host certificate is valid" do
                Puppet.settings.stubs(:value).with(:ssl_client_header).returns "certheader"
                Puppet.settings.expects(:value).with(:ssl_client_verify_header).returns "myheader"
                req = mk_req('/', "myheader" => "SUCCESS", "certheader" => "/CN=host.domain.com")
                @handler.params(req)
            end

            it "should consider the host authenticated if the validity parameter contains 'SUCCESS'" do
                Puppet.settings.stubs(:value).with(:ssl_client_header).returns "certheader"
                Puppet.settings.stubs(:value).with(:ssl_client_verify_header).returns "myheader"
                req = mk_req('/', "myheader" => "SUCCESS", "certheader" => "/CN=host.domain.com")
                @handler.params(req)[:authenticated].should be_true
            end

            it "should consider the host unauthenticated if the validity parameter does not contain 'SUCCESS'" do
                Puppet.settings.stubs(:value).with(:ssl_client_header).returns "certheader"
                Puppet.settings.stubs(:value).with(:ssl_client_verify_header).returns "myheader"
                req = mk_req('/', "myheader" => "whatever", "certheader" => "/CN=host.domain.com")
                @handler.params(req)[:authenticated].should be_false
            end

            it "should consider the host unauthenticated if no certificate information is present" do
                Puppet.settings.stubs(:value).with(:ssl_client_header).returns "certheader"
                Puppet.settings.stubs(:value).with(:ssl_client_verify_header).returns "myheader"
                req = mk_req('/', "myheader" => nil, "certheader" => "/CN=host.domain.com")
                @handler.params(req)[:authenticated].should be_false
            end

            it "should resolve the node name with an ip address look-up if no certificate is present" do
                Puppet.settings.stubs(:value).returns "eh"
                Puppet.settings.expects(:value).with(:ssl_client_header).returns "myheader"
                req = mk_req('/', "myheader" => nil)
                @handler.expects(:resolve_node).returns("host.domain.com")
                @handler.params(req)[:node].should == "host.domain.com"
            end
        end
    end
end

describe Puppet::Network::HTTP::RackREST::RackFile do
    before(:each) do
        stat = stub 'stat', :size => 100
        @file = stub 'file', :stat => stat, :path => "/tmp/path"
        @rackfile = Puppet::Network::HTTP::RackREST::RackFile.new(@file)
    end

    it "should have an each method" do
        @rackfile.should be_respond_to(:each)
    end

    it "should yield file chunks by chunks" do
        @file.expects(:read).times(3).with(8192).returns("1", "2", nil)
        i = 1
        @rackfile.each do |chunk|
            chunk.to_i.should == i
            i += 1
        end
    end

    it "should have a close method" do
        @rackfile.should be_respond_to(:close)
    end

    it "should delegate close to File close" do
        @file.expects(:close)
        @rackfile.close
    end
end