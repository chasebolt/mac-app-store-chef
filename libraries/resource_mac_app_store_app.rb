# Encoding: UTF-8
#
# Cookbook Name:: mac-app-store
# Library:: resource_mac_app_store_app
#
# Copyright 2015-2016, Jonathan Hartman
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'etc'
require 'chef/resource'
require_relative 'helpers_app'

class Chef
  class Resource
    # A Chef resource for Mac App Store applications.
    #
    # @author Jonathan Hartman <j@p4nt5.com>
    class MacAppStoreApp < Resource
      include Chef::Mixin::ShellOut

      provides :mac_app_store_app, platform_family: 'mac_os_x'

      #
      # The name of the app to be installed (defaults to the resource name).
      #
      property :app_name, String, name_property: true

      #
      # The system user to execute Mas commands as.
      #
      property :system_user, String, default: Etc.getlogin, desired_state: false

      #
      # If circumstances require, the reattach-to-user-namespace utility can be
      # used every time we shell out to Mas.
      #
      property :use_rtun, [TrueClass, FalseClass], default: false

      ######################################################################
      # Every property below this point is for tracking resource state and #
      # should *not* be overridden.                                        #
      ######################################################################

      #
      # A state property for whether the app is installed.
      #
      property :installed, [TrueClass, FalseClass]

      #
      # A state property for whether an upgrade is available.
      #
      property :upgradable, [TrueClass, FalseClass], desired_state: false

      default_action :install

      load_current_value do |desired|
        MacAppStore::Helpers::App.user = desired.system_user
        installed(MacAppStore::Helpers::App.installed?(desired.app_name))
        upgradable(MacAppStore::Helpers::App.upgradable?(desired.app_name))
      end

      action :install do
        new_resource.installed(true)
        MacAppStore::Helpers::App.user = new_resource.system_user

        converge_if_changed :installed do
          app_id = MacAppStore::Helpers::App.app_id_for?(new_resource.app_name)
          raise(Exceptions::InvalidAppName, new_resource.app_name) unless app_id

          cmd = if new_resource.use_rtun
                  include_recipe 'reattach-to-user-namespace'
                  "reattach-to-user-namespace mas install #{app_id}"
                else
                  "mas install #{app_id}"
                end
          execute "Install #{new_resource.app_name} with Mas" do
            command cmd
            user new_resource.system_user
          end
        end
      end

      action :upgrade do
        new_resource.installed(true)
        new_resource.upgradable(false)
        MacAppStore::Helpers::App.user = new_resource.system_user

        converge_if_changed :installed, :upgradable do
          app_id = MacAppStore::Helpers::App.app_id_for?(new_resource.app_name)
          raise(Exceptions::InvalidAppName, new_resource.app_name) unless app_id

          cmd = if new_resource.use_rtun
                  include_recipe 'reattach-to-user-namespace'
                  "reattach-to-user-namespace mas install #{app_id}"
                else
                  "mas install #{app_id}"
                end
          execute "Upgrade #{new_resource.app_name} with Mas" do
            command cmd
            user new_resource.system_user
          end
        end
      end

      class Exceptions
        # An exception class for app names that don't turn up in `mas search`.
        #
        # @author Jonathan Hartman <j@p4nt5.com>
        class InvalidAppName < StandardError
          def initialize(app_name)
            super("Could not find '#{app_name}' in the Mac App Store. " \
                  'Is the name correct and do you own the app?')
          end
        end
      end
    end
  end
end
