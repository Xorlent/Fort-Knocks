export default {
  async fetch(request, env) {
    // Check VPNAuth header PSK value
    const vpnAuth = request.headers.get('VPNAuth');
    if (!vpnAuth) {
      return new Response('Unauthorized', { status: 401 });
    }

    // Constant-time comparison of pre-shared key (VPNAuth)
    const encoder = new TextEncoder();
    // Convert strings to UTF-8
    const providedAuth = encoder.encode(vpnAuth);
    const expectedAuth = encoder.encode(env.VPNAUTH);
    
    let isAuthorized = false;
    try {
      // Copy provided PSK into a fixed-length buffer
      const compareAuth = new Uint8Array(expectedAuth.length);
      // Copy data into the buffer for comparison
      for (let i = 0; i < expectedAuth.length; i++) {
        compareAuth[i] = i < providedAuth.length ? providedAuth[i] : 0;
      }
      isAuthorized = await crypto.subtle.timingSafeEqual(compareAuth, expectedAuth);
      // Xor the lengths of the provided and expected pre-shared key (should be constant-time?)
      const lengthMismatch = providedAuth.length ^ expectedAuth.length;
      // Allow authorization if supplied length and value matches the pre-shared key
      isAuthorized = isAuthorized && (lengthMismatch === 0);
    } catch (e) {
      isAuthorized = false;
    }

    if (!isAuthorized) {
      return new Response('Unauthorized', { status: 401 });
    }

    // Get client IP
    const clientIP = request.headers.get('cf-connecting-ip');
    
    // Enforce rate limit using Cloudflare Cache
    const rateLimitPass = await this.checkRateLimit(request, clientIP);
    if (!rateLimitPass) {
      return new Response('Rate limit exceeded. Try again later.', { status: 429 });
    }

    // Verify request method and process request
    if (request.method === 'GET') {
      const requestPath = new URL(request.url).pathname.substring(1);
      return await this.handleRequest(requestPath, clientIP, env);
    }
    
    return new Response('Method not allowed', { status: 405 });
  },

  async checkRateLimit(request, clientIP) {
    // Create cache key for this IP
    const cacheKey = `https://vpn-allowlist.organization.internal/ratelimit:${clientIP}`;
    
    // Try to get the cache value
    let cache = await caches.open("VPNAuth");
    let response = await cache.match(cacheKey);
    
    if (response) {
      // IP has made a request within the last 8 hours
      console.log(`Rate limit hit for IP: ${clientIP}`);
      return false;
    }
    
    // Create a dummy response to store in cache
    response = new Response('rate-limit-marker', {
      headers: {
        'Cache-Control': 'max-age=28799' // 8 hours - 1 second
      }
    });
    
    // Store the rate limit marker
    await cache.put(cacheKey, response);
    return true;
  },

    async handleRequest(requestPath, clientIP, env) {
      const sourceKeys = await env.SSLUSERS.list();
      
      for (const key of sourceKeys.keys) {
        
        // Check if the request path matches a valid SHA-256 username hash
        const encoder = new TextEncoder();
        const msgBuffer = new TextEncoder().encode(key.name);
        const hashBuffer = await crypto.subtle.digest('SHA-256', msgBuffer);
        const hashArray = Array.from(new Uint8Array(hashBuffer));
        const hashHex = hashArray.map(b => b.toString(16).padStart(2, '0')).join('');

        if (hashHex === requestPath) {
        // Add to authorized IP list with an 8-hour expiration
        await env.SSLAUTHORIZED.put(clientIP, key.name, {
          expirationTtl: 28800
        });
        
        return new Response('Authenticated successfully.  Please wait 2 minutes before connecting.', { status: 200 });
      }
    }
    
    return new Response('Rejected', { status: 404 });
  }
};
