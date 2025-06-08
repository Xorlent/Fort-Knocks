document.addEventListener('DOMContentLoaded', function() {
  // Load saved credentials if they exist
  chrome.storage.local.get(['username', 'vpnAuth', 'uri'], function(result) {
    if (result.username) {
      document.getElementById('username').value = result.username;
      document.getElementById('vpnAuth').value = result.vpnAuth;
      document.getElementById('uri').value = result.uri;
      document.getElementById('saveCredentials').checked = true;
    }
  });

  document.getElementById('authenticate').addEventListener('click', async function() {
    const username = document.getElementById('username').value.toLowerCase();
    const vpnAuth = document.getElementById('vpnAuth').value;
    const uri = document.getElementById('uri').value;
    const saveCredentials = document.getElementById('saveCredentials').checked;

    if (!username || !vpnAuth || !uri) {
      showStatus('Please fill in all fields', 'error');
      return;
    }

    try {
      // Save credentials if requested
      if (saveCredentials) {
        chrome.storage.local.set({
          username: username,
          vpnAuth: vpnAuth,
          uri: uri
        });
      }

      // Send message to background script to handle authentication
      const response = await chrome.runtime.sendMessage({
        action: 'authenticate',
        data: {
          username,
          vpnAuth,
          uri
        }
      });

      handleResponse(response);
    } catch (error) {
      showStatus('Error: ' + error.message, 'error');
    }
  });
});

function handleResponse(response) {
  const statusDiv = document.getElementById('status');
  statusDiv.style.display = 'block';

  switch (response.status) {
    case 200:
      showStatus('Success! Please wait up to 2 minutes before connecting to the SSLVPN. Your session will be valid for 8 hours.', 'success');
      break;
    case 401:
      showStatus('Authentication failed. Invalid pre-shared key.', 'error');
      break;
    case 403:
      showStatus('Please update this extension\'s manifest.json, then close and reopen your browser:', 'error');
      // Create a code block for the manifest update
      const codeBlock = document.createElement('pre');
      codeBlock.style.cssText = 'background: #f5f5f5; padding: 10px; border-radius: 4px; overflow-x: auto; margin-top: 10px;';
      codeBlock.textContent = response.message;
      statusDiv.appendChild(codeBlock);
      break;
    case 404:
      showStatus('Invalid username hash or key not found.', 'error');
      break;
    case 429:
      showStatus('Rate limit exceeded. Try again later.', 'warning');
      break;
    default:
      showStatus('Unexpected response from server (HTTP ' + response.status + ')', 'error');
  }
}

function showStatus(message, type) {
  const statusDiv = document.getElementById('status');
  statusDiv.textContent = message;
  statusDiv.className = 'status ' + type;
  statusDiv.style.display = 'block';
} 