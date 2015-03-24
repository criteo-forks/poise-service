#
# Copyright 2015, Noah Kantrowitz
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# Used in the template.
require 'shellwords'

require 'chef/mixin/shell_out'

require 'poise_service/error'
require 'poise_service/providers/base'

module PoiseService
  module Providers
    class Upstart < Base
      include Chef::Mixin::ShellOut
      poise_service_provides(:upstart)

      def self.provides_auto?(node, resource)
        # Don't allow upstart under docker, it won't work.
        return false if node['virtualization'] && %w{docker lxc}.include?(node['virtualization']['system'])
        service_resource_hints.include?(:upstart)
      end

      def pid
        cmd = shell_out(%w{initctl status} + [new_resource.service_name])
        if !cmd.error? && md = cmd.stdout.match(/process (\d+)/)
          md[1].to_i
        else
          nil
        end
      end

      private

      def service_resource
        super.tap do |r|
          r.provider(Chef::Provider::Service::Upstart)
        end
      end

      def create_service
        features = upstart_features
        if !features[:reload_signal] && new_resource.reload_signal != 'HUP'
          raise Error.new("Upstart #{upstart_version} only supports HUP for reload, cannot use #{new_resource.reload_signal} for #{new_resource.to_s}")
        end
        service_template("/etc/init/#{new_resource.service_name}.conf", 'upstart.conf.erb') do
          variables.update(
            upstart_features: features,
            pid_file: options['pid_file'],
          )
        end
      end

      def destroy_service
        file "/etc/init/#{new_resource.service_name}.conf" do
          action :delete
        end
      end

      def upstart_version
        cmd = shell_out(%w{initctl --version})
        if !cmd.error? && md = cmd.stdout.match(/upstart ([^)]+)\)/)
          md[1]
        else
          '0'
        end
      end

      def upstart_features
        upstart_ver = Gem::Version.new(upstart_version)
        versions_added = {
          kill_signal: '1.3',
          reload_signal: '1.10',
          setuid: '1.4',
        }
        versions_added.inject({}) do |memo, (feature, version)|
          memo[feature] = Gem::Requirement.create(">= #{version}").satisfied_by?(upstart_ver)
          memo
        end
      end

    end
  end
end
