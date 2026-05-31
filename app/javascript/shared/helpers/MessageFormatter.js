import mila from 'markdown-it-link-attributes';
import mentionPlugin from './markdownIt/link';
import MarkdownIt from 'markdown-it';

// [ALPHNOLOGY] Extended to support cw_image_width in addition to cw_image_height.
// cw_image_width is used by the inline image paste feature (Shift+Cmd/Ctrl+V in email editor).
//
// MERGE NOTE (targeting upstream v4.15.0 / PR #14516):
// Upstream PR #14516 renames cw_image_height → cw_image_width as the primary dimension param
// and updates @chatwoot/prosemirror-schema to write width instead of height.
// When merging, consolidate setImageHeight + setImageWidth into a single function that
// reads cw_image_width. Keep backward-compat for cw_image_height if old messages exist.
const setImageHeight = inlineToken => {
  const imgSrc = inlineToken.attrGet('src');
  if (!imgSrc) return;
  try {
    const url = new URL(imgSrc);
    const height = url.searchParams.get('cw_image_height');
    if (!height) return;
    inlineToken.attrSet('style', `height: ${height};`);
  } catch {
    // invalid URL, skip silently
  }
};

// [ALPHNOLOGY] Reads cw_image_width query param and applies it as an inline style.
// Added alongside setImageHeight to support the inline image paste feature.
const setImageWidth = inlineToken => {
  const imgSrc = inlineToken.attrGet('src');
  if (!imgSrc) return;
  try {
    const url = new URL(imgSrc);
    const width = url.searchParams.get('cw_image_width');
    if (!width) return;
    const existingStyle = inlineToken.attrGet('style') || '';
    inlineToken.attrSet('style', `${existingStyle}width: ${width};`.trim());
  } catch {
    // invalid URL, skip silently
  }
};

const processInlineToken = blockToken => {
  blockToken.children.forEach(inlineToken => {
    if (inlineToken.type === 'image') {
      setImageHeight(inlineToken);
      setImageWidth(inlineToken); // [ALPHNOLOGY] inline image width support
    }
  });
};

const imgResizeManager = md => {
  // Custom rule for image resize in markdown
  // If the image url has a query param cw_image_height or cw_image_width,
  // then add a style attribute to the image.
  md.core.ruler.after('inline', 'add-image-height', state => {
    state.tokens.forEach(blockToken => {
      if (blockToken.type === 'inline') {
        processInlineToken(blockToken);
      }
    });
  });
};

const createMarkdownInstance = (linkify = true) => {
  return MarkdownIt({
    html: false,
    xhtmlOut: true,
    breaks: true,
    langPrefix: 'language-',
    linkify,
    typographer: true,
    quotes: '\u201c\u201d\u2018\u2019',
    maxNesting: 20,
  })
    .use(mentionPlugin)
    .use(imgResizeManager)
    .use(mila, {
      attrs: {
        class: 'link',
        rel: 'noreferrer noopener nofollow',
        target: '_blank',
      },
    });
};

const TWITTER_USERNAME_REGEX = /(^|[^@\w])@(\w{1,15})\b/g;
const TWITTER_USERNAME_REPLACEMENT = '$1[@$2](http://twitter.com/$2)';
const TWITTER_HASH_REGEX = /(^|\s)#(\w+)/g;
const TWITTER_HASH_REPLACEMENT = '$1[#$2](https://twitter.com/hashtag/$2)';

class MessageFormatter {
  constructor(
    message,
    isATweet = false,
    isAPrivateNote = false,
    linkify = true
  ) {
    this.message = message || '';
    this.isAPrivateNote = isAPrivateNote;
    this.isATweet = isATweet;
    this.linkify = linkify;
    this.md = createMarkdownInstance(linkify);
  }

  formatMessage() {
    let updatedMessage = this.message;
    if (this.isATweet && !this.isAPrivateNote) {
      updatedMessage = updatedMessage.replace(
        TWITTER_USERNAME_REGEX,
        TWITTER_USERNAME_REPLACEMENT
      );
      updatedMessage = updatedMessage.replace(
        TWITTER_HASH_REGEX,
        TWITTER_HASH_REPLACEMENT
      );
    }
    return this.md.render(updatedMessage);
  }

  get formattedMessage() {
    return this.formatMessage();
  }

  get plainText() {
    const strippedOutHtml = new DOMParser().parseFromString(
      this.formattedMessage,
      'text/html'
    );
    return strippedOutHtml.body.textContent || '';
  }
}

export default MessageFormatter;
