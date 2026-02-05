// pad capture - background service worker
// Handles context menus, keyboard shortcuts, and WebSocket connection to pad daemon

const DEFAULT_WS_URL = 'ws://localhost:7778';
let PAD_WS_URL = DEFAULT_WS_URL;

// Load settings
chrome.storage.sync.get({ wsUrl: DEFAULT_WS_URL }, (items) => {
  PAD_WS_URL = items.wsUrl;
});

// Listen for settings changes
chrome.storage.onChanged.addListener((changes, area) => {
  if (area === 'sync' && changes.wsUrl) {
    PAD_WS_URL = changes.wsUrl.newValue;
    // Reconnect with new URL
    if (ws) {
      ws.close();
    }
  }
});

// Cross-browser badge API (MV3: action, MV2: browserAction)
const badgeAPI = chrome.action || chrome.browserAction;

// Show badge notification
function showBadge(text, color) {
  if (!badgeAPI) return;
  badgeAPI.setBadgeText({ text: text });
  badgeAPI.setBadgeBackgroundColor({ color: color });
  setTimeout(() => {
    badgeAPI.setBadgeText({ text: '' });
  }, 2000);
}

let ws = null;
let wsConnecting = false;
let reconnectAttempts = 0;
const MAX_RECONNECT_DELAY = 30000;

// Queue for messages while disconnected
let messageQueue = [];

// Create context menus on install
chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.create({
    id: 'pad-page',
    title: 'Capture page URL to pad',
    contexts: ['page']
  });

  chrome.contextMenus.create({
    id: 'pad-content',
    title: 'Capture page content to pad',
    contexts: ['page']
  });

  chrome.contextMenus.create({
    id: 'pad-selection',
    title: 'Capture selection to pad',
    contexts: ['selection']
  });

  chrome.contextMenus.create({
    id: 'pad-image',
    title: 'Capture image to pad',
    contexts: ['image']
  });

  chrome.contextMenus.create({
    id: 'pad-link',
    title: 'Capture link to pad',
    contexts: ['link']
  });

  chrome.contextMenus.create({
    id: 'pad-all-links',
    title: 'Capture all links to pad',
    contexts: ['page']
  });

  chrome.contextMenus.create({
    id: 'pad-code-blocks',
    title: 'Capture code blocks to pad',
    contexts: ['page']
  });

  chrome.contextMenus.create({
    id: 'pad-tables',
    title: 'Capture tables to pad',
    contexts: ['page']
  });

  chrome.contextMenus.create({
    id: 'pad-screenshot',
    title: 'Capture screenshot to pad',
    contexts: ['page']
  });
});

// Connect to pad daemon via WebSocket
function connectWebSocket() {
  if (ws && ws.readyState === WebSocket.OPEN) return;
  if (wsConnecting) return;

  wsConnecting = true;

  try {
    ws = new WebSocket(PAD_WS_URL);

    ws.onopen = () => {
      wsConnecting = false;
      reconnectAttempts = 0;
      console.log('pad: connected to daemon');

      // Flush queued messages
      while (messageQueue.length > 0) {
        const msg = messageQueue.shift();
        sendMessage(msg);
      }
    };

    ws.onclose = () => {
      wsConnecting = false;
      ws = null;
      scheduleReconnect();
    };

    ws.onerror = (err) => {
      console.error('pad: WebSocket error', err);
      wsConnecting = false;
    };

    ws.onmessage = (event) => {
      try {
        const response = JSON.parse(event.data);
        if (response.error) {
          console.error('pad: daemon error:', response.error);
          showBadge('!', '#dc3545');
        } else {
          console.log('pad: captured', response);
          showBadge('✓', '#28a745');
        }
      } catch (e) {
        console.log('pad: response:', event.data);
      }
    };
  } catch (err) {
    wsConnecting = false;
    console.error('pad: failed to connect', err);
    scheduleReconnect();
  }
}

function scheduleReconnect() {
  reconnectAttempts++;
  const delay = Math.min(1000 * Math.pow(2, reconnectAttempts), MAX_RECONNECT_DELAY);
  console.log(`pad: reconnecting in ${delay}ms`);
  setTimeout(connectWebSocket, delay);
}

