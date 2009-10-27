#!/usr/bin/env ruby

require File.dirname(__FILE__) + '/../../spec_helper'

require 'puppet_spec/files'

require 'puppet/application/puppet'

describe "Puppet" do
    include PuppetSpec::Files

    describe "when applying provided catalogs" do
        confine "PSON library is missing; cannot test applying catalogs" => Puppet.features.pson?
        it "should be able to apply catalogs provided in a file in pson" do
            file_to_create = tmpfile("pson_catalog")
            catalog = Puppet::Resource::Catalog.new
            resource = Puppet::Resource.new(:file, file_to_create, :content => "my stuff")
            catalog.add_resource resource

            manifest = tmpfile("manifest")

            File.open(manifest, "w") { |f| f.print catalog.to_pson }

            puppet = Puppet::Application[:puppet]
            puppet.options[:catalog] = manifest

            puppet.apply

            File.should be_exist(file_to_create)
            File.read(file_to_create).should == "my stuff"
        end
    end
end
