require 'chef/knife'

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

      def run
        begin
          if config[:node]
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

          environment_cookbook_versions = Chef::Environment.load(environment).cookbook_versions

          run_list_expansion = node.expand!
          expanded_run_list_with_versions = run_list_expansion.recipes.with_version_constraints_strings

          depsolver_start_time = Time.now

          ckbks = rest.post_rest("environments/" + node.chef_environment + "/cookbook_versions", { "run_list" => expanded_run_list_with_versions })

          depsolver_finish_time = Time.now

          depsolver_results = {}
          ckbks.each do |name, ckbk|
            version = ckbk.is_a?(Hash) ? ckbk['version'] : ckbk.version
            depsolver_results[name] = version
          end

        rescue => e
          api_error = {}
          api_error[:error_code] = e.response.code
          api_error[:error_message] = e.response.message
          begin
            api_error[:error_body] = JSON.parse(e.response.body)
          rescue JSON::ParserError
          end
        ensure
          results = {}
          results[:node] = node.name unless node.nil? || node.name.nil?
          results[:environment] = node.chef_environment unless node.chef_environment.nil?
          results[:environment_cookbook_versions] = environment_cookbook_versions unless environment_cookbook_versions.nil?
          results[:run_list] = node.run_list unless node.nil? || node.run_list.nil?
          results[:expanded_run_list] = expanded_run_list_with_versions unless expanded_run_list_with_versions.nil?
          results[:depsolver_results] = depsolver_results unless depsolver_results.nil? || depsolver_results.empty?
          results[:depsolver_cookbook_count] = ckbks.count unless ckbks.nil?
          results[:depsolver_elapsed_ms] = ((depsolver_finish_time - depsolver_start_time) * 1000).to_i unless depsolver_finish_time.nil?
          results[:api_error] = api_error unless api_error.nil?

          msg(JSON.pretty_generate(results))
        end
      end
    end
  end
end
