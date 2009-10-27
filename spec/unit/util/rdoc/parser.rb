#!/usr/bin/env ruby

Dir.chdir(File.dirname(__FILE__)) { (s = lambda { |f| File.exist?(f) ? require(f) : Dir.chdir("..") { s.call(f) } }).call("spec/spec_helper.rb") }

require 'puppet/parser/loaded_code'
require 'puppet/util/rdoc/parser'
require 'puppet/util/rdoc/code_objects'
require 'rdoc/options'
require 'rdoc/rdoc'

describe RDoc::Parser do
    before :each do
        File.stubs(:stat).with("init.pp")
        @top_level = stub_everything 'toplevel', :file_relative_name => "init.pp"
        @parser = RDoc::Parser.new(@top_level, "module/manifests/init.pp", nil, Options.instance, RDoc::Stats.new)
    end

    describe "when scanning files" do
        it "should parse puppet files with the puppet parser" do
            @parser.stubs(:scan_top_level)
            parser = stub 'parser'
            Puppet::Parser::Parser.expects(:new).returns(parser)
            parser.expects(:parse)
            parser.expects(:file=).with("module/manifests/init.pp")

            @parser.scan
        end

        it "should scan the ast for Puppet files" do
            parser = stub_everything 'parser'
            Puppet::Parser::Parser.stubs(:new).returns(parser)

            @parser.expects(:scan_top_level)

            @parser.scan
        end

        it "should return a PuppetTopLevel to RDoc" do
            parser = stub_everything 'parser'
            Puppet::Parser::Parser.stubs(:new).returns(parser)

            @parser.expects(:scan_top_level)

            @parser.scan.should be_a(RDoc::PuppetTopLevel)
        end
    end

    describe "when scanning top level entities" do
        before :each do
            @loadedcode = stub_everything 'loadedcode'
            @parser.ast = @loadedcode
            @parser.stubs(:split_module).returns("module")

            @topcontainer = stub_everything 'topcontainer'
            @container = stub_everything 'container'
            @module = stub_everything 'module'
            @container.stubs(:add_module).returns(@module)
            @parser.stubs(:get_class_or_module).returns([@container, "module"])
        end

        it "should read any present README as module documentation" do
            FileTest.stubs(:readable?).returns(true)
            File.stubs(:open).returns("readme")
            @parser.stubs(:parse_elements)

            @module.expects(:comment=).with("readme")

            @parser.scan_top_level(@topcontainer)
        end

        it "should tell the container its module name" do
            @parser.stubs(:parse_elements)

            @topcontainer.expects(:module_name=).with("module")

            @parser.scan_top_level(@topcontainer)
        end

        it "should not document our toplevel if it isn't a valid module" do
            @parser.stubs(:split_module).returns(nil)

            @topcontainer.expects(:document_self=).with(false)
            @parser.expects(:parse_elements).never

            @parser.scan_top_level(@topcontainer)
        end

        it "should set the module as global if we parse the global manifests (ie <site> module)" do
            @parser.stubs(:split_module).returns("<site>")
            @parser.stubs(:parse_elements)

            @topcontainer.expects(:global=).with(true)

            @parser.scan_top_level(@topcontainer)
        end

        it "should attach this module container to the toplevel container" do
            @parser.stubs(:parse_elements)

            @container.expects(:add_module).with(RDoc::PuppetModule, "module").returns(@module)

            @parser.scan_top_level(@topcontainer)
        end

        it "should defer ast parsing to parse_elements for this module" do
            @parser.expects(:parse_elements).with(@module)

            @parser.scan_top_level(@topcontainer)
        end

        it "should defer plugins parsing to parse_plugins for this module" do
            @parser.input_file_name = "module/plugins/puppet/parser/function.rb"

            @parser.expects(:parse_plugins).with(@module)

            @parser.scan_top_level(@topcontainer)
        end
    end

    describe "when finding modules from filepath" do
        before :each do
            Puppet::Module.stubs(:modulepath).returns("/path/to/modules")
        end

        it "should return the module name for modulized puppet manifests" do
            File.stubs(:expand_path).returns("/path/to/module/manifests/init.pp")
            File.stubs(:identical?).with("/path/to", "/path/to/modules").returns(true)
            @parser.split_module("/path/to/modules/mymodule/manifests/init.pp").should == "module"
        end

        it "should return <site> for manifests not under module path" do
            File.stubs(:expand_path).returns("/path/to/manifests/init.pp")
            File.stubs(:identical?).returns(false)
            @parser.split_module("/path/to/manifests/init.pp").should == "<site>"
        end
    end

    describe "when parsing AST elements" do
        before :each do
            @klass = stub_everything 'klass', :file => "module/manifests/init.pp", :classname => "myclass"
            @definition = stub_everything 'definition', :file => "module/manifests/init.pp"
            @node = stub_everything 'node', :file => "module/manifests/init.pp"

            @loadedcode = Puppet::Parser::LoadedCode.new
            @parser.ast = @loadedcode

            @container = stub_everything 'container'
        end

        it "should document classes in the parsed file" do
            @loadedcode.add_hostclass("myclass", @klass)

            @parser.expects(:document_class).with("myclass", @klass, @container)

            @parser.parse_elements(@container)
        end

        it "should not document class parsed in an other file" do
            @klass.stubs(:file).returns("/not/same/path/file.pp")
            @loadedcode.add_hostclass("myclass", @klass)

            @parser.expects(:document_class).with("myclass", @klass, @container).never

            @parser.parse_elements(@container)
        end

        it "should document vardefs for the main class" do
            @loadedcode.add_hostclass(:main, @klass)

            code = stub 'code', :is_a? => false
            @klass.stubs(:classname).returns("")
            @klass.stubs(:code).returns(code)

            @parser.expects(:scan_for_vardef).with(@container, code)

            @parser.parse_elements(@container)
        end

        it "should document definitions in the parsed file" do
            @loadedcode.add_definition("mydef", @definition)

            @parser.expects(:document_define).with("mydef", @definition, @container)

            @parser.parse_elements(@container)
        end

        it "should not document definitions parsed in an other file" do
            @definition.stubs(:file).returns("/not/same/path/file.pp")
            @loadedcode.add_definition("mydef", @definition)

            @parser.expects(:document_define).with("mydef", @definition, @container).never

            @parser.parse_elements(@container)
        end

        it "should document nodes in the parsed file" do
            @loadedcode.add_node("mynode", @node)

            @parser.expects(:document_node).with("mynode", @node, @container)

            @parser.parse_elements(@container)
        end

        it "should not document node parsed in an other file" do
            @node.stubs(:file).returns("/not/same/path/file.pp")
            @loadedcode.add_node("mynode", @node)

            @parser.expects(:document_node).with("mynode", @node, @container).never

            @parser.parse_elements(@container)
        end
    end

    describe "when documenting definition" do
        before(:each) do
            @define = stub_everything 'define', :arguments => [], :doc => "mydoc"
            @class = stub_everything 'class'
            @parser.stubs(:get_class_or_module).returns([@class, "mydef"])
        end

        it "should register a RDoc method to the current container" do
            @class.expects(:add_method).with { |m| m.name == "mydef"}
            @parser.document_define("mydef", @define, @class)
        end

        it "should attach the documentation to this method" do
            @class.expects(:add_method).with { |m| m.comment = "mydoc" }

            @parser.document_define("mydef", @define, @class)
        end
    end

    describe "when documenting nodes" do
        before :each do
            @code = stub_everything 'code'
            @node = stub_everything 'node', :doc => "mydoc", :parentclass => "parent", :code => @code
            @rdoc_node = stub_everything 'rdocnode'

            @class = stub_everything 'class'
            @class.stubs(:add_node).returns(@rdoc_node)
        end

        it "should add a node to the current container" do
            @class.expects(:add_node).with("mynode", "parent").returns(@rdoc_node)
            @parser.document_node("mynode", @node, @class)
        end

        it "should associate the node documentation to the rdoc node" do
            @rdoc_node.expects(:comment=).with("mydoc")
            @parser.document_node("mynode", @node, @class)
        end

        it "should scan for include and require" do
            @parser.expects(:scan_for_include_or_require).with(@rdoc_node, @code)
            @parser.document_node("mynode", @node, @class)
        end

        it "should scan for variable definition" do
            @parser.expects(:scan_for_vardef).with(@rdoc_node, @code)
            @parser.document_node("mynode", @node, @class)
        end

        it "should scan for resources if needed" do
            Puppet.settings.stubs(:[]).with(:document_all).returns(true)
            @parser.expects(:scan_for_resource).with(@rdoc_node, @code)
            @parser.document_node("mynode", @node, @class)
        end
    end

    describe "when documenting classes" do
        before :each do
            @code = stub_everything 'code'
            @class = stub_everything 'class', :doc => "mydoc", :parentclass => "parent", :code => @code
            @rdoc_class = stub_everything 'rdoc-class'

            @module = stub_everything 'class'
            @module.stubs(:add_class).returns(@rdoc_class)
            @parser.stubs(:get_class_or_module).returns([@module, "myclass"])
        end

        it "should add a class to the current container" do
            @module.expects(:add_class).with(RDoc::PuppetClass, "myclass", "parent").returns(@rdoc_class)
            @parser.document_class("mynode", @class, @module)
        end

        it "should set the superclass" do
            @rdoc_class.expects(:superclass=).with("parent")
            @parser.document_class("mynode", @class, @module)
        end

        it "should associate the node documentation to the rdoc class" do
            @rdoc_class.expects(:comment=).with("mydoc")
            @parser.document_class("mynode", @class, @module)
        end

        it "should scan for include and require" do
            @parser.expects(:scan_for_include_or_require).with(@rdoc_class, @code)
            @parser.document_class("mynode", @class, @module)
        end

        it "should scan for resources if needed" do
            Puppet.settings.stubs(:[]).with(:document_all).returns(true)
            @parser.expects(:scan_for_resource).with(@rdoc_class, @code)
            @parser.document_class("mynode", @class, @module)
        end
    end

    describe "when scanning for includes and requires" do

        def create_stmt(name)
            stmt_value = stub "#{name}_value", :value => "myclass"
            stmt = stub_everything 'stmt', :name => name, :arguments => [stmt_value], :doc => "mydoc"
            stmt.stubs(:is_a?).with(Puppet::Parser::AST::ASTArray).returns(false)
            stmt.stubs(:is_a?).with(Puppet::Parser::AST::Function).returns(true)
            stmt
        end

        before(:each) do
            @class = stub_everything 'class'
            @code = stub_everything 'code'
            @code.stubs(:is_a?).with(Puppet::Parser::AST::ASTArray).returns(true)
        end

        it "should register recursively includes to the current container" do
            @code.stubs(:children).returns([ create_stmt("include") ])

            @class.expects(:add_include).with { |i| i.is_a?(RDoc::Include) and i.name == "myclass" and i.comment == "mydoc" }
            @parser.scan_for_include_or_require(@class, [@code])
        end

        it "should register requires to the current container" do
            @code.stubs(:children).returns([ create_stmt("require") ])

            @class.expects(:add_require).with { |i| i.is_a?(RDoc::Include) and i.name == "myclass" and i.comment == "mydoc" }
            @parser.scan_for_include_or_require(@class, [@code])
        end
    end

    describe "when scanning for variable definition" do
        before :each do
            @class = stub_everything 'class'

            @stmt = stub_everything 'stmt', :name => "myvar", :value => "myvalue", :doc => "mydoc"
            @stmt.stubs(:is_a?).with(Puppet::Parser::AST::ASTArray).returns(false)
            @stmt.stubs(:is_a?).with(Puppet::Parser::AST::VarDef).returns(true)

            @code = stub_everything 'code'
            @code.stubs(:is_a?).with(Puppet::Parser::AST::ASTArray).returns(true)
        end

        it "should recursively register variables to the current container" do
            @code.stubs(:children).returns([ @stmt ])

            @class.expects(:add_constant).with { |i| i.is_a?(RDoc::Constant) and i.name == "myvar" and i.comment == "mydoc" }
            @parser.scan_for_vardef(@class, [ @code ])
        end
    end

    describe "when scanning for resources" do
        before :each do
            @class = stub_everything 'class'

            param = stub 'params', :children => []
            @stmt = stub_everything 'stmt', :type => "File", :title => "myfile", :doc => "mydoc", :params => param
            @stmt.stubs(:is_a?).with(Puppet::Parser::AST::ASTArray).returns(false)
            @stmt.stubs(:is_a?).with(Puppet::Parser::AST::Resource).returns(true)

            @code = stub_everything 'code'
            @code.stubs(:is_a?).with(Puppet::Parser::AST::ASTArray).returns(true)
        end

        it "should register a PuppetResource to the current container" do
            @code.stubs(:children).returns([ @stmt ])

            @class.expects(:add_resource).with { |i| i.is_a?(RDoc::PuppetResource) and i.title == "myfile" and i.comment == "mydoc" }
            @parser.scan_for_resource(@class, [ @code ])
        end
    end

    describe "when parsing plugins" do
        before :each do
            @container = stub 'container'
        end

        it "should delegate parsing custom facts to parse_facts" do
            @parser = RDoc::Parser.new(@top_level, "module/manifests/plugins/puppet/facter/test.rb", nil, Options.instance, RDoc::Stats.new)

            @parser.expects(:parse_fact).with(@container)
            @parser.parse_plugins(@container)
        end

        it "should delegate parsing plugins to parse_plugins" do
            @parser = RDoc::Parser.new(@top_level, "module/manifests/plugins/puppet/functions/test.rb", nil, Options.instance, RDoc::Stats.new)

            @parser.expects(:parse_puppet_plugin).with(@container)
            @parser.parse_plugins(@container)
        end
    end

    describe "when parsing plugins" do
        before :each do
            @container = stub_everything 'container'
        end

        it "should add custom functions to the container" do
            File.stubs(:open).yields("# documentation
            module Puppet::Parser::Functions
            	newfunction(:myfunc, :type => :rvalue) do |args|
            		File.dirname(args[0])
            	end
            end".split("\n"))

            @container.expects(:add_plugin).with do |plugin|
                plugin.comment == "documentation\n" #and
                plugin.name == "myfunc"
            end

            @parser.parse_puppet_plugin(@container)
        end

        it "should add custom types to the container" do
            File.stubs(:open).yields("# documentation
            Puppet::Type.newtype(:mytype) do
            end".split("\n"))

            @container.expects(:add_plugin).with do |plugin|
                plugin.comment == "documentation\n" #and
                plugin.name == "mytype"
            end

            @parser.parse_puppet_plugin(@container)
        end
    end

    describe "when parsing facts" do
        before :each do
            @container = stub_everything 'container'
            File.stubs(:open).yields(["# documentation", "Facter.add('myfact') do", "confine :kernel => :linux", "end"])
        end

        it "should add facts to the container" do
            @container.expects(:add_fact).with do |fact|
                fact.comment == "documentation\n" and
                fact.name == "myfact"
            end

            @parser.parse_fact(@container)
        end

        it "should add confine to the parsed facts" do
            ourfact = nil
            @container.expects(:add_fact).with do |fact|
                ourfact = fact
                true
            end

            @parser.parse_fact(@container)
            ourfact.confine.should == { :type => "kernel", :value => ":linux" }
        end
    end
end
