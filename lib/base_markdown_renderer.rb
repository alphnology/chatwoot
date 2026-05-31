# [ALPHNOLOGY] Extended to support cw_image_width in addition to cw_image_height.
# cw_image_width is used by the inline image paste feature added in this fork.
#
# MERGE NOTE (targeting upstream v4.15.0 / PR #14516):
# Upstream PR #14516 adds cw_image_width as the dimension param written by the updated
# @chatwoot/prosemirror-schema imageResizeView. When merging:
#   1. Confirm upstream's extract_image_dimensions method signature matches ours.
#   2. Upstream may rename render_img_tag signature — reconcile parameter order.
#   3. Keep backward-compat: cw_image_height should still work for old stored messages.
class BaseMarkdownRenderer < CommonMarker::HtmlRenderer
  def image(node)
    src, title = extract_img_attributes(node)
    height, width = extract_image_dimensions(src)

    render_img_tag(src, title, height, width)
  end

  private

  def extract_img_attributes(node)
    [
      escape_href(node.url),
      escape_html(node.title)
    ]
  end

  # [ALPHNOLOGY] Returns [height, width] from cw_image_height / cw_image_width query params.
  # width takes precedence for sizing when both are present (width + auto height is more
  # email-client-friendly than fixed height + auto width).
  def extract_image_dimensions(src)
    query_params = parse_query_params(src)
    height = query_params['cw_image_height']&.first
    width  = query_params['cw_image_width']&.first
    [height, width]
  end

  def parse_query_params(url)
    parsed_url = URI.parse(url)
    CGI.parse(parsed_url.query || '')
  rescue URI::InvalidURIError
    {}
  end

  # [ALPHNOLOGY] Supports width attribute in addition to height.
  # Width takes precedence: if width is set, use width + auto height (safer across email clients).
  # Falls back to height + auto width for backward compatibility with existing messages.
  def render_img_tag(src, title, height = nil, width = nil)
    title_attribute = title.present? ? " title=\"#{title}\"" : ''
    size_attribute  = if width
                        " width=\"#{width}\" height=\"auto\""
                      elsif height
                        " height=\"#{height}\" width=\"auto\""
                      else
                        ''
                      end

    plain do
      # plain ensures that the content is not wrapped in a paragraph tag
      out("<img src=\"#{src}\"#{title_attribute}#{size_attribute} />")
    end
  end
end
