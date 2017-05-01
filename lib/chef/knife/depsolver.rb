require 'chef/knife'
require 'digest'

class Chef
  class Knife
    class Depsolver < Knife
      deps do
      end

      banner 'knife depsolver RUN_LIST'

      option :node,
             short: '-n',
             long: '--node NAME',
             description: 'Use the run list from a given node'

      option :timeout,
             short: '-t',
             long: '--timeout SECONDS',
             description: 'Set the local depsolver timeout. Only valid when using the --env-constraints and --universe options'

      option :capture,
             long: '--capture',
             description: 'Save the expanded run list, environment cookbook constraints and cookbook universe to files for local depsolving'

      option :env_constraints,
             long: '--env-constraints FILENAME',
             description: 'Use the environment cookbook constraints from FILENAME. The local depsolver will automatically be used'

      option :universe,
             long: '--universe FILENAME',
             description: 'Use the cookbook universe from FILENAME. The local depsolver will automatically be used'

      option :csv_universe_to_json,
             long: '--csv-universe-to-json FILENAME',
             description: 'Convert a CSV cookbook universe, FILENAME, to JSON.'

      option :env_constraints_filter_universe,
           long: '--env-constraints-filter-universe',
           description: 'Filter the cookbook universe using the environment cookbook version constraints.'

      def run
        begin
          if config[:capture] && (config[:env_constraints] || config[:universe])
            puts "ERROR: The --capture option is not compatible with the --env-constraints or --universe options"
            exit!
          elsif config[:env_constraints] && !config[:universe]
            puts "ERROR: The --env-constraints option requires the --universe option to be set"
            exit!
          elsif !config[:env_constraints] && config[:universe]
            puts "ERROR: The --universe option requires the --env-constraints option to be set"
            exit!
          elsif config[:env_constraints_filter_universe] && !(config[:env_constraints] && config[:universe])
            msg("ERROR: The --env-constraints-filter-universe option requires the --env-constraints and --universe options to be set")
            exit!
          end

          if config[:csv_universe_to_json]
            unless File.file?(config[:csv_universe_to_json])
              msg("ERROR: #{config[:csv_universe_to_json]} does not exist or is not a file.")
              exit!
            end
            universe = Hash.new { |hash, key| hash[key] = Hash.new }
            IO.foreach(config[:csv_universe_to_json]) do |line|
              name, version, updated_at, dependencies = line.split(",", 4)
              universe[name][version] = {updated_at: updated_at, dependencies: JSON.parse(dependencies)}
            end

            universe_json = JSON.pretty_generate(universe)
            universe_filename = "universe-#{Time.now.strftime("%Y%m%d%H%M%S")}-#{Digest::SHA1.hexdigest(universe_json)}.txt"
            IO.write(universe_filename, universe_json)
            puts "Cookbook universe saved to #{universe_filename}"
            exit!
          end

          use_local_depsolver = config[:local_depsolver] || config[:env_constraints] || config[:universe]
          timeout = 5000
          if config[:timeout]
            if use_local_depsolver
              timeout = (config[:timeout].to_f * 1000).to_i
            else
              msg("ERROR: The --timeout option is only compatible with the --local-depsolver, --env-constraints or --universe options")
              exit!
            end
          end

          if config[:node] && !(config[:env_constraints_filter_universe] && config[:env_constraints])
            node = Chef::Node.load(config[:node])
          else
            node = Chef::Node.new
            node.name('depsolver-tmp-node')

            run_list = name_args.map {|item| item.to_s.split(/,/) }.flatten.each{|item| item.strip! }
            run_list.delete_if {|item| item.empty? }

            run_list.each do |arg|
              node.run_list.add(arg)
            end
          end

          node.chef_environment = config[:environment] if config[:environment]

          if config[:capture]
            if node.chef_environment == '_default'
              environment_cookbook_versions = Hash.new
            else
              environment_cookbook_versions = Chef::Environment.load(node.chef_environment).cookbook_versions
            end
            env = { name: node.chef_environment, cookbook_versions: environment_cookbook_versions }
            environment_constraints_json = JSON.pretty_generate(env)
            environment_constraints_filename = "#{node.chef_environment}-environment-#{Time.now.strftime("%Y%m%d%H%M%S")}-#{Digest::SHA1.hexdigest(environment_constraints_json)}.txt"
            IO.write(environment_constraints_filename, environment_constraints_json)
            puts "Environment constraints saved to #{environment_constraints_filename}"

            begin
              universe = rest.get_rest("universe")
              universe_json = JSON.pretty_generate(universe)
              universe_filename = ""
              rest.url.to_s.match(".*/organizations/(.*)/?") { universe_filename = "#{$1}-" }
              universe_filename += "universe-#{Time.now.strftime("%Y%m%d%H%M%S")}-#{Digest::SHA1.hexdigest(universe_json)}.txt"
              IO.write(universe_filename, universe_json)
              puts "Cookbook universe saved to #{universe_filename}"
            rescue Net::HTTPServerException
              puts "WARNING: The cookbook universe API endpoint is not available."
              puts "WARNING: Try capturing the cookbook universe using the SQL query found in the knife-depsolver README."
              puts "WARNING: Then convert the results using knife-depsolver's --csv-universe-to-json option"
            end
          end

          if config[:env_constraints] && config[:universe]
            unless File.file?(config[:env_constraints])
              msg("ERROR: #{config[:env_constraints]} does not exist or is not a file.")
              exit!
            end
            env = JSON.parse(IO.read(config[:env_constraints]))
            if env['name'].to_s.empty?
              msg("ERROR: #{config[:env_constraints]} does not contain an environment name.")
              exit!
            else
              node.chef_environment = env['name']
            end
            if !env['cookbook_versions'].is_a?(Hash)
              msg("ERROR: #{config[:env_constraints]} does not contain a Hash of cookbook version constraints.")
              exit!
            else
              environment_cookbook_versions = env['cookbook_versions']
            end

            unless File.file?(config[:universe])
              msg("ERROR: #{config[:universe]} does not exist or is not a file.")
              exit!
            end
            universe = JSON.parse(IO.read(config[:universe]))
            if !universe.is_a?(Hash)
              msg("ERROR: #{config[:universe]} does not contain a cookbook universe Hash.")
              exit!
            end
          end

          if config[:env_constraints_filter_universe]
            env_constraints = environment_cookbook_versions.each_with_object({}) do |env_constraint, memo|
              name, constraint = env_constraint
              constraint, version = constraint.split
              memo[name] = DepSelector::VersionConstraint.new(constraint_to_str(constraint, version))
            end
            universe.each do |name, versions|
              versions.delete_if {|version, v| !env_constraints[name].include?(version)} if env_constraints[name]
            end
            filtered_universe_json = JSON.pretty_generate(universe)
            filtered_universe_filename = "filtered-universe-#{Time.now.strftime("%Y%m%d%H%M%S")}-#{Digest::SHA1.hexdigest(filtered_universe_json)}.txt"
            IO.write(filtered_universe_filename, filtered_universe_json)
            puts "Filtered cookbook universe saved to #{filtered_universe_filename}"
            exit!
          end

          run_list_expansion = node.run_list.expand(node.chef_environment, 'server')
          expanded_run_list_with_versions = run_list_expansion.recipes.with_version_constraints_strings

          exit if config[:capture]

          depsolver_results = Hash.new
          if config[:env_constraints] && config[:universe]
            env_ckbk_constraints = environment_cookbook_versions.map do |ckbk_name, ckbk_constraint|
              [ckbk_name, ckbk_constraint.split.reverse].flatten
            end

            all_versions = universe.map do |ckbk_name, ckbk_metadata|
              ckbk_versions = ckbk_metadata.map do |version, version_metadata|
                [version, version_metadata['dependencies'].map { |dep_ckbk_name, dep_ckbk_constraint| [dep_ckbk_name, dep_ckbk_constraint.split.reverse].flatten }]
              end
              [ckbk_name, ckbk_versions]
            end

            expanded_run_list_with_split_versions = expanded_run_list_with_versions.map do |run_list_item|
              name, version = run_list_item.split('@')
              name.sub!(/::.*/, '')
              version ? [name, version] : name
            end

            data = {environment_constraints: env_ckbk_constraints, all_versions: all_versions, run_list: expanded_run_list_with_split_versions, timeout_ms: timeout}

            depsolver_start_time = Time.now

            solution = solve(data)

            depsolver_finish_time = Time.now

            if solution.first == :ok
              solution.last.map { |ckbk| ckbk_name, ckbk_version = ckbk; depsolver_results[ckbk_name] = ckbk_version.join('.') }
            else
              status, error_type, error_detail = solution
              depsolver_error = { error_type => error_detail }
            end
          else
            begin
              chef_server_version = rest.get(server_url.sub(/organizations.*/, 'version')).split("\n")[0]
            rescue Net::HTTPServerException
              chef_server_version = "unknown"
            end

            depsolver_start_time = Time.now

            ckbks = rest.post_rest("environments/" + node.chef_environment + "/cookbook_versions", { "run_list" => expanded_run_list_with_versions })

            depsolver_finish_time = Time.now

            ckbks.each do |name, ckbk|
              version = ckbk.is_a?(Hash) ? ckbk['version'] : ckbk.version
              depsolver_results[name] = version
            end
          end
        rescue Net::HTTPServerException => e
          api_error = {}
          api_error[:error_code] = e.response.code
          api_error[:error_message] = e.response.message
          begin
            api_error[:error_body] = JSON.parse(e.response.body)
          rescue JSON::ParserError
          end
        rescue => e
          msg("ERROR: #{e.message}")
          exit!
        ensure
          local_software = Hash.new
          %w(chef-dk chef dep_selector).each do |gem_name|
            begin
              local_software[gem_name] = Gem::Specification.find_by_name(gem_name).version
            rescue Gem::MissingSpecError
            end
          end

          results = {}
          results[:local_software] = local_software unless local_software.empty?
          if config[:env_constraints] && config[:universe]
            results[:depsolver] = "used local depsolver"
          else
            results[:depsolver] = {"used chef server" => chef_server_version} unless chef_server_version.nil?
          end
          results[:node] = node.name unless node.nil? || node.name.nil?
          results[:environment] = node.chef_environment unless node.chef_environment.nil?
          results[:run_list] = node.run_list unless node.nil? || node.run_list.nil?
          results[:expanded_run_list] = expanded_run_list_with_versions unless expanded_run_list_with_versions.nil?
          results[:depsolver_results] = depsolver_results unless depsolver_results.nil? || depsolver_results.empty?
          results[:depsolver_cookbook_count] = depsolver_results.count unless depsolver_results.nil? || depsolver_results.empty?
          results[:depsolver_elapsed_ms] = ((depsolver_finish_time - depsolver_start_time) * 1000).to_i unless depsolver_finish_time.nil?
          results[:depsolver_error] = depsolver_error unless depsolver_error.nil?
          results[:api_error] = api_error unless api_error.nil?

          if config[:capture]
            results_json = JSON.pretty_generate(results)
            expanded_run_list_filename = "expanded-run-list-#{Time.now.strftime("%Y%m%d%H%M%S")}-#{Digest::SHA1.hexdigest(results_json)}.txt"
            IO.write(expanded_run_list_filename, results_json)
            puts "Expanded run list saved to #{expanded_run_list_filename}"
          else
            msg(JSON.pretty_generate(results))
          end
        end
      end
    end
  end
end
