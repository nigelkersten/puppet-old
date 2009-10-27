#!/usr/bin/env ruby

require File.dirname(__FILE__) + '/../../spec_helper'

describe Puppet::Resource::Catalog, "when compiling" do
    it "should be an Expirer" do
        Puppet::Resource::Catalog.ancestors.should be_include(Puppet::Util::Cacher::Expirer)
    end

    it "should always be expired if it's not applying" do
        @catalog = Puppet::Resource::Catalog.new("host")
        @catalog.expects(:applying?).returns false
        @catalog.should be_dependent_data_expired(Time.now)
    end

    it "should not be expired if it's applying and the timestamp is late enough" do
        @catalog = Puppet::Resource::Catalog.new("host")
        @catalog.expire
        @catalog.expects(:applying?).returns true
        @catalog.should_not be_dependent_data_expired(Time.now)
    end

    it "should be able to write its list of classes to the class file" do
        @catalog = Puppet::Resource::Catalog.new("host")

        @catalog.add_class "foo", "bar"

        Puppet.settings.expects(:value).with(:classfile).returns "/class/file"

        fh = mock 'filehandle'
        File.expects(:open).with("/class/file", "w").yields fh

        fh.expects(:puts).with "foo\nbar"

        @catalog.write_class_file
    end

    it "should have a client_version attribute" do
        @catalog = Puppet::Resource::Catalog.new("host")
        @catalog.client_version = 5
        @catalog.client_version.should == 5
    end

    it "should have a server_version attribute" do
        @catalog = Puppet::Resource::Catalog.new("host")
        @catalog.server_version = 5
        @catalog.server_version.should == 5
    end

    describe "when compiling" do
        it "should accept tags" do
            config = Puppet::Resource::Catalog.new("mynode")
            config.tag("one")
            config.tags.should == %w{one}
        end

        it "should accept multiple tags at once" do
            config = Puppet::Resource::Catalog.new("mynode")
            config.tag("one", "two")
            config.tags.should == %w{one two}
        end

        it "should convert all tags to strings" do
            config = Puppet::Resource::Catalog.new("mynode")
            config.tag("one", :two)
            config.tags.should == %w{one two}
        end

        it "should tag with both the qualified name and the split name" do
            config = Puppet::Resource::Catalog.new("mynode")
            config.tag("one::two")
            config.tags.include?("one").should be_true
            config.tags.include?("one::two").should be_true
        end

        it "should accept classes" do
            config = Puppet::Resource::Catalog.new("mynode")
            config.add_class("one")
            config.classes.should == %w{one}
            config.add_class("two", "three")
            config.classes.should == %w{one two three}
        end

        it "should tag itself with passed class names" do
            config = Puppet::Resource::Catalog.new("mynode")
            config.add_class("one")
            config.tags.should == %w{one}
        end
    end

    describe "when extracting" do
        it "should return extraction result as the method result" do
            config = Puppet::Resource::Catalog.new("mynode")
            config.expects(:extraction_format).returns(:whatever)
            config.expects(:extract_to_whatever).returns(:result)
            config.extract.should == :result
        end
    end

    describe "when extracting transobjects" do

        def mkscope
            @parser = Puppet::Parser::Parser.new :Code => ""
            @node = Puppet::Node.new("mynode")
            @compiler = Puppet::Parser::Compiler.new(@node, @parser)

            # XXX This is ridiculous.
            @compiler.send(:evaluate_main)
            @scope = @compiler.topscope
        end

        def mkresource(type, name)
            Puppet::Parser::Resource.new(:type => type, :title => name, :source => @source, :scope => @scope)
        end

        it "should always create a TransBucket for the 'main' class" do
            config = Puppet::Resource::Catalog.new("mynode")

            @scope = mkscope
            @source = mock 'source'

            main = mkresource("class", :main)
            config.add_vertex(main)

            bucket = stub 'bucket', :file= => nil, :line= => nil, :classes= => nil
            bucket.expects(:type=).with("Class")
            bucket.expects(:name=).with(:main)
            main.stubs(:builtin?).returns(false)

            Puppet::TransBucket.expects(:new).returns bucket

            config.extract_to_transportable.should equal(bucket)
        end

        # Now try it with a more complicated graph -- a three tier graph, each tier
        it "should transform arbitrarily deep graphs into isomorphic trees" do
            config = Puppet::Resource::Catalog.new("mynode")

            @scope = mkscope
            @scope.stubs(:tags).returns([])
            @source = mock 'source'

            # Create our scopes.
            top = mkresource "class", :main
            topbucket = []
            topbucket.expects(:classes=).with([])
            top.expects(:to_trans).returns(topbucket)
            topres = mkresource "file", "/top"
            topres.expects(:to_trans).returns(:topres)
            config.add_edge top, topres

            middle = mkresource "class", "middle"
            middle.expects(:to_trans).returns([])
            config.add_edge top, middle
            midres = mkresource "file", "/mid"
            midres.expects(:to_trans).returns(:midres)
            config.add_edge middle, midres

            bottom = mkresource "class", "bottom"
            bottom.expects(:to_trans).returns([])
            config.add_edge middle, bottom
            botres = mkresource "file", "/bot"
            botres.expects(:to_trans).returns(:botres)
            config.add_edge bottom, botres

            toparray = config.extract_to_transportable

            # This is annoying; it should look like:
            #   [[[:botres], :midres], :topres]
            # but we can't guarantee sort order.
            toparray.include?(:topres).should be_true

            midarray = toparray.find { |t| t.is_a?(Array) }
            midarray.include?(:midres).should be_true
            botarray = midarray.find { |t| t.is_a?(Array) }
            botarray.include?(:botres).should be_true
        end
    end

    describe " when converting to a Puppet::Resource catalog" do
        before do
            @original = Puppet::Resource::Catalog.new("mynode")
            @original.tag(*%w{one two three})
            @original.add_class *%w{four five six}

            @top            = Puppet::TransObject.new 'top', "class"
            @topobject      = Puppet::TransObject.new '/topobject', "file"
            @middle         = Puppet::TransObject.new 'middle', "class"
            @middleobject   = Puppet::TransObject.new '/middleobject', "file"
            @bottom         = Puppet::TransObject.new 'bottom', "class"
            @bottomobject   = Puppet::TransObject.new '/bottomobject', "file"

            @resources = [@top, @topobject, @middle, @middleobject, @bottom, @bottomobject]

            @original.add_resource(*@resources)

            @original.add_edge(@top, @topobject)
            @original.add_edge(@top, @middle)
            @original.add_edge(@middle, @middleobject)
            @original.add_edge(@middle, @bottom)
            @original.add_edge(@bottom, @bottomobject)

            @catalog = @original.to_resource
        end

        it "should copy over the version" do
            @original.version = "foo"
            @original.to_resource.version.should == "foo"
        end

        it "should add all resources as Puppet::Resource instances" do
            @resources.each { |resource| @catalog.resource(resource.ref).should be_instance_of(Puppet::Resource) }
        end

        it "should copy the tag list to the new catalog" do
            @catalog.tags.sort.should == @original.tags.sort
        end

        it "should copy the class list to the new catalog" do
            @catalog.classes.should == @original.classes
        end

        it "should duplicate the original edges" do
            @original.edges.each do |edge|
                @catalog.edge?(@catalog.resource(edge.source.ref), @catalog.resource(edge.target.ref)).should be_true
            end
        end

        it "should set itself as the catalog for each converted resource" do
            @catalog.vertices.each { |v| v.catalog.object_id.should equal(@catalog.object_id) }
        end
    end

    describe "when converting to a RAL catalog" do
        before do
            @original = Puppet::Resource::Catalog.new("mynode")
            @original.tag(*%w{one two three})
            @original.add_class *%w{four five six}

            @top            = Puppet::Resource.new :class, 'top'
            @topobject      = Puppet::Resource.new :file, '/topobject'
            @middle         = Puppet::Resource.new :class, 'middle'
            @middleobject   = Puppet::Resource.new :file, '/middleobject'
            @bottom         = Puppet::Resource.new :class, 'bottom'
            @bottomobject   = Puppet::Resource.new :file, '/bottomobject'

            @resources = [@top, @topobject, @middle, @middleobject, @bottom, @bottomobject]

            @original.add_resource(*@resources)

            @original.add_edge(@top, @topobject)
            @original.add_edge(@top, @middle)
            @original.add_edge(@middle, @middleobject)
            @original.add_edge(@middle, @bottom)
            @original.add_edge(@bottom, @bottomobject)

            @catalog = @original.to_ral
        end

        it "should add all resources as RAL instances" do
            @resources.each { |resource| @catalog.resource(resource.ref).should be_instance_of(Puppet::Type) }
        end

        it "should copy the tag list to the new catalog" do
            @catalog.tags.sort.should == @original.tags.sort
        end

        it "should copy the class list to the new catalog" do
            @catalog.classes.should == @original.classes
        end

        it "should duplicate the original edges" do
            @original.edges.each do |edge|
                @catalog.edge?(@catalog.resource(edge.source.ref), @catalog.resource(edge.target.ref)).should be_true
            end
        end

        it "should set itself as the catalog for each converted resource" do
            @catalog.vertices.each { |v| v.catalog.object_id.should equal(@catalog.object_id) }
        end

        # This tests #931.
        it "should not lose track of resources whose names vary" do
            changer = Puppet::TransObject.new 'changer', 'test'

            config = Puppet::Resource::Catalog.new('test')
            config.add_resource(changer)
            config.add_resource(@top)

            config.add_edge(@top, changer)

            resource = stub 'resource', :name => "changer2", :title => "changer2", :ref => "Test[changer2]", :catalog= => nil, :remove => nil

            #changer is going to get duplicated as part of a fix for aliases 1094
            changer.expects(:dup).returns(changer)
            changer.expects(:to_ral).returns(resource)

            newconfig = nil

            proc { @catalog = config.to_ral }.should_not raise_error
            @catalog.resource("Test[changer2]").should equal(resource)
        end

        after do
            # Remove all resource instances.
            @catalog.clear(true)
        end
    end

    describe "when filtering" do
        before :each do
            @original = Puppet::Resource::Catalog.new("mynode")
            @original.tag(*%w{one two three})
            @original.add_class *%w{four five six}

            @r1 = stub_everything 'r1', :ref => "File[/a]"
            @r1.stubs(:respond_to?).with(:ref).returns(true)
            @r1.stubs(:dup).returns(@r1)
            @r1.stubs(:is_a?).returns(Puppet::Resource).returns(true)

            @r2 = stub_everything 'r2', :ref => "File[/b]"
            @r2.stubs(:respond_to?).with(:ref).returns(true)
            @r2.stubs(:dup).returns(@r2)
            @r2.stubs(:is_a?).returns(Puppet::Resource).returns(true)

            @resources = [@r1,@r2]

            @original.add_resource(@r1,@r2)
        end

        it "should transform the catalog to a resource catalog" do
            @original.expects(:to_catalog).with { |h,b| h == :to_resource }

            @original.filter
        end

        it "should scan each catalog resource in turn and apply filtering block" do
            @resources.each { |r| r.expects(:test?) }
            @original.filter do |r|
                r.test?
            end
        end

        it "should filter out resources which produce true when the filter block is evaluated" do
            @original.filter do |r|
                r == @r1
            end.resource("File[/a]").should be_nil
        end

        it "should not consider edges against resources that were filtered out" do
            @original.add_edge(@r1,@r2)
            @original.filter do |r|
                r == @r1
            end.edge(@r1,@r2).should be_empty
        end
    end

    describe "when functioning as a resource container" do
        before do
            @catalog = Puppet::Resource::Catalog.new("host")
            @one = Puppet::Type.type(:notify).new :name => "one"
            @two = Puppet::Type.type(:notify).new :name => "two"
            @dupe = Puppet::Type.type(:notify).new :name => "one"
        end

        it "should provide a method to add one or more resources" do
            @catalog.add_resource @one, @two
            @catalog.resource(@one.ref).should equal(@one)
            @catalog.resource(@two.ref).should equal(@two)
        end

        it "should add resources to the relationship graph if it exists" do
            relgraph = @catalog.relationship_graph
            @catalog.add_resource @one
            relgraph.should be_vertex(@one)
        end

        it "should yield added resources if a block is provided" do
            yielded = []
            @catalog.add_resource(@one, @two) { |r| yielded << r }
            yielded.length.should == 2
        end

        it "should set itself as the resource's catalog if it is not a relationship graph" do
            @one.expects(:catalog=).with(@catalog)
            @catalog.add_resource @one
        end

        it "should make all vertices available by resource reference" do
            @catalog.add_resource(@one)
            @catalog.resource(@one.ref).should equal(@one)
            @catalog.vertices.find { |r| r.ref == @one.ref }.should equal(@one)
        end

        it "should canonize how resources are referred to during retrieval when both type and title are provided" do
            @catalog.add_resource(@one)

            @catalog.resource("notify", "one").should equal(@one)
        end

        it "should canonize how resources are referred to during retrieval when just the title is provided" do
            @catalog.add_resource(@one)

            @catalog.resource("notify[one]", nil).should equal(@one)
        end

        it "should not allow two resources with the same resource reference" do
            @catalog.add_resource(@one)

            proc { @catalog.add_resource(@dupe) }.should raise_error(Puppet::Resource::Catalog::DuplicateResourceError)
        end

        it "should not store objects that do not respond to :ref" do
            proc { @catalog.add_resource("thing") }.should raise_error(ArgumentError)
        end

        it "should remove all resources when asked" do
            @catalog.add_resource @one
            @catalog.add_resource @two
            @one.expects :remove
            @two.expects :remove
            @catalog.clear(true)
        end

        it "should support a mechanism for finishing resources" do
            @one.expects :finish
            @two.expects :finish
            @catalog.add_resource @one
            @catalog.add_resource @two

            @catalog.finalize
        end

        it "should make default resources when finalizing" do
            @catalog.expects(:make_default_resources)
            @catalog.finalize
        end

        it "should add default resources to the catalog upon creation" do
            @catalog.make_default_resources
            @catalog.resource(:schedule, "daily").should_not be_nil
        end

        it "should optionally support an initialization block and should finalize after such blocks" do
            @one.expects :finish
            @two.expects :finish
            config = Puppet::Resource::Catalog.new("host") do |conf|
                conf.add_resource @one
                conf.add_resource @two
            end
        end

        it "should inform the resource that it is the resource's catalog" do
            @one.expects(:catalog=).with(@catalog)
            @catalog.add_resource @one
        end

        it "should be able to find resources by reference" do
            @catalog.add_resource @one
            @catalog.resource(@one.ref).should equal(@one)
        end

        it "should be able to find resources by reference or by type/title tuple" do
            @catalog.add_resource @one
            @catalog.resource("notify", "one").should equal(@one)
        end

        it "should have a mechanism for removing resources" do
            @catalog.add_resource @one
            @one.expects :remove
            @catalog.remove_resource(@one)
            @catalog.resource(@one.ref).should be_nil
            @catalog.vertex?(@one).should be_false
        end

        it "should have a method for creating aliases for resources" do
            @catalog.add_resource @one
            @catalog.alias(@one, "other")
            @catalog.resource("notify", "other").should equal(@one)
        end

        it "should ignore conflicting aliases that point to the aliased resource" do
            @catalog.alias(@one, "other")
            lambda { @catalog.alias(@one, "other") }.should_not raise_error
        end

        it "should create aliases for resources isomorphic resources whose names do not match their titles" do
            resource = Puppet::Type::File.new(:title => "testing", :path => "/something")

            @catalog.add_resource(resource)

            @catalog.resource(:file, "/something").should equal(resource)
        end

        it "should not create aliases for resources non-isomorphic resources whose names do not match their titles" do
            resource = Puppet::Type.type(:exec).new(:title => "testing", :command => "echo", :path => %w{/bin /usr/bin /usr/local/bin})

            @catalog.add_resource(resource)

            # Yay, I've already got a 'should' method
            @catalog.resource(:exec, "echo").object_id.should == nil.object_id
        end

        # This test is the same as the previous, but the behaviour should be explicit.
        it "should alias using the class name from the resource reference, not the resource class name" do
            @catalog.add_resource @one
            @catalog.alias(@one, "other")
            @catalog.resource("notify", "other").should equal(@one)
        end

        it "should ignore conflicting aliases that point to the aliased resource" do
            @catalog.alias(@one, "other")
            lambda { @catalog.alias(@one, "other") }.should_not raise_error
        end

        it "should fail to add an alias if the aliased name already exists" do
            @catalog.add_resource @one
            proc { @catalog.alias @two, "one" }.should raise_error(ArgumentError)
        end

        it "should not fail when a resource has duplicate aliases created" do
            @catalog.add_resource @one
            proc { @catalog.alias @one, "one" }.should_not raise_error
        end

        it "should not create aliases that point back to the resource" do
            @catalog.alias(@one, "one")
            @catalog.resource(:notify, "one").should be_nil
        end

        it "should be able to look resources up by their aliases" do
            @catalog.add_resource @one
            @catalog.alias @one, "two"
            @catalog.resource(:notify, "two").should equal(@one)
        end

        it "should remove resource aliases when the target resource is removed" do
            @catalog.add_resource @one
            @catalog.alias(@one, "other")
            @one.expects :remove
            @catalog.remove_resource(@one)
            @catalog.resource("notify", "other").should be_nil
        end

        it "should add an alias for the namevar when the title and name differ on isomorphic resource types" do
            resource = Puppet::Type.type(:file).new :path => "/something", :title => "other", :content => "blah"
            resource.expects(:isomorphic?).returns(true)
            @catalog.add_resource(resource)
            @catalog.resource(:file, "other").should equal(resource)
            @catalog.resource(:file, "/something").ref.should == resource.ref
        end

        it "should not add an alias for the namevar when the title and name differ on non-isomorphic resource types" do
            resource = Puppet::Type.type(:file).new :path => "/something", :title => "other", :content => "blah"
            resource.expects(:isomorphic?).returns(false)
            @catalog.add_resource(resource)
            @catalog.resource(:file, resource.title).should equal(resource)
            # We can't use .should here, because the resources respond to that method.
            if @catalog.resource(:file, resource.name)
                raise "Aliased non-isomorphic resource"
            end
        end

        it "should provide a method to create additional resources that also registers the resource" do
            args = {:name => "/yay", :ensure => :file}
            resource = stub 'file', :ref => "File[/yay]", :catalog= => @catalog, :title => "/yay", :[] => "/yay"
            Puppet::Type.type(:file).expects(:new).with(args).returns(resource)
            @catalog.create_resource :file, args
            @catalog.resource("File[/yay]").should equal(resource)
        end
    end

    describe "when applying" do
        before :each do
            @catalog = Puppet::Resource::Catalog.new("host")

            @catalog.retrieval_duration = Time.now
            @transaction = mock 'transaction'
            Puppet::Transaction.stubs(:new).returns(@transaction)
            @transaction.stubs(:evaluate)
            @transaction.stubs(:cleanup)
            @transaction.stubs(:addtimes)
        end

        it "should create and evaluate a transaction" do
            @transaction.expects(:evaluate)
            @catalog.apply
        end

        it "should provide the catalog time to the transaction" do
            @transaction.expects(:addtimes).with do |arg|
                arg[:config_retrieval].should be_instance_of(Time)
                true
            end
            @catalog.apply
        end

        it "should clean up the transaction" do
            @transaction.expects :cleanup
            @catalog.apply
        end

        it "should return the transaction" do
            @catalog.apply.should equal(@transaction)
        end

        it "should yield the transaction if a block is provided" do
            @catalog.apply do |trans|
                trans.should equal(@transaction)
            end
        end

        it "should default to not being a host catalog" do
            @catalog.host_config.should be_nil
        end

        it "should pass supplied tags on to the transaction" do
            @transaction.expects(:tags=).with(%w{one two})
            @catalog.apply(:tags => %w{one two})
        end

        it "should set ignoreschedules on the transaction if specified in apply()" do
            @transaction.expects(:ignoreschedules=).with(true)
            @catalog.apply(:ignoreschedules => true)
        end

        it "should remove resources created mid-transaction" do
            args = {:name => "/yay", :ensure => :file}
            resource = stub 'file', :ref => "File[/yay]", :catalog= => @catalog, :title => "/yay", :[] => "/yay"
            @transaction = mock 'transaction'
            Puppet::Transaction.stubs(:new).returns(@transaction)
            @transaction.stubs(:evaluate)
            @transaction.stubs(:cleanup)
            @transaction.stubs(:addtimes)
            Puppet::Type.type(:file).expects(:new).with(args).returns(resource)
            resource.expects :remove
            @catalog.apply do |trans|
                @catalog.create_resource :file, args
                @catalog.resource("File[/yay]").should equal(resource)
            end
            @catalog.resource("File[/yay]").should be_nil
        end

        it "should remove resources added mid-transaction" do
            @transaction = mock 'transaction'
            Puppet::Transaction.stubs(:new).returns(@transaction)
            @transaction.stubs(:evaluate)
            @transaction.stubs(:cleanup)
            @transaction.stubs(:addtimes)
            file = Puppet::Type.type(:file).new(:name => "/yay", :ensure => :file)
            @catalog.apply do |trans|
                @catalog.add_resource file
                @catalog.resource("File[/yay]").should_not be_nil
            end
            @catalog.resource("File[/yay]").should be_nil
        end

        it "should expire cached data in the resources both before and after the transaction" do
            @catalog.expects(:expire).times(2)
            @catalog.apply
        end

        describe "host catalogs" do

            # super() doesn't work in the setup method for some reason
            before do
                @catalog.host_config = true
                Puppet::Util::Storage.stubs(:store)
            end

            it "should send a report if reporting is enabled" do
                Puppet[:report] = true
                @transaction.expects :send_report
                @transaction.stubs :any_failed? => false
                @catalog.apply
            end

            it "should send a report if report summaries are enabled" do
                Puppet[:summarize] = true
                @transaction.expects :send_report
                @transaction.stubs :any_failed? => false
                @catalog.apply
            end

            it "should initialize the state database before applying a catalog" do
                Puppet::Util::Storage.expects(:load)

                # Short-circuit the apply, so we know we're loading before the transaction
                Puppet::Transaction.expects(:new).raises ArgumentError
                proc { @catalog.apply }.should raise_error(ArgumentError)
            end

            it "should sync the state database after applying" do
                Puppet::Util::Storage.expects(:store)
                @transaction.stubs :any_failed? => false
                @catalog.apply
            end

            after { Puppet.settings.clear }
        end

        describe "non-host catalogs" do

            before do
                @catalog.host_config = false
            end

            it "should never send reports" do
                Puppet[:report] = true
                Puppet[:summarize] = true
                @transaction.expects(:send_report).never
                @catalog.apply
            end

            it "should never modify the state database" do
                Puppet::Util::Storage.expects(:load).never
                Puppet::Util::Storage.expects(:store).never
                @catalog.apply
            end

            after { Puppet.settings.clear }
        end
    end

    describe "when creating a relationship graph" do
        before do
            Puppet::Type.type(:component)
            @catalog = Puppet::Resource::Catalog.new("host")
            @compone = Puppet::Type::Component.new :name => "one"
            @comptwo = Puppet::Type::Component.new :name => "two", :require => "Class[one]"
            @file = Puppet::Type.type(:file)
            @one = @file.new :path => "/one"
            @two = @file.new :path => "/two"
            @sub = @file.new :path => "/two/subdir"
            @catalog.add_edge @compone, @one
            @catalog.add_edge @comptwo, @two

            @three = @file.new :path => "/three"
            @four = @file.new :path => "/four", :require => "File[/three]"
            @five = @file.new :path => "/five"
            @catalog.add_resource @compone, @comptwo, @one, @two, @three, @four, @five, @sub

            @relationships = @catalog.relationship_graph
        end

        it "should be able to create a relationship graph" do
            @relationships.should be_instance_of(Puppet::SimpleGraph)
        end

        it "should not have any components" do
            @relationships.vertices.find { |r| r.instance_of?(Puppet::Type::Component) }.should be_nil
        end

        it "should have all non-component resources from the catalog" do
            # The failures print out too much info, so i just do a class comparison
            @relationships.vertex?(@five).should be_true
        end

        it "should have all resource relationships set as edges" do
            @relationships.edge?(@three, @four).should be_true
        end

        it "should copy component relationships to all contained resources" do
            @relationships.edge?(@one, @two).should be_true
        end

        it "should add automatic relationships to the relationship graph" do
            @relationships.edge?(@two, @sub).should be_true
        end

        it "should get removed when the catalog is cleaned up" do
            @relationships.expects(:clear)
            @catalog.clear
            @catalog.instance_variable_get("@relationship_graph").should be_nil
        end

        it "should write :relationships and :expanded_relationships graph files if the catalog is a host catalog" do
            @catalog.clear
            graph = Puppet::SimpleGraph.new
            Puppet::SimpleGraph.expects(:new).returns graph

            graph.expects(:write_graph).with(:relationships)
            graph.expects(:write_graph).with(:expanded_relationships)

            @catalog.host_config = true

            @catalog.relationship_graph
        end

        it "should not write graph files if the catalog is not a host catalog" do
            @catalog.clear
            graph = Puppet::SimpleGraph.new
            Puppet::SimpleGraph.expects(:new).returns graph

            graph.expects(:write_graph).never

            @catalog.host_config = false

            @catalog.relationship_graph
        end

        it "should create a new relationship graph after clearing the old one" do
            @relationships.expects(:clear)
            @catalog.clear
            @catalog.relationship_graph.should be_instance_of(Puppet::SimpleGraph)
        end

        it "should remove removed resources from the relationship graph if it exists" do
            @catalog.remove_resource(@one)
            @catalog.relationship_graph.vertex?(@one).should be_false
        end
    end

    describe "when writing dot files" do
        before do
            @catalog = Puppet::Resource::Catalog.new("host")
            @name = :test
            @file = File.join(Puppet[:graphdir], @name.to_s + ".dot")
        end

        it "should only write when it is a host catalog" do
            File.expects(:open).with(@file).never
            @catalog.host_config = false
            Puppet[:graph] = true
            @catalog.write_graph(@name)
        end

        after do
            Puppet.settings.clear
        end
    end

    describe "when indirecting" do
        before do
            @indirection = stub 'indirection', :name => :catalog

            Puppet::Util::Cacher.expire
        end

        it "should redirect to the indirection for retrieval" do
            Puppet::Resource::Catalog.stubs(:indirection).returns(@indirection)
            @indirection.expects(:find)
            Puppet::Resource::Catalog.find(:myconfig)
        end

        it "should default to the 'compiler' terminus" do
            Puppet::Resource::Catalog.indirection.terminus_class.should == :compiler
        end

        after do
            Puppet::Util::Cacher.expire
        end
    end

    describe "when converting to yaml" do
        before do
            @catalog = Puppet::Resource::Catalog.new("me")
            @catalog.add_edge("one", "two")
        end

        it "should be able to be dumped to yaml" do
            YAML.dump(@catalog).should be_instance_of(String)
        end
    end

    describe "when converting from yaml" do
        before do
            @catalog = Puppet::Resource::Catalog.new("me")
            @catalog.add_edge("one", "two")

            text = YAML.dump(@catalog)
            @newcatalog = YAML.load(text)
        end

        it "should get converted back to a catalog" do
            @newcatalog.should be_instance_of(Puppet::Resource::Catalog)
        end

        it "should have all vertices" do
            @newcatalog.vertex?("one").should be_true
            @newcatalog.vertex?("two").should be_true
        end

        it "should have all edges" do
            @newcatalog.edge?("one", "two").should be_true
        end
    end
