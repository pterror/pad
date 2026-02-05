// pad capture - options page

const DEFAULT_WS_URL = 'ws://localhost:7778';

// Load saved options
chrome.storage.sync.get({ wsUrl: DEFAULT_WS_URL }, (items) => {
  document.getElementById('wsUrl').value = items.wsUrl;
});

// Save options
document.getElementById('save').addEventListener('click', () => {
  const wsUrl = document.getElementById('wsUrl').value.trim() || DEFAULT_WS_URL;

  chrome.storage.sync.set({ wsUrl: wsUrl }, () => {
    const status = document.getElementById('status');
    status.textContent = 'Saved!';
    setTimeout(() => {
      status.textContent = '';
    }, 2000);
  });
});
