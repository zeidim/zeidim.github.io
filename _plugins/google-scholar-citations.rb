require "active_support/all"
require "nokogiri"
require "open-uri"
require "liquid"

module Helpers
  extend ActiveSupport::NumberHelper
end

module Jekyll
  class GoogleScholarCitationsTag < Liquid::Tag
    Citations = {}

    def initialize(tag_name, params, tokens)
      super
      @raw_params = params
    end

    # Evaluate a Liquid expression (variable, dotted path, or string literal)
    def eval_param(context, raw)
      expr = Liquid::Expression.parse(raw)
      val  = context.evaluate(expr)
      # If still nil, treat as literal string and strip any surrounding quotes/spaces
      (val.nil? || (val.respond_to?(:empty?) && val.empty?)) ? raw.to_s.strip.gsub(/\A['"]|['"]\z/, "") : val
    end

    def render(context)
      # Support: {% google_scholar_citations page.scholar_user_id page.google_scholar_id %}
      # or      {% google_scholar_citations "gXXXXAAAAAJ" "ZeXyd9-uunAC" %}
      parts = @raw_params.split(/\s+/, 2)
      unless parts.size == 2
        Jekyll.logger.warn "google_scholar_citations:", "expected 2 params: <scholar_user_id> <article_id_suffix>"
        return "N/A"
      end

      scholar_id_raw, article_id_raw = parts
      scholar_id = eval_param(context, scholar_id_raw)
      article_id = eval_param(context, article_id_raw)

      if scholar_id.to_s.empty? || article_id.to_s.empty?
        Jekyll.logger.warn "google_scholar_citations:", "Empty scholar_id or article_id after evaluation"
        return "N/A"
      end

      # Example URL:
      # https://scholar.google.com/citations?view_op=view_citation&hl=en&user=<scholar_id>&citation_for_view=<scholar_id>:<article_id>
      article_url = "https://scholar.google.com/citations?view_op=view_citation&hl=en&user=#{scholar_id}&citation_for_view=#{scholar_id}:#{article_id}"

      # Return cached value if present
      if Citations.key?(article_id)
        return Citations[article_id]
      end

      begin
        # Random sleep to be gentler
        sleep(rand(1.2..2.8))

        # A more realistic header set
        headers = {
          "User-Agent" => "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "\
                          "(KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36",
          "Accept-Language" => "en-US,en;q=0.9",
          "Referer" => "https://scholar.google.com/"
        }

        html = URI.open(article_url, headers) { |io| io.read }
        doc  = Nokogiri::HTML(html)

        # Try several ways to find the count:

        # 1) Direct link that contains "Cited by"
        cited_link = doc.at_css('a:contains("Cited by")')

        # 2) Link in the citation info table pointing to cites=...
        cited_link ||= doc.at_css('a[href*="cites="]')

        # 3) og:description / description meta fallbacks
        og_desc = doc.at_css('meta[property="og:description"]')&.[]('content')
        desc    = doc.at_css('meta[name="description"]')&.[]('content')

        count = nil

        if cited_link
          if (m = cited_link.text.to_s.match(/Cited by\s+([\d,]+)/i))
            count = m[1]
          elsif (m = cited_link.text.to_s.match(/([\d,]+)/))
            count = m[1]
          end
        end

        # Text search fallback
        if count.nil?
          if (m = doc.text.match(/Cited by\s+([\d,]+)/i))
            count = m[1]
          end
        end

        # Meta description fallback
        if count.nil? && og_desc
          if (m = og_desc.match(/Cited by\s+([\d,]+)/i))
            count = m[1]
          end
        end
        if count.nil? && desc
          if (m = desc.match(/Cited by\s+([\d,]+)/i))
            count = m[1]
          end
        end

        # Last resort: zero if not found (avoid throwing)
        raw_int = count ? count.delete(",").to_i : 0

        human = Helpers.number_to_human(
          raw_int,
          format: "%n%u",
          precision: 2,
          units: { thousand: "K", million: "M", billion: "B" }
        )

        Citations[article_id] = human
        human
      rescue => e
        Jekyll.logger.warn "google_scholar_citations:", "Error for #{article_id} -> #{e.class}: #{e.message}"
        Citations[article_id] = "N/A"
        "N/A"
      end
    end
  end
end

Liquid::Template.register_tag('google_scholar_citations', Jekyll::GoogleScholarCitationsTag)
