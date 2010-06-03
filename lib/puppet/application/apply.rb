require 'puppet'
require 'puppet/application'
require 'puppet/configurer'
require 'puppet/network/handler'
require 'puppet/network/client'

class Puppet::Application::Apply < Puppet::Application

    should_parse_config

    option("--debug","-d")
    option("--execute EXECUTE","-e") do |arg|
        options[:code] = arg
    end
    option("--loadclasses","-L")
    option("--verbose","-v")
    option("--use-nodes")
    option("--detailed-exitcodes")

    option("--apply catalog",  "-a catalog") do |arg|
        options[:catalog] = arg
    end

    option("--logdest LOGDEST", "-l") do |arg|
        begin
            Puppet::Util::Log.newdestination(arg)
            options[:logset] = true
        rescue => detail
            $stderr.puts detail.to_s
        end
    end

    def run_command
        if options[:catalog]
            apply
        elsif Puppet[:parseonly]
            parseonly
        else
            main
        end
    end

    def apply
        require 'puppet/configurer'

        if options[:catalog] == "-"
            text = $stdin.read
        else
            text = File.read(options[:catalog])
        end

        begin
            catalog = Puppet::Resource::Catalog.convert_from(Puppet::Resource::Catalog.default_format,text)
            unless catalog.is_a?(Puppet::Resource::Catalog)
                catalog = Puppet::Resource::Catalog.pson_create(catalog)
            end
        rescue => detail
            raise Puppet::Error, "Could not deserialize catalog from pson: %s" % detail
        end

        catalog = catalog.to_ral

        configurer = Puppet::Configurer.new
        configurer.run :catalog => catalog
    end

    def parseonly
        # Set our code or file to use.
        if options[:code] or command_line.args.length == 0
            Puppet[:code] = options[:code] || STDIN.read
        else
            Puppet[:manifest] = command_line.args.shift
        end
        begin
            Puppet::Resource::TypeCollection.new(Puppet[:environment]).perform_initial_import
        rescue => detail
            Puppet.err detail
            exit 1
        end
        exit 0
    end

    def main
        # Set our code or file to use.
        if options[:code] or command_line.args.length == 0
            Puppet[:code] = options[:code] || STDIN.read
        else
            Puppet[:manifest] = command_line.args.shift
        end

        # Collect our facts.
        unless facts = Puppet::Node::Facts.find(Puppet[:certname])
            raise "Could not find facts for %s" % Puppet[:certname]
        end

        # Find our Node
        unless node = Puppet::Node.find(Puppet[:certname])
            raise "Could not find node %s" % Puppet[:certname]
        end

        # Merge in the facts.
        node.merge(facts.values)

        # Allow users to load the classes that puppetd creates.
        if options[:loadclasses]
            file = Puppet[:classfile]
            if FileTest.exists?(file)
                unless FileTest.readable?(file)
                    $stderr.puts "%s is not readable" % file
                    exit(63)
                end
                node.classes = File.read(file).split(/[\s\n]+/)
            end
        end

        begin
            # Compile our catalog
            starttime = Time.now
            catalog = Puppet::Resource::Catalog.find(node.name, :use_node => node)

            # Translate it to a RAL catalog
            catalog = catalog.to_ral

            catalog.host_config = true if Puppet[:graph] or Puppet[:report]

            catalog.finalize

            catalog.retrieval_duration = Time.now - starttime

            configurer = Puppet::Configurer.new
            configurer.execute_prerun_command

            # And apply it
            transaction = catalog.apply

            configurer.execute_postrun_command

            status = 0
            if not Puppet[:noop] and options[:detailed_exitcodes] then
                transaction.generate_report
                exit(transaction.report.exit_status)
            else
                exit(0)
            end
        rescue => detail
            puts detail.backtrace if Puppet[:trace]
            if detail.is_a?(XMLRPC::FaultException)
                $stderr.puts detail.message
            else
                $stderr.puts detail
            end
            exit(1)
        end
    end

    def setup
        if Puppet.settings.print_configs?
            exit(Puppet.settings.print_configs ? 0 : 1)
        end

        # If noop is set, then also enable diffs
        if Puppet[:noop]
            Puppet[:show_diff] = true
        end

        unless options[:logset]
            Puppet::Util::Log.newdestination(:console)
        end
        client = nil
        server = nil

        trap(:INT) do
            $stderr.puts "Exiting"
            exit(1)
        end

        if options[:debug]
            Puppet::Util::Log.level = :debug
        elsif options[:verbose]
            Puppet::Util::Log.level = :info
        end
    end
end
