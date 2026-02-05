// pad capture - content script
// Provides DOM access for page info and selection

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
  }
  return true;
});
