// pad capture - background service worker
// Handles context menus and WebSocket connection to pad daemon

const PAD_WS_URL = 'ws://localhost:7778';

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
    title: 'Capture page to pad',
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
        } else {
          console.log('pad: captured', response);
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

    case 'pad-selection':
      capture(info.selectionText, 'selection', { url: pageUrl, title: pageTitle });
      break;

    case 'pad-image':
      capture(info.srcUrl, 'image', { url: pageUrl });
      break;

    case 'pad-link':
      capture(info.linkUrl, 'link', { url: pageUrl, link_text: info.linkText || '' });
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
