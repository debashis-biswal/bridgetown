# frozen_string_literal: true

# Handles Generated Pages
Bridgetown::Hooks.register :pages, :post_init, reloadable: false do |page|
  if page.class != Bridgetown::PrototypePage && page.data["prototype"].is_a?(Hash)
    Bridgetown::PrototypeGenerator.add_matching_template(page)
  end
end

# Handles Resources
Bridgetown::Hooks.register :resources, :post_read, reloadable: false do |resource|
  if resource.data["prototype"].is_a?(Hash)
    Bridgetown::PrototypeGenerator.add_matching_template(resource)
  end
end

# Ensure sites clear out templates before rebuild
Bridgetown::Hooks.register :site, :after_reset, reloadable: false do |_site|
  Bridgetown::PrototypeGenerator.matching_templates.clear
end

module Bridgetown
  class PrototypeGenerator < Generator
    priority :low

    # @return [Bridgetown::Site]
    attr_reader :site

    # @return [Set<Bridgetown::Page, Bridgetown::Resource::Base>]
    def self.matching_templates
      @matching_templates ||= Set.new
    end

    def self.add_matching_template(template)
      matching_templates << template
    end

    # @param site [Bridgetown::Site]
    def generate(site)
      @site = site
      @configured_collection = "posts" unless site.uses_resource?
      page_list = site.uses_resource? ? site.collections.pages.resources : site.pages

      prototype_pages = self.class.matching_templates.select do |page|
        page_list.include?(page)
      end

      if prototype_pages.length.positive?
        ensure_pagination_enabled

        page_list.reject! do |page|
          prototype_pages.include? page
        end

        prototype_pages.each do |prototype_page|
          search_term = validate_search_term(prototype_page)
          next if search_term.nil?

          terms_matching_pages(search_term).each do |term|
            generate_new_page_from_prototype(prototype_page, search_term, term)
          end
        end
      end
    end

    def ensure_pagination_enabled
      unless @site.config.dig(:pagination, :enabled)
        Bridgetown.logger.warn(
          "Pagination:",
          "Must be enabled for prototype pages to contain matches"
        )
      end
    end

    # Check incoming prototype configuration and normalize options.
    #
    # @param prototype_page [Bridgetown::Page, Bridgetown::Resource::Base]
    #
    # @return [String, nil]
    def validate_search_term(prototype_page)
      # @type [String]
      search_term = prototype_page.data["prototype"]["term"].to_s
      return nil unless search_term.present?

      if prototype_page.data["prototype"]["collection"]
        @configured_collection = prototype_page.data["prototype"]["collection"].to_s
      end

      unless site.collections[@configured_collection]
        Bridgetown.logger.warn(
          "No collection specified for prototype page #{prototype_page.relative_path}"
        )
        return nil
      end

      # Categories and Tags are unique in that singular and plural front matter
      # can be present for each
      search_term.sub(%r!^category$!, "categories").sub(%r!^tag$!, "tags")
    end

    def generate_new_page_from_prototype(prototype_page, search_term, term)
      new_page = PrototypePage.new(prototype_page, @configured_collection, search_term, term)
      site.add_generated_page new_page
      new_page
    end

    # Provide a list of all relevent indexed values for the given term.
    #
    # @param search_term [String]
    #
    # @return [Array<String>]
    def terms_matching_pages(search_term)
      pages_list = if site.uses_resource?
                     site.collections[@configured_collection].resources
                   else
                     site.collections[@configured_collection].docs
                   end

      Bridgetown::Paginate::PaginationIndexer.index_documents_by(
        pages_list, search_term
      ).keys
    end
  end

  class PrototypePage < GeneratedPage
    # @return [Bridgetown::Page, Bridgetown::Resource::Base]
    attr_reader :prototyped_page

    # @param prototyped_page [Bridgetown::Page, Bridgetown::Resource::Base]
    # @param collection [Bridgetown::Collection]
    # @param search_term [String]
    # @param term [String]
    def initialize(prototyped_page, collection, search_term, term)
      @prototyped_page = prototyped_page
      @site = prototyped_page.site
      @url = ""
      @name = "index.html"
      @path = prototyped_page.path

      process(@name)

      self.data = Bridgetown::Utils.deep_merge_hashes prototyped_page.data, {}
      self.content = prototyped_page.content

      # Perform some validation that is also performed in Bridgetown::Page
      validate_data! prototyped_page.path
      validate_permalink! prototyped_page.path

      @dir = Pathname.new(prototyped_page.relative_path).dirname.to_s.sub(%r{^_pages}, "")
      @path = site.in_source_dir(@dir, @name)

      process_prototype_page_data(collection, search_term, term)

      Bridgetown::Hooks.trigger :pages, :post_init, self
    end

    def process_prototype_page_data(collection, search_term, term)
      # Fill in pagination details to be handled later by Bridgetown::Paginate
      data["pagination"] = Bridgetown::Utils.deep_merge_hashes(
        prototyped_page.data["pagination"].to_h, {
          "enabled"     => true,
          "collection"  => collection,
          "where_query" => [search_term, term],
        }
      )
      # Use the original prototype page term so we get "tag" back, not "tags":
      data[prototyped_page.data["prototype"]["term"]] = term
      # Process title and slugs/URLs:
      process_title_data_placeholder(search_term, term)
      process_title_simple_placeholders(term)
      slugify_term(term)
    end

    # rubocop:todo Metrics/AbcSize
    def process_title_data_placeholder(search_term, term)
      if prototyped_page.data["prototype"]["data"]
        if data["title"]&.include?(":prototype-data-label")
          related_data = site.data[prototyped_page.data["prototype"]["data"]].dig(term)
          if related_data
            data["#{search_term}_data"] = related_data
            data_label = related_data[prototyped_page.data["prototype"]["data_label"]]
            data["title"] = data["title"].gsub(
              ":prototype-data-label", data_label
            )
          end
        end
      end
    end
    # rubocop:enable Metrics/AbcSize

    def process_title_simple_placeholders(term)
      if data["title"]&.include?(":prototype-term-titleize")
        data["title"] = data["title"].gsub(
          ":prototype-term-titleize", Bridgetown::Utils.titleize_slug(term)
        )
      end

      if data["title"]&.include?(":prototype-term")
        data["title"] = data["title"].gsub(
          ":prototype-term", term
        )
      end
    end

    def slugify_term(term)
      term_slug = Bridgetown::Utils.slugify(term, mode: site.config.slugify_mode)
      @url = if permalink.is_a?(String)
               data["permalink"] = data["permalink"].sub(":term", term_slug)
             else
               "/#{@dir}/#{term_slug}/"
             end
    end
  end
end
