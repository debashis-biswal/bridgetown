# frozen_string_literal: true

module Bridgetown
  # This class handles custom defaults for YAML frontmatter variables.
  # It is exposed via the frontmatter_defaults method on the site class.
  # TODO: needs simplification/refactoring.
  class FrontmatterDefaults
    # @return [Bridgetown::Site]
    attr_reader :site

    def initialize(site)
      @site = site
    end

    def reset
      @glob_cache = {}
    end

    def update_deprecated_types(set)
      return set unless set.key?("scope") && set["scope"].key?("type")

      set["scope"]["type"] =
        case set["scope"]["type"]
        when "page"
          Deprecator.defaults_deprecate_type("page", "pages")
          "pages"
        when "post"
          Deprecator.defaults_deprecate_type("post", "posts")
          "posts"
        else
          set["scope"]["type"]
        end

      set
    end

    def ensure_time!(set)
      return set unless set.key?("values") && set["values"].key?("date")
      return set if set["values"]["date"].is_a?(Time)

      set["values"]["date"] = Utils.parse_date(
        set["values"]["date"],
        "An invalid date format was found in a front-matter default set: #{set}"
      )
      set
    end

    # TODO: deprecated. See `all` method instead
    #
    # path - the path (relative to the source) of the page or
    # post the default is used in
    # type - a symbol indicating whether a :page,
    # a :post calls this method
    #
    # Returns the default value or nil if none was found
    def find(path, type, setting)
      merged_data = {}
      merge_data_cascade_for_path(path, merged_data)
      return merged_data[setting] if merged_data.key?(setting)

      value = nil
      old_scope = nil

      matching_sets(path, type).each do |set|
        if set["values"].key?(setting) && has_precedence?(old_scope, set["scope"])
          value = set["values"][setting]
          old_scope = set["scope"]
        end
      end
      value
    end

    # Collects a hash with all default values for a page or post
    #
    # path - the relative path of the page or post
    # type - a symbol indicating the type (:post or :page)
    #
    # Returns a hash with all default values (an empty hash if there are none)
    def all(path, type)
      defaults = {}

      merge_data_cascade_for_path(path, defaults)

      old_scope = nil
      matching_sets(path, type).each do |set|
        if has_precedence?(old_scope, set["scope"])
          defaults = Utils.deep_merge_hashes(defaults, set["values"])
          old_scope = set["scope"]
        else
          defaults = Utils.deep_merge_hashes(set["values"], defaults)
        end
      end
      defaults
    end

    private

    def merge_data_cascade_for_path(path, merged_data)
      absolute_path = site.in_source_dir(path)
      site.defaults_reader.path_defaults
        .select { |k, _v| absolute_path.include? k }
        .sort_by { |k, _v| k.length }
        .each do |defaults|
          merged_data.merge!(defaults[1])
        end
    end

    # Checks if a given default setting scope matches the given path and type
    #
    # scope - the hash indicating the scope, as defined in bridgetown.config.yml
    # path - the path to check for
    # type - the type (:post or :page) to check for
    #
    # Returns true if the scope applies to the given type and path
    def applies?(scope, path, type)
      applies_type?(scope, type) && applies_path?(scope, path)
    end

    def applies_path?(scope, path)
      rel_scope_path = scope["path"]
      return true if !rel_scope_path.is_a?(String) || rel_scope_path.empty?

      sanitized_path = sanitize_path(path)

      if rel_scope_path.include?("*")
        glob_scope(sanitized_path, rel_scope_path)
      else
        path_is_subpath?(sanitized_path, strip_collections_dir(rel_scope_path))
      end
    end

    def glob_scope(sanitized_path, rel_scope_path)
      site_source    = Pathname.new(site.source)
      abs_scope_path = site_source.join(rel_scope_path).to_s

      glob_cache(abs_scope_path).each do |scope_path|
        scope_path = Pathname.new(scope_path).relative_path_from(site_source).to_s
        scope_path = strip_collections_dir(scope_path)
        Bridgetown.logger.debug "Globbed Scope Path:", scope_path
        return true if path_is_subpath?(sanitized_path, scope_path)
      end
      false
    end

    def glob_cache(path)
      @glob_cache ||= {}
      @glob_cache[path] ||= Dir.glob(path)
    end

    def path_is_subpath?(path, parent_path)
      path.start_with?(parent_path)
    end

    def strip_collections_dir(path)
      collections_dir  = site.config["collections_dir"]
      slashed_coll_dir = collections_dir.empty? ? "/" : "#{collections_dir}/"
      return path if collections_dir.empty? || !path.to_s.start_with?(slashed_coll_dir)

      path.sub(slashed_coll_dir, "")
    end

    # Determines whether the scope applies to type.
    # The scope applies to the type if:
    #   1. no 'type' is specified
    #   2. the 'type' in the scope is the same as the type asked about
    #
    # scope - the Hash defaults set being asked about application
    # type  - the type of the document being processed / asked about
    #         its defaults.
    #
    # Returns true if either of the above conditions are satisfied,
    #   otherwise returns false
    def applies_type?(scope, type)
      !scope.key?("type") || scope["type"].eql?(type.to_s)
    end

    # Checks if a given set of default values is valid
    #
    # set - the default value hash, as defined in bridgetown.config.yml
    #
    # Returns true if the set is valid and can be used in this class
    def valid?(set)
      set.is_a?(Hash) && set["values"].is_a?(Hash)
    end

    # Determines if a new scope has precedence over an old one
    #
    # old_scope - the old scope hash, or nil if there's none
    # new_scope - the new scope hash
    #
    # Returns true if the new scope has precedence over the older
    # rubocop: disable Naming/PredicateName
    def has_precedence?(old_scope, new_scope)
      return true if old_scope.nil?

      new_path = sanitize_path(new_scope["path"])
      old_path = sanitize_path(old_scope["path"])

      if new_path.length != old_path.length
        new_path.length >= old_path.length
      elsif new_scope.key?("type")
        true
      else
        !old_scope.key? "type"
      end
    end
    # rubocop: enable Naming/PredicateName

    # Collects a list of sets that match the given path and type
    #
    # Returns an array of hashes
    def matching_sets(path, type)
      @matched_set_cache ||= {}
      @matched_set_cache[path] ||= {}
      @matched_set_cache[path][type] ||= begin
        valid_sets.select do |set|
          !set.key?("scope") || applies?(set["scope"], path, type)
        end
      end
    end

    # Returns a list of valid sets
    #
    # This is not cached to allow plugins to modify the configuration
    # and have their changes take effect
    #
    # Returns an array of hashes
    def valid_sets
      sets = site.config["defaults"]
      return [] unless sets.is_a?(Array)

      sets.map do |set|
        if valid?(set)
          ensure_time!(update_deprecated_types(set))
        else
          Bridgetown.logger.warn "Defaults:", "An invalid front-matter default set was found:"
          Bridgetown.logger.warn set.to_s
          nil
        end
      end.compact
    end

    # Sanitizes the given path by removing a leading and adding a trailing slash

    SANITIZATION_REGEX = %r!\A/|(?<=[^/])\z!.freeze

    def sanitize_path(path)
      if path.nil? || path.empty?
        ""
      else
        path.gsub(SANITIZATION_REGEX, "")
      end
    end
  end
end
