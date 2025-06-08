// Constants
const SALT = 'default-salt-value';

// Convert string to UTF-8 bytes
function stringToUtf8Bytes(str) {
  return new TextEncoder().encode(str);
}

// Convert bytes to hex string
function bytesToHex(bytes) {
  return Array.from(bytes)
    .map(b => b.toString(16).padStart(2, '0'))
    .join('');
}

// Calculate SHA-256 hash
async function calculateSHA256(data) {
  const msgBuffer = new TextEncoder().encode(data);
  const hashBuffer = await crypto.subtle.digest('SHA-256', msgBuffer);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
}

// Handle authentication request
async function handleAuthentication(data) {
  try {
    const { username, vpnAuth, uri } = data;
    
    // Create salted input
    const saltedInput = `${username}:${SALT}`;
    
    // Calculate hash
    const hashHex = await calculateSHA256(saltedInput);
    
    // Construct the URL
    const requestUrl = `${uri}/${hashHex}`;
    
    // Make the request
    const response = await fetch(requestUrl, {
      method: 'GET',
      headers: {
        'VPNAuth': vpnAuth
      }
    });
    
    return {
      status: response.status,
      message: await response.text()
    };
  } catch (error) {
    console.error('Authentication error:', error);
    
    // Check if the error is due to missing host permissions
    if (error.name === 'TypeError' && error.message.includes('Failed to fetch')) {
      const url = new URL(data.uri);
      const domain = url.hostname;
      return {
        status: 403,
        message: `Add the following entry to manifest.json under host_permissions:\n\n"host_permissions": [\n  "https://${domain}/*"\n],`
      };
    }
    
    throw error;
  }
}

// Listen for messages from popup
chrome.runtime.onMessage.addListener((request, sender, sendResponse) => {
  if (request.action === 'authenticate') {
    handleAuthentication(request.data)
      .then(response => sendResponse(response))
      .catch(error => sendResponse({ status: 500, message: error.message }));
    return true; // Required for async sendResponse
  }
}); 