end

describe Puppet::Resource::Catalog, "when converting to pson" do
    confine "Missing 'pson' library" => Puppet.features.pson?

    before do
        @catalog = Puppet::Resource::Catalog.new("myhost")
    end

    def pson_output_should
        @catalog.class.expects(:pson_create).with { |hash| yield hash }.returns(:something)
    end

    # LAK:NOTE For all of these tests, we convert back to the resource so we can
    # trap the actual data structure then.
    it "should set its document_type to 'Catalog'" do
        pson_output_should { |hash| hash['document_type'] == "Catalog" }

        PSON.parse @catalog.to_pson
    end

    it "should set its data as a hash" do
        pson_output_should { |hash| hash['data'].is_a?(Hash) }
        PSON.parse @catalog.to_pson
    end

    [:name, :version, :tags, :classes].each do |param|
        it "should set its #{param} to the #{param} of the resource" do
            @catalog.send(param.to_s + "=", "testing") unless @catalog.send(param)

            pson_output_should { |hash| hash['data'][param.to_s] == @catalog.send(param) }
            PSON.parse @catalog.to_pson
        end
    end

    it "should convert its resources to a PSON-encoded array and store it as the 'resources' data" do
        one = stub 'one', :to_pson_data_hash => "one_resource", :ref => "Foo[one]"
        two = stub 'two', :to_pson_data_hash => "two_resource", :ref => "Foo[two]"

        @catalog.add_resource(one)
        @catalog.add_resource(two)

        # TODO this should really guarantee sort order
        PSON.parse(@catalog.to_pson,:create_additions => false)['data']['resources'].sort.should == ["one_resource", "two_resource"].sort

    end

    it "should convert its edges to a PSON-encoded array and store it as the 'edges' data" do
        one   = stub 'one',   :to_pson_data_hash => "one_resource",   :ref => 'Foo[one]'
        two   = stub 'two',   :to_pson_data_hash => "two_resource",   :ref => 'Foo[two]'
        three = stub 'three', :to_pson_data_hash => "three_resource", :ref => 'Foo[three]'

        @catalog.add_edge(one, two)
        @catalog.add_edge(two, three)

        @catalog.edge(one, two  ).expects(:to_pson_data_hash).returns "one_two_pson"
        @catalog.edge(two, three).expects(:to_pson_data_hash).returns "two_three_pson"

        PSON.parse(@catalog.to_pson,:create_additions => false)['data']['edges'].sort.should == %w{one_two_pson two_three_pson}.sort
    end
