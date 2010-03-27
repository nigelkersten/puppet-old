#!/usr/bin/env ruby

Dir.chdir(File.dirname(__FILE__)) { (s = lambda { |f| File.exist?(f) ? require(f) : Dir.chdir("..") { s.call(f) } }).call("spec/spec_helper.rb") }

require 'puppet/util/autoload'

describe Puppet::Util::Autoload do
    before do
        @autoload = Puppet::Util::Autoload.new("foo", "tmp")

        @autoload.stubs(:eachdir).yields "/my/dir"
    end

    it "should use the Cacher module" do
        Puppet::Util::Autoload.ancestors.should be_include(Puppet::Util::Cacher)
    end

    it "should use a ttl of 15 for the search path" do
        Puppet::Util::Autoload.attr_ttl(:searchpath).should == 15
    end

    describe "when building the search path" do
        it "should collect all of the plugins and lib directories that exist in the current environment's module path" do
            Puppet.settings.expects(:value).with(:environment).returns "foo"
            Puppet.settings.expects(:value).with(:modulepath, :foo).returns "/a:/b:/c"
            Dir.expects(:entries).with("/a").returns %w{one two}
            Dir.expects(:entries).with("/b").returns %w{one two}

            FileTest.stubs(:directory?).returns false
            FileTest.expects(:directory?).with("/a").returns true
            FileTest.expects(:directory?).with("/b").returns true
            %w{/a/one/plugins /a/two/lib /b/one/plugins /b/two/lib}.each do |d|
                FileTest.expects(:directory?).with(d).returns true
            end

            @autoload.module_directories.should == %w{/a/one/plugins /a/two/lib /b/one/plugins /b/two/lib}
        end

        it "should not look for lib directories in directories starting with '.'" do
            Puppet.settings.expects(:value).with(:environment).returns "foo"
            Puppet.settings.expects(:value).with(:modulepath, :foo).returns "/a"
            Dir.expects(:entries).with("/a").returns %w{. ..}

            FileTest.expects(:directory?).with("/a").returns true
            FileTest.expects(:directory?).with("/a/./lib").never
            FileTest.expects(:directory?).with("/a/./plugins").never
            FileTest.expects(:directory?).with("/a/../lib").never
            FileTest.expects(:directory?).with("/a/../plugins").never

            @autoload.module_directories
        end

        it "should include the module directories, the Puppet libdir, and all of the Ruby load directories" do
            Puppet.stubs(:[]).with(:libdir).returns(%w{/libdir1 /lib/dir/two /third/lib/dir}.join(File::PATH_SEPARATOR))
            @autoload.expects(:module_directories).returns %w{/one /two}
            @autoload.search_directories.should == %w{/one /two /libdir1 /lib/dir/two /third/lib/dir} + $:
        end

        it "should include in its search path all of the search directories that have a subdirectory matching the autoload path" do
            @autoload = Puppet::Util::Autoload.new("foo", "loaddir")
            @autoload.expects(:search_directories).returns %w{/one /two /three}
            FileTest.expects(:directory?).with("/one/loaddir").returns true
            FileTest.expects(:directory?).with("/two/loaddir").returns false
            FileTest.expects(:directory?).with("/three/loaddir").returns true
            @autoload.searchpath.should == ["/one/loaddir", "/three/loaddir"]
        end
    end

    it "should include its FileCache module" do
        Puppet::Util::Autoload.ancestors.should be_include(Puppet::Util::Autoload::FileCache)
    end

    describe "when loading a file" do
        before do
            @autoload.stubs(:searchpath).returns %w{/a}
        end

        [RuntimeError, LoadError, SyntaxError].each do |error|
            it "should not die an if a #{error.to_s} exception is thrown" do
                @autoload.stubs(:file_exist?).returns true

                Kernel.expects(:load).raises error

                @autoload.load("foo")
            end
        end

        it "should skip files that it knows are missing" do
            @autoload.expects(:named_file_missing?).with("foo").returns true
            @autoload.expects(:eachdir).never

            @autoload.load("foo")
        end

        it "should register that files are missing if they cannot be found" do
            @autoload.load("foo")

            @autoload.should be_named_file_missing("foo")
        end

        it "should register loaded files with the main loaded file list so they are not reloaded by ruby" do
            @autoload.stubs(:file_exist?).returns true
            Kernel.stubs(:load)

            @autoload.load("myfile")

            $".should be_include("tmp/myfile.rb")
        end
    end

    describe "when loading all files" do
        before do
            @autoload.stubs(:searchpath).returns %w{/a}
            Dir.stubs(:glob).returns "/path/to/file.rb"

            @autoload.class.stubs(:loaded?).returns(false)
        end

        [RuntimeError, LoadError, SyntaxError].each do |error|
            it "should not die an if a #{error.to_s} exception is thrown" do
                Kernel.expects(:require).raises error

                lambda { @autoload.loadall }.should_not raise_error
            end
        end

        it "should require the full path to the file" do
            Kernel.expects(:require).with("/path/to/file.rb")

            @autoload.loadall
        end
    end
end
