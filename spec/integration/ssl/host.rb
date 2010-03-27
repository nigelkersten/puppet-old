#!/usr/bin/env ruby
#
#  Created by Luke Kanies on 2008-4-17.
#  Copyright (c) 2008. All rights reserved.

require File.dirname(__FILE__) + '/../../spec_helper'

require 'puppet/ssl/host'
require 'tempfile'

describe Puppet::SSL::Host do
    before do
        # Get a safe temporary file
        file = Tempfile.new("host_integration_testing")
        @dir = file.path
        file.delete

        Puppet.settings[:confdir] = @dir
        Puppet.settings[:vardir] = @dir

        Puppet::SSL::Host.ca_location = :local

        @host = Puppet::SSL::Host.new("luke.madstop.com")
        @ca = Puppet::SSL::CertificateAuthority.new
    end

    after {
        Puppet::SSL::Host.ca_location = :none

        system("rm -rf %s" % @dir)
        Puppet.settings.clear
        Puppet::Util::Cacher.expire
    }

    it "should be considered a CA host if its name is equal to 'ca'" do
        Puppet::SSL::Host.new(Puppet::SSL::CA_NAME).should be_ca
    end

    describe "when managing its key" do
        it "should be able to generate and save a key" do
            @host.generate_key
        end

        it "should save the key such that the Indirector can find it" do
            @host.generate_key

            Puppet::SSL::Key.find(@host.name).content.to_s.should == @host.key.to_s
        end

        it "should save the private key into the :privatekeydir" do
            @host.generate_key
            File.read(File.join(Puppet.settings[:privatekeydir], "luke.madstop.com.pem")).should == @host.key.to_s
        end
    end

    describe "when managing its certificate request" do
        it "should be able to generate and save a certificate request" do
            @host.generate_certificate_request
        end

        it "should save the certificate request such that the Indirector can find it" do
            @host.generate_certificate_request

            Puppet::SSL::CertificateRequest.find(@host.name).content.to_s.should == @host.certificate_request.to_s
        end

        it "should save the private certificate request into the :privatekeydir" do
            @host.generate_certificate_request
            File.read(File.join(Puppet.settings[:requestdir], "luke.madstop.com.pem")).should == @host.certificate_request.to_s
        end
    end

    describe "when the CA host" do
        it "should never store its key in the :privatekeydir" do
            Puppet.settings.use(:main, :ssl, :ca)
            @ca = Puppet::SSL::Host.new(Puppet::SSL::Host.ca_name)
            @ca.generate_key

            FileTest.should_not be_exist(File.join(Puppet[:privatekeydir], "ca.pem"))
        end
    end

    it "should pass the verification of its own SSL store" do
        @host.generate
        @ca = Puppet::SSL::CertificateAuthority.new
        @ca.sign(@host.name)

        @host.ssl_store.verify(@host.certificate.content).should be_true
    end
end
