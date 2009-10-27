#!/usr/bin/env ruby
#
#  Created by Luke Kanies on 2007-4-8.
#  Copyright (c) 2008. All rights reserved.

require File.dirname(__FILE__) + '/../../spec_helper'

describe Puppet::Resource::Catalog do
    describe "when pson is available" do
        confine "PSON library is missing" => Puppet.features.pson?
        it "should support pson" do
            Puppet::Resource::Catalog.supported_formats.should be_include(:pson)
        end
    end

    describe "when using the indirector" do
        after { Puppet::Util::Cacher.expire }
        before do
            # This is so the tests work w/out networking.
            Facter.stubs(:to_hash).returns({"hostname" => "foo.domain.com"})
            Facter.stubs(:value).returns("eh")
        end


        it "should be able to delegate to the :yaml terminus" do
            Puppet::Resource::Catalog.indirection.stubs(:terminus_class).returns :yaml

            # Load now, before we stub the exists? method.
            terminus = Puppet::Resource::Catalog.indirection.terminus(:yaml)
            terminus.expects(:path).with("me").returns "/my/yaml/file"

            FileTest.expects(:exist?).with("/my/yaml/file").returns false
            Puppet::Resource::Catalog.find("me").should be_nil
        end

        it "should be able to delegate to the :compiler terminus" do
            Puppet::Resource::Catalog.indirection.stubs(:terminus_class).returns :compiler

            # Load now, before we stub the exists? method.
            compiler = Puppet::Resource::Catalog.indirection.terminus(:compiler)

            node = mock 'node'
            node.stub_everything

            Puppet::Node.expects(:find).returns(node)
            compiler.expects(:compile).with(node).returns nil

            Puppet::Resource::Catalog.find("me").should be_nil
        end

        it "should pass provided node information directly to the terminus" do
            terminus = mock 'terminus'

            Puppet::Resource::Catalog.indirection.stubs(:terminus).returns terminus

            node = mock 'node'
            terminus.expects(:find).with { |request| request.options[:use_node] == node }
            Puppet::Resource::Catalog.find("me", :use_node => node)
        end
    end
end
