// pad capture - content script
// Provides DOM access for page info, selection, and content extraction

// Simple HTML to Markdown converter
function htmlToMarkdown(element) {
  let md = '';

  function process(node) {
    if (node.nodeType === Node.TEXT_NODE) {
      return node.textContent;
    }

    if (node.nodeType !== Node.ELEMENT_NODE) {
      return '';
    }

    const tag = node.tagName.toLowerCase();
    const children = Array.from(node.childNodes).map(process).join('');

    switch (tag) {
      case 'h1': return `# ${children.trim()}\n\n`;
      case 'h2': return `## ${children.trim()}\n\n`;
      case 'h3': return `### ${children.trim()}\n\n`;
      case 'h4': return `#### ${children.trim()}\n\n`;
      case 'h5': return `##### ${children.trim()}\n\n`;
      case 'h6': return `###### ${children.trim()}\n\n`;
      case 'p': return `${children.trim()}\n\n`;
      case 'br': return '\n';
      case 'hr': return '---\n\n';
      case 'strong':
      case 'b': return `**${children}**`;
      case 'em':
      case 'i': return `*${children}*`;
      case 'code': return `\`${children}\``;
      case 'pre': return `\`\`\`\n${children.trim()}\n\`\`\`\n\n`;
      case 'blockquote': return `> ${children.trim().replace(/\n/g, '\n> ')}\n\n`;
      case 'a':
        const href = node.getAttribute('href');
        if (href && !href.startsWith('javascript:')) {
          return `[${children}](${href})`;
        }
        return children;
      case 'img':
        const src = node.getAttribute('src');
        const alt = node.getAttribute('alt') || '';
        return src ? `![${alt}](${src})` : '';
      case 'ul':
        return Array.from(node.children)
          .map(li => `- ${process(li).trim()}`)
          .join('\n') + '\n\n';
      case 'ol':
        return Array.from(node.children)
          .map((li, i) => `${i + 1}. ${process(li).trim()}`)
          .join('\n') + '\n\n';
      case 'li': return children;
      case 'div':
      case 'section':
      case 'article':
      case 'main':
        return children + '\n';
      case 'span': return children;
      case 'script':
      case 'style':
      case 'nav':
      case 'footer':
      case 'header':
      case 'aside':
      case 'noscript':
        return '';
      default:
        return children;
    }
  }

  md = process(element);

  // Clean up multiple newlines
  md = md.replace(/\n{3,}/g, '\n\n').trim();

  return md;
}

// Extract main content from page
function extractContent() {
  // Try to find main content area
  const selectors = [
    'article',
    'main',
    '[role="main"]',
    '.post-content',
    '.article-content',
    '.entry-content',
    '.content',
    '#content'
  ];

  for (const selector of selectors) {
    const el = document.querySelector(selector);
    if (el && el.textContent.trim().length > 100) {
      return el;
    }
  }

  // Fallback to body
  return document.body;
}

// Get page content as markdown
function getPageMarkdown() {
  const title = document.title;
  const url = window.location.href;
  const content = extractContent();
  const markdown = htmlToMarkdown(content);

  // Add frontmatter
  return `# ${title}\n\nSource: ${url}\n\n---\n\n${markdown}`;
}

// Listen for messages from background script
chrome.runtime.onMessage.addListener((request, sender, sendResponse) => {
  if (request.action === 'getPageInfo') {
    sendResponse({
      url: window.location.href,
      title: document.title,
      selection: window.getSelection().toString()
    });
  } else if (request.action === 'getSelection') {
    sendResponse({
      selection: window.getSelection().toString()
    });
  } else if (request.action === 'getMarkdown') {
    sendResponse({
      markdown: getPageMarkdown()
    });
  }
  return true;
});
