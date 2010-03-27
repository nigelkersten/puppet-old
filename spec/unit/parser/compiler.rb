#!/usr/bin/env ruby

require File.dirname(__FILE__) + '/../../spec_helper'

class CompilerTestResource
    attr_accessor :builtin, :virtual, :evaluated, :type, :title

    def initialize(type, title)
        @type = type
        @title = title
    end

    def ref
        "%s[%s]" % [type.to_s.capitalize, title]
    end

    def evaluated?
        @evaluated
    end

    def builtin?
        @builtin
    end

    def virtual?
        @virtual
    end

    def evaluate
    end
end

describe Puppet::Parser::Compiler do
    before :each do
        @node = Puppet::Node.new "testnode"
        @parser = Puppet::Parser::Parser.new :environment => "development"

        @scope_resource = stub 'scope_resource', :builtin? => true, :finish => nil, :ref => 'Class[main]', :type => "class"
        @scope = stub 'scope', :resource => @scope_resource, :source => mock("source")
        @compiler = Puppet::Parser::Compiler.new(@node, @parser)
    end

    it "should be able to return a class list containing all added classes" do
        @compiler.add_class ""
        @compiler.add_class "one"
        @compiler.add_class "two"

        @compiler.classlist.sort.should == %w{one two}.sort
    end

    describe "when initializing" do

        it "should set its node attribute" do
            @compiler.node.should equal(@node)
        end

        it "should set its parser attribute" do
            @compiler.parser.should equal(@parser)
        end

        it "should detect when ast nodes are absent" do
            @compiler.ast_nodes?.should be_false
        end

        it "should detect when ast nodes are present" do
            @parser.expects(:nodes?).returns true
            @compiler.ast_nodes?.should be_true
        end

        it "should copy the parser version to the catalog" do
            @compiler.catalog.version.should == @parser.version
        end

        it "should copy any node classes into the class list" do
            node = Puppet::Node.new("mynode")
            node.classes = %w{foo bar}
            compiler = Puppet::Parser::Compiler.new(node, @parser)
            p compiler.classlist

            compiler.classlist.should include("foo")
            compiler.classlist.should include("bar")
        end
    end

    describe "when managing scopes" do

        it "should create a top scope" do
            @compiler.topscope.should be_instance_of(Puppet::Parser::Scope)
        end

        it "should be able to create new scopes" do
            @compiler.newscope(@compiler.topscope).should be_instance_of(Puppet::Parser::Scope)
        end

        it "should correctly set the level of newly created scopes" do
            @compiler.newscope(@compiler.topscope, :level => 5).level.should == 5
        end

        it "should set the parent scope of the new scope to be the passed-in parent" do
            scope = mock 'scope'
            newscope = @compiler.newscope(scope)

            newscope.parent.should equal(scope)
        end

        it "should set the parent scope of the new scope to its topscope if the parent passed in is nil" do
            scope = mock 'scope'
            newscope = @compiler.newscope(nil)

            newscope.parent.should equal(@compiler.topscope)
        end
    end

    describe "when compiling" do

        def compile_methods
            [:set_node_parameters, :evaluate_main, :evaluate_ast_node, :evaluate_node_classes, :evaluate_generators, :fail_on_unevaluated,
                :finish, :store, :extract]
        end

        # Stub all of the main compile methods except the ones we're specifically interested in.
        def compile_stub(*except)
            (compile_methods - except).each { |m| @compiler.stubs(m) }
        end

        it "should set node parameters as variables in the top scope" do
            params = {"a" => "b", "c" => "d"}
            @node.stubs(:parameters).returns(params)
            compile_stub(:set_node_parameters)
            @compiler.compile
            @compiler.topscope.lookupvar("a").should == "b"
            @compiler.topscope.lookupvar("c").should == "d"
        end

        it "should set the client and server versions on the catalog" do
            params = {"clientversion" => "2", "serverversion" => "3"}
            @node.stubs(:parameters).returns(params)
            compile_stub(:set_node_parameters)
            @compiler.compile
            @compiler.catalog.client_version.should == "2"
            @compiler.catalog.server_version.should == "3"
        end

        it "should evaluate any existing classes named in the node" do
            classes = %w{one two three four}
            main = stub 'main'
            one = stub 'one', :name => "one"
            three = stub 'three', :name => "three"
            @node.stubs(:name).returns("whatever")
            @node.stubs(:classes).returns(classes)

            @compiler.expects(:evaluate_classes).with(classes, @compiler.topscope)
            @compiler.class.publicize_methods(:evaluate_node_classes) { @compiler.evaluate_node_classes }
        end

        it "should evaluate the main class if it exists" do
            compile_stub(:evaluate_main)
            main_class = mock 'main_class'
            main_class.expects(:evaluate_code).with { |r| r.is_a?(Puppet::Parser::Resource) }
            @compiler.topscope.expects(:source=).with(main_class)
            @parser.stubs(:find_hostclass).with("", "").returns(main_class)

            @compiler.compile
        end

        it "should evaluate any node classes" do
            @node.stubs(:classes).returns(%w{one two three four})
            @compiler.expects(:evaluate_classes).with(%w{one two three four}, @compiler.topscope)
            @compiler.send(:evaluate_node_classes)
        end

        it "should evaluate all added collections" do
            colls = []
            # And when the collections fail to evaluate.
            colls << mock("coll1-false")
            colls << mock("coll2-false")
            colls.each { |c| c.expects(:evaluate).returns(false) }

            @compiler.add_collection(colls[0])
            @compiler.add_collection(colls[1])

            compile_stub(:evaluate_generators)
            @compiler.compile
        end

        it "should ignore builtin resources" do
            resource = stub 'builtin', :ref => "File[testing]", :builtin? => true, :type => "file"

            @compiler.add_resource(@scope, resource)
            resource.expects(:evaluate).never

            @compiler.compile
        end

        it "should evaluate unevaluated resources" do
            resource = CompilerTestResource.new(:file, "testing")

            @compiler.add_resource(@scope, resource)

            # We have to now mark the resource as evaluated
            resource.expects(:evaluate).with { |*whatever| resource.evaluated = true }

            @compiler.compile
        end

        it "should not evaluate already-evaluated resources" do
            resource = stub 'already_evaluated', :ref => "File[testing]", :builtin? => false, :evaluated? => true, :virtual? => false, :type => "file"
            @compiler.add_resource(@scope, resource)
            resource.expects(:evaluate).never

            @compiler.compile
        end

        it "should evaluate unevaluated resources created by evaluating other resources" do
            resource = CompilerTestResource.new(:file, "testing")
            @compiler.add_resource(@scope, resource)

            resource2 = CompilerTestResource.new(:file, "other")

            # We have to now mark the resource as evaluated
            resource.expects(:evaluate).with { |*whatever| resource.evaluated = true; @compiler.add_resource(@scope, resource2) }
            resource2.expects(:evaluate).with { |*whatever| resource2.evaluated = true }


            @compiler.compile
        end

        it "should call finish() on all resources" do
            # Add a resource that does respond to :finish
            resource = Puppet::Parser::Resource.new :scope => @scope, :type => "file", :title => "finish"
            resource.expects(:finish)

            @compiler.add_resource(@scope, resource)

            # And one that does not
            dnf = stub "dnf", :ref => "File[dnf]", :type => "file"

            @compiler.add_resource(@scope, dnf)

            @compiler.send(:finish)
        end

        it "should call finish() in add_resource order" do
            resources = sequence('resources')

            resource1 = Puppet::Parser::Resource.new :scope => @scope, :type => "file", :title => "finish1"
            resource1.expects(:finish).in_sequence(resources)

            @compiler.add_resource(@scope, resource1)

            resource2 = Puppet::Parser::Resource.new :scope => @scope, :type => "file", :title => "finish2"
            resource2.expects(:finish).in_sequence(resources)

            @compiler.add_resource(@scope, resource2)

            @compiler.send(:finish)
        end

        it "should return added resources in add order" do
            resource1 = stub "1", :ref => "File[yay]", :type => "file"
            @compiler.add_resource(@scope, resource1)
            resource2 = stub "2", :ref => "File[youpi]", :type => "file"
            @compiler.add_resource(@scope, resource2)

            @compiler.resources.should == [resource1, resource2]
        end

        it "should add resources that do not conflict with existing resources" do
            resource = CompilerTestResource.new(:file, "yay")
            @compiler.add_resource(@scope, resource)

            @compiler.catalog.should be_vertex(resource)
        end

        it "should fail to add resources that conflict with existing resources" do
            file1 = Puppet::Type.type(:file).new :path => "/foo"
            file2 = Puppet::Type.type(:file).new :path => "/foo"

            @compiler.add_resource(@scope, file1)
            lambda { @compiler.add_resource(@scope, file2) }.should raise_error(Puppet::Resource::Catalog::DuplicateResourceError)
        end

        it "should add an edge from the scope resource to the added resource" do
            resource = stub "noconflict", :ref => "File[yay]", :type => "file"
            @compiler.add_resource(@scope, resource)

            @compiler.catalog.should be_edge(@scope.resource, resource)
        end

        it "should add edges from the class resources to the main class" do
            main = CompilerTestResource.new(:class, :main)
            @compiler.add_resource(@scope, main)
            resource = CompilerTestResource.new(:class, "foo")
            @compiler.add_resource(@scope, resource)

            @compiler.catalog.should be_edge(main, resource)
        end

        it "should just add edges to the scope resource for the class resources when no main class can be found" do
            resource = CompilerTestResource.new(:class, "foo")
            @compiler.add_resource(@scope, resource)

            @compiler.catalog.should be_edge(@scope.resource, resource)
        end

        it "should have a method for looking up resources" do
            resource = stub 'resource', :ref => "Yay[foo]", :type => "file"
            @compiler.add_resource(@scope, resource)
            @compiler.findresource("Yay[foo]").should equal(resource)
        end

        it "should be able to look resources up by type and title" do
            resource = stub 'resource', :ref => "Yay[foo]", :type => "file"
            @compiler.add_resource(@scope, resource)
            @compiler.findresource("Yay", "foo").should equal(resource)
        end

        it "should not evaluate virtual defined resources" do
            resource = stub 'notevaluated', :ref => "File[testing]", :builtin? => false, :evaluated? => false, :virtual? => true, :type => "file"
            @compiler.add_resource(@scope, resource)

            resource.expects(:evaluate).never

            @compiler.compile
        end
    end

    describe "when evaluating collections" do

        it "should evaluate each collection" do
            2.times { |i|
                coll = mock 'coll%s' % i
                @compiler.add_collection(coll)

                # This is the hard part -- we have to emulate the fact that
                # collections delete themselves if they are done evaluating.
                coll.expects(:evaluate).with do
                    @compiler.delete_collection(coll)
                end
            }

            @compiler.class.publicize_methods(:evaluate_collections) { @compiler.evaluate_collections }
        end

        it "should not fail when there are unevaluated resource collections that do not refer to specific resources" do
            coll = stub 'coll', :evaluate => false
            coll.expects(:resources).returns(nil)

            @compiler.add_collection(coll)

            lambda { @compiler.compile }.should_not raise_error
        end

        it "should fail when there are unevaluated resource collections that refer to a specific resource" do
            coll = stub 'coll', :evaluate => false
            coll.expects(:resources).returns(:something)

            @compiler.add_collection(coll)

            lambda { @compiler.compile }.should raise_error(Puppet::ParseError)
        end

        it "should fail when there are unevaluated resource collections that refer to multiple specific resources" do
            coll = stub 'coll', :evaluate => false
            coll.expects(:resources).returns([:one, :two])

            @compiler.add_collection(coll)

            lambda { @compiler.compile }.should raise_error(Puppet::ParseError)
        end
    end

    describe "when told to evaluate missing classes" do

        it "should fail if there's no source listed for the scope" do
            scope = stub 'scope', :source => nil
            proc { @compiler.evaluate_classes(%w{one two}, scope) }.should raise_error(Puppet::DevError)
        end

        it "should tag the catalog with the name of each not-found class" do
            @compiler.catalog.expects(:tag).with("notfound")
            @scope.expects(:find_hostclass).with("notfound").returns(nil)
            @compiler.evaluate_classes(%w{notfound}, @scope)
        end
    end

    describe "when evaluating found classes" do

        before do
            @class = stub 'class', :name => "my::class"
            @scope.stubs(:find_hostclass).with("myclass").returns(@class)

            @resource = stub 'resource', :ref => "Class[myclass]", :type => "file"
        end

        it "should evaluate each class" do
            @compiler.catalog.stubs(:tag)

            @class.expects(:mk_plain_resource).with(@scope)
            @scope.stubs(:class_scope).with(@class)

            @compiler.evaluate_classes(%w{myclass}, @scope)
        end

        it "should not evaluate the resources created for found classes unless asked" do
            @compiler.catalog.stubs(:tag)

            @resource.expects(:evaluate).never

            @class.expects(:mk_plain_resource).returns(@resource)
            @scope.stubs(:class_scope).with(@class)

            @compiler.evaluate_classes(%w{myclass}, @scope)
        end

        it "should immediately evaluate the resources created for found classes when asked" do
            @compiler.catalog.stubs(:tag)

            @resource.expects(:evaluate)
            @class.expects(:mk_plain_resource).returns(@resource)
            @scope.stubs(:class_scope).with(@class)

            @compiler.evaluate_classes(%w{myclass}, @scope, false)
        end

        it "should skip classes that have already been evaluated" do
            @compiler.catalog.stubs(:tag)

            @scope.stubs(:class_scope).with(@class).returns("something")

            @compiler.expects(:add_resource).never

            @resource.expects(:evaluate).never

            Puppet::Parser::Resource.expects(:new).never
            @compiler.evaluate_classes(%w{myclass}, @scope, false)
        end

        it "should skip classes previously evaluated with different capitalization" do
            @compiler.catalog.stubs(:tag)
            @scope.stubs(:find_hostclass).with("MyClass").returns(@class)
            @scope.stubs(:class_scope).with(@class).returns("something")
            @compiler.expects(:add_resource).never
            @resource.expects(:evaluate).never
            Puppet::Parser::Resource.expects(:new).never
            @compiler.evaluate_classes(%w{MyClass}, @scope, false)
        end

        it "should return the list of found classes" do
            @compiler.catalog.stubs(:tag)

            @compiler.stubs(:add_resource)
            @scope.stubs(:find_hostclass).with("notfound").returns(nil)
            @scope.stubs(:class_scope).with(@class)

            Puppet::Parser::Resource.stubs(:new).returns(@resource)
            @class.stubs :mk_plain_resource
            @compiler.evaluate_classes(%w{myclass notfound}, @scope).should == %w{myclass}
        end
    end

    describe "when evaluating AST nodes with no AST nodes present" do

        it "should do nothing" do
            @compiler.expects(:ast_nodes?).returns(false)
            @compiler.parser.expects(:nodes).never
            Puppet::Parser::Resource.expects(:new).never

            @compiler.send(:evaluate_ast_node)
        end
    end

    describe "when evaluating AST nodes with AST nodes present" do

        before do
            @compiler.parser.stubs(:nodes?).returns true

            # Set some names for our test
            @node.stubs(:names).returns(%w{a b c})
            @compiler.parser.stubs(:node).with("a").returns(nil)
            @compiler.parser.stubs(:node).with("b").returns(nil)
            @compiler.parser.stubs(:node).with("c").returns(nil)

            # It should check this last, of course.
            @compiler.parser.stubs(:node).with("default").returns(nil)
        end

        it "should fail if the named node cannot be found" do
            proc { @compiler.send(:evaluate_ast_node) }.should raise_error(Puppet::ParseError)
        end

        it "should evaluate the first node class matching the node name" do
            node_class = stub 'node', :name => "c", :evaluate_code => nil
            @compiler.parser.stubs(:node).with("c").returns(node_class)

            node_resource = stub 'node resource', :ref => "Node[c]", :evaluate => nil, :type => "node"
            node_class.expects(:mk_plain_resource).returns(node_resource)

            @compiler.compile
        end

        it "should match the default node if no matching node can be found" do
            node_class = stub 'node', :name => "default", :evaluate_code => nil
            @compiler.parser.stubs(:node).with("default").returns(node_class)

            node_resource = stub 'node resource', :ref => "Node[default]", :evaluate => nil, :type => "node"
            node_class.expects(:mk_plain_resource).returns(node_resource)

            @compiler.compile
        end

        it "should evaluate the node resource immediately rather than using lazy evaluation" do
            node_class = stub 'node', :name => "c"
            @compiler.parser.stubs(:node).with("c").returns(node_class)

            node_resource = stub 'node resource', :ref => "Node[c]", :type => "node"
            node_class.expects(:mk_plain_resource).returns(node_resource)

            node_resource.expects(:evaluate)

            @compiler.send(:evaluate_ast_node)
        end

        it "should set the node's scope as the top scope" do
            node_resource = stub 'node resource', :ref => "Node[c]", :evaluate => nil, :type => "node"
            node_class = stub 'node', :name => "c", :mk_plain_resource => node_resource

            @compiler.parser.stubs(:node).with("c").returns(node_class)

            # The #evaluate method normally does this.
            scope = stub 'scope', :source => "mysource"
            @compiler.topscope.expects(:class_scope).with(node_class).returns(scope)
            node_resource.stubs(:evaluate)

            @compiler.compile

            @compiler.topscope.should equal(scope)
        end
    end

    describe "when managing resource overrides" do

        before do
            @override = stub 'override', :ref => "My[ref]", :type => "my"
            @resource = stub 'resource', :ref => "My[ref]", :builtin? => true, :type => "my"
        end

        it "should be able to store overrides" do
            lambda { @compiler.add_override(@override) }.should_not raise_error
        end

        it "should apply overrides to the appropriate resources" do
            @compiler.add_resource(@scope, @resource)
            @resource.expects(:merge).with(@override)

            @compiler.add_override(@override)

            @compiler.compile
        end

        it "should accept overrides before the related resource has been created" do
            @resource.expects(:merge).with(@override)

            # First store the override
            @compiler.add_override(@override)

            # Then the resource
            @compiler.add_resource(@scope, @resource)

            # And compile, so they get resolved
            @compiler.compile
        end

        it "should fail if the compile is finished and resource overrides have not been applied" do
            @compiler.add_override(@override)

            lambda { @compiler.compile }.should raise_error(Puppet::ParseError)
        end
    end
end