function sendMessage(msg) {
  if (ws && ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify(msg));
    return true;
  }
  return false;
}

function capture(content, type, metadata) {
  const msg = {
    action: 'ingest',
    content: content,
    source: 'browser',
    metadata: {
      type: type,
      ...metadata
    }
  };

  // Connect if needed
  if (!ws || ws.readyState !== WebSocket.OPEN) {
    messageQueue.push(msg);
    connectWebSocket();
  } else {
    sendMessage(msg);
  }
}

// Handle context menu clicks
chrome.contextMenus.onClicked.addListener((info, tab) => {
  const pageUrl = info.pageUrl || (tab && tab.url);
  const pageTitle = tab && tab.title;

  switch (info.menuItemId) {
    case 'pad-page':
      capture(pageUrl, 'url', { title: pageTitle });
      break;

    case 'pad-content':
      // Request markdown content from content script
      chrome.tabs.sendMessage(tab.id, { action: 'getMarkdown' }, (response) => {
        if (response && response.markdown) {
          capture(response.markdown, 'markdown', { url: pageUrl, title: pageTitle });
        }
      });
      break;

    case 'pad-selection':
      capture(info.selectionText, 'selection', { url: pageUrl, title: pageTitle });
      break;

    case 'pad-image':
      capture(info.srcUrl, 'image', { url: pageUrl });
      break;

    case 'pad-link':
      capture(info.linkUrl, 'link', { url: pageUrl, link_text: info.linkText || '' });
      break;

    case 'pad-all-links':
      // Request all links from content script
      chrome.tabs.sendMessage(tab.id, { action: 'getAllLinks' }, (response) => {
        if (response && response.links && response.links.length > 0) {
          const content = response.links.map(l => `${l.text}: ${l.href}`).join('\n');
          capture(content, 'links', { url: pageUrl, title: pageTitle, count: response.links.length });
        }
      });
      break;

    case 'pad-code-blocks':
      // Request code blocks from content script
      chrome.tabs.sendMessage(tab.id, { action: 'getCodeBlocks' }, (response) => {
        if (response && response.blocks && response.blocks.length > 0) {
          const content = response.blocks.map((b, i) =>
            `--- Block ${i + 1}${b.lang ? ` (${b.lang})` : ''} ---\n${b.code}`
          ).join('\n\n');
          capture(content, 'code', { url: pageUrl, title: pageTitle, count: response.blocks.length });
        }
      });
      break;

    case 'pad-tables':
      // Request tables from content script
      chrome.tabs.sendMessage(tab.id, { action: 'getTables' }, (response) => {
        if (response && response.tables && response.tables.length > 0) {
          const content = response.tables.map((t, i) =>
            `--- Table ${i + 1} ---\n${t}`
          ).join('\n\n');
          capture(content, 'table', { url: pageUrl, title: pageTitle, count: response.tables.length });
        }
      });
      break;

    case 'pad-screenshot':
      // Capture visible tab as PNG
      chrome.tabs.captureVisibleTab(null, { format: 'png' }, (dataUrl) => {
        if (chrome.runtime.lastError) {
          console.error('pad: screenshot error', chrome.runtime.lastError);
          showBadge('!', '#dc3545');
          return;
        }
        if (dataUrl) {
          capture(dataUrl, 'screenshot', { url: pageUrl, title: pageTitle });
        }
      });
      break;
  }
});

// Listen for messages from content script
chrome.runtime.onMessage.addListener((request, sender, sendResponse) => {
  if (request.action === 'capture') {
    capture(request.content, request.type, request.metadata);
    sendResponse({ ok: true });
  }
  return true;
});

// Handle keyboard shortcuts
chrome.commands.onCommand.addListener((command, tab) => {
  if (command === 'capture-page' && tab) {
    capture(tab.url, 'url', { title: tab.title });
  } else if (command === 'capture-selection' && tab) {
    // Request selection from content script
    chrome.tabs.sendMessage(tab.id, { action: 'getSelection' }, (response) => {
      if (response && response.selection) {
        capture(response.selection, 'selection', { url: tab.url, title: tab.title });
      }
    });
  }
});