end

describe Puppet::Resource::Catalog, "when converting from pson" do
    confine "Missing 'pson' library" => Puppet.features.pson?

    def pson_result_should
        Puppet::Resource::Catalog.expects(:new).with { |hash| yield hash }
    end

    before do
        @data = {
            'name' => "myhost"
        }
        @pson = {
            'document_type' => 'Puppet::Resource::Catalog',
            'data' => @data,
            'metadata' => {}
        }

        @catalog = Puppet::Resource::Catalog.new("myhost")
        Puppet::Resource::Catalog.stubs(:new).returns @catalog
    end

    it "should be extended with the PSON utility module" do
        Puppet::Resource::Catalog.metaclass.ancestors.should be_include(Puppet::Util::Pson)
    end

    it "should create it with the provided name" do
        Puppet::Resource::Catalog.expects(:new).with('myhost').returns @catalog
        PSON.parse @pson.to_pson
    end

    it "should set the provided version on the catalog if one is set" do
        @data['version'] = 50
        PSON.parse @pson.to_pson
        @catalog.version.should == @data['version']
    end

    it "should set any provided tags on the catalog" do
        @data['tags'] = %w{one two}
        PSON.parse @pson.to_pson
        @catalog.tags.should == @data['tags']
    end

    it "should set any provided classes on the catalog" do
        @data['classes'] = %w{one two}
        PSON.parse @pson.to_pson
        @catalog.classes.should == @data['classes']
    end

    it 'should convert the resources list into resources and add each of them' do
        @data['resources'] = [Puppet::Resource.new(:file, "/foo"), Puppet::Resource.new(:file, "/bar")]

        @catalog.expects(:add_resource).times(2).with { |res| res.type == "File" }
        PSON.parse @pson.to_pson
    end

    it 'should convert resources even if they do not include "type" information' do
        @data['resources'] = [Puppet::Resource.new(:file, "/foo")]

        @data['resources'][0].expects(:to_pson).returns '{"title":"/foo","tags":["file"],"type":"File"}'

        @catalog.expects(:add_resource).with { |res| res.type == "File" }

        PSON.parse @pson.to_pson
    end

    it 'should convert the edges list into edges and add each of them' do
        one = Puppet::Relationship.new("osource", "otarget", :event => "one", :callback => "refresh")
        two = Puppet::Relationship.new("tsource", "ttarget", :event => "two", :callback => "refresh")

        @data['edges'] = [one, two]

        @catalog.stubs(:resource).returns("eh")

        @catalog.expects(:add_edge).with { |edge| edge.event == "one" }
        @catalog.expects(:add_edge).with { |edge| edge.event == "two" }

        PSON.parse @pson.to_pson
    end

    it "should be able to convert relationships that do not include 'type' information" do
        one = Puppet::Relationship.new("osource", "otarget", :event => "one", :callback => "refresh")
        one.expects(:to_pson).returns "{\"event\":\"one\",\"callback\":\"refresh\",\"source\":\"osource\",\"target\":\"otarget\"}"

        @data['edges'] = [one]

        @catalog.stubs(:resource).returns("eh")

        @catalog.expects(:add_edge).with { |edge| edge.event == "one" }

        PSON.parse @pson.to_pson
    end

    it "should set the source and target for each edge to the actual resource" do
        edge = Puppet::Relationship.new("source", "target")

        @data['edges'] = [edge]

        @catalog.expects(:resource).with("source").returns("source_resource")
        @catalog.expects(:resource).with("target").returns("target_resource")

        @catalog.expects(:add_edge).with { |edge| edge.source == "source_resource" and edge.target == "target_resource" }

        PSON.parse @pson.to_pson
    end

    it "should fail if the source resource cannot be found" do
        edge = Puppet::Relationship.new("source", "target")

        @data['edges'] = [edge]

        @catalog.expects(:resource).with("source").returns(nil)
        @catalog.stubs(:resource).with("target").returns("target_resource")

        lambda { PSON.parse @pson.to_pson }.should raise_error(ArgumentError)
    end

    it "should fail if the target resource cannot be found" do
        edge = Puppet::Relationship.new("source", "target")

        @data['edges'] = [edge]

        @catalog.stubs(:resource).with("source").returns("source_resource")
        @catalog.expects(:resource).with("target").returns(nil)

        lambda { PSON.parse @pson.to_pson }.should raise_error(ArgumentError)
    end
end
