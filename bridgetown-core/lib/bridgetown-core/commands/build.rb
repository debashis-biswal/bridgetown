# frozen_string_literal: true

module Bridgetown
  module Commands
    class Build < Thor::Group
      extend BuildOptions
      extend Summarizable
      include ConfigurationOverridable

      Registrations.register do
        register(Build, "build", "build", Build.summary)
      end

      def self.banner
        "bridgetown build [options]"
      end
      summary "Build your site and save to destination folder"

      class_option :watch,
                   type: :boolean,
                   aliases: "-w",
                   desc: "Watch for changes and rebuild"

      def self.print_startup_message
        Bridgetown.logger.info "Starting:", "Bridgetown v#{Bridgetown::VERSION.magenta}" \
                               " (codename \"#{Bridgetown::CODE_NAME.yellow}\")"
      end

      # Build your bridgetown site
      # Continuously watch if `watch` is set to true in the config.
      def build
        Bridgetown.logger.adjust_verbosity(options)

        unless caller_locations.find do |loc|
          loc.to_s.include?("bridgetown-core/commands/start.rb")
        end
          self.class.print_startup_message
        end

        config_options = (
          Bridgetown::Current.preloaded_configuration || configuration_with_overrides(options)
        ).merge(options)

        config_options["serving"] = false unless config_options["serving"]
        @site = Bridgetown::Site.new(config_options)

        if config_options.fetch("skip_initial_build", false)
          Bridgetown.logger.warn "Build Warning:", "Skipping the initial build." \
                                 " This may result in an out-of-date site."
        else
          build_site(config_options)
        end

        if config_options.fetch("detach", false)
          Bridgetown.logger.info "Auto-regeneration:",
                                 "disabled when running server detached."
        elsif config_options.fetch("watch", false)
          watch_site(config_options)
        else
          Bridgetown.logger.info "Auto-regeneration:", "disabled. Use --watch to enable."
        end
      end

      protected

      # Build your Bridgetown site.
      #
      # options - A Hash of options passed to the command or loaded from config
      #
      # Returns nothing.
      def build_site(config_options)
        t = Time.now
        display_folder_paths(config_options)
        if config_options["unpublished"]
          Bridgetown.logger.info "Unpublished mode:",
                                 "enabled. Processing documents marked unpublished"
        end
        Bridgetown.logger.info "Generating…"
        @site.process
        Bridgetown.logger.info "Done! 🎉", "#{"Completed".green} in less than" \
                                " #{(Time.now - t).ceil(2)} seconds."
        if config_options[:using_puma]
          require "socket"
          external_ip = Socket.ip_address_list.find do |ai|
            ai.ipv4? && !ai.ipv4_loopback?
          end&.ip_address
          scheme = config_options.bind&.split("://")&.first == "ssl" ? "https" : "http"
          port = config_options.bind&.split(":")&.last || ENV["BRIDGETOWN_PORT"] || 4000
          Bridgetown.logger.info ""
          Bridgetown.logger.info "Now serving at:", "#{scheme}://localhost:#{port}".magenta
          Bridgetown.logger.info "", "#{scheme}://#{external_ip}:#{port}".magenta if external_ip
          Bridgetown.logger.info ""
        end
      end

      # Watch for file changes and rebuild the site.
      #
      # options - A Hash of options passed to the command or loaded from config
      #
      # Returns nothing.
      def watch_site(config_options)
        Bridgetown::Watcher.watch(@site, config_options)
      end

      # Display the source and destination folder paths
      #
      # options - A Hash of options passed to the command
      #
      # Returns nothing.
      def display_folder_paths(config_options)
        source = File.expand_path(config_options["source"])
        destination = File.expand_path(config_options["destination"])
        Bridgetown.logger.info "Environment:", Bridgetown.environment.cyan
        Bridgetown.logger.info "Source:", source
        Bridgetown.logger.info "Destination:", destination
        # TODO: work with arrays
        if config_options["plugins_dir"].is_a?(String)
          plugins_dir = File.expand_path(config_options["plugins_dir"])
          Bridgetown.logger.info "Custom Plugins:", plugins_dir if Dir.exist?(plugins_dir)
        end
      end
    end
  end
end
