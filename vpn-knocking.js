export default {
    async fetch(request, env) {
      // Verify request method
      if (request.method !== 'GET') {
        return new Response('Method not allowed', { status: 405 });
      }
  
      const clientIP = request.headers.get('cf-connecting-ip');
      const requestUrl = new URL(request.url);
      const hostname = requestUrl.hostname;
      const bruteforceTTL = env.TTL || 14400
      const VPNAuthMaxLength = 256;
  
      // Check VPNAuth header PSK value
      const vpnAuth = request.headers.get('VPNAuth');
      if (!vpnAuth || vpnAuth.length > VPNAuthMaxLength) {
        // Check rate limit on missing auth header
        const rateLimitPass = await this.checkRateLimit(clientIP, hostname, bruteforceTTL);
        if (!rateLimitPass) {
          return new Response('Rate limit exceeded. Try again later.', { status: 429 });
        }
        return new Response('Unauthorized', { status: 401 });
      }
  
      // Constant-time comparison of pre-shared key (VPNAuth)
      const encoder = new TextEncoder();
      const providedAuth = encoder.encode(vpnAuth);
      const expectedAuth = encoder.encode(env.VPNAUTH);
  
      // Validate VPNAuth length before processing
      if (providedAuth.byteLength !== expectedAuth.byteLength) {
        // Check rate limit on invalid auth length
        const rateLimitPass = await this.checkRateLimit(clientIP, hostname, bruteforceTTL);
        if (!rateLimitPass) {
          return new Response('Rate limit exceeded. Try again later.', { status: 429 });
        }
        return new Response('Unauthorized', { status: 401 });
      }
      
      let isAuthorized = false;
      try {
        // Use a fixed-size buffer for both inputs to prevent length leakage
        const compareAuth = new Uint8Array(VPNAuthMaxLength);
        const compareExpected = new Uint8Array(VPNAuthMaxLength);
        
        // Copy both inputs into fixed-size buffers
        for (let i = 0; i < VPNAuthMaxLength; i++) {
          compareAuth[i] = i < providedAuth.length ? providedAuth[i] : 0;
          compareExpected[i] = i < expectedAuth.length ? expectedAuth[i] : 0;
        }
        
        // Perform constant-time comparison
        isAuthorized = crypto.subtle.timingSafeEqual(compareAuth, compareExpected);
      } catch (e) {
        isAuthorized = false;
      }
  
      if (!isAuthorized) {
        // Check rate limit on failed auth
        const rateLimitPass = await this.checkRateLimit(clientIP, hostname, bruteforceTTL);
        if (!rateLimitPass) {
          return new Response('Rate limit exceeded. Try again later.', { status: 429 });
        }
        return new Response('Unauthorized', { status: 401 });
      }
  
      // Process request
      const requestPath = requestUrl.pathname.substring(1);
      const validUserHash = await this.handleRequest(requestPath, clientIP, env);
      // Check rate limit on failed hash match
      if (!validUserHash){
        const rateLimitPass = await this.checkRateLimit(clientIP, hostname, bruteforceTTL);
        if (!rateLimitPass) {
          return new Response('Rate limit exceeded. Try again later.', { status: 429 });
        }
        return new Response('Rejected', { status: 404 });
      }
      else{
        return new Response('Authenticated successfully. Please wait 2 minutes before connecting.', { status: 200 });
      }
    },
  
    async checkRateLimit(clientIP, hostname, bruteforceTTL) {
      // Create cache key for this IP using the actual hostname
      const cacheKey = `https://${hostname}/ratelimit:${clientIP}`;
  
      // Try to get the cache value
      let cache = await caches.open("VPNAuth");
      let response = await cache.match(cacheKey);
      
      if (response) {
        // IP has made an invalid request within the TTL period
        return false;
      }
      
      // Create a dummy response to store in cache
      response = new Response('rate-limit-marker', {
        headers: {
          'Cache-Control': `max-age=${bruteforceTTL}` // TTL
        }
      });
      
      // Store the rate limit marker
      await cache.put(cacheKey, response);
      return true;
    },
  
    async handleRequest(requestPath, clientIP, env) {
      const sourceKeys = await env.SSLUSERS.list();
      
      for (const key of sourceKeys.keys) {
        const salt = 'default-salt-value';
        const saltedInput = `${key.name}:${salt}`;
        const encoder = new TextEncoder();
        const msgBuffer = encoder.encode(saltedInput);

        const hashBuffer = await crypto.subtle.digest('SHA-256', msgBuffer);
        const hashArray = Array.from(new Uint8Array(hashBuffer));
        const hashHex = hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
  
        if (hashHex === requestPath) {
          // Add to authorized IP list with an 8-hour expiration
          await env.SSLAUTHORIZED.put(clientIP, key.name, {
            expirationTtl: 28800
          });
          return true;
        }
      }
      return false;
    }
  };
  