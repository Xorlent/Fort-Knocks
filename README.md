# Fort Knocks
_Cloudflare Worker solution with port knock-like functionality for time-limited access to public-facing services like an SSLVPN portal_  
![Fort Knocks Image](https://github.com/Xorlent/Fort-Knocks/blob/8010b189ad012e2c6d395550cf6041b73037c1d2/img/FortKnocks.jpeg)
### Background
User access controls and multifactor authentication are important, but what if the public-facing service itself has a pre-authentication vulnerability?  This tool implements a secure pre-authentication, pre-connection "knock" that dynamically adds the validated requestor's IP to a temporary allow list so they may connect to the protected service.
### Solution
#### The solution is comprised of Cloudflare workers that:
  - Authenticate client requests for time-limited access to a protected service  
  - Produce a real-time IP allow list for a security device like a firewall to consume  
#### and Windows and MacOS scripts that:
  - Clients run to authenticate against the Cloudflare Worker to receive time-limited access to the desired resource  
### Prerequisites
1. A firewall that supports external IP threat feeds (most do, including Cisco, Palo Alto, Fortinet)
2. A Cloudflare account (https://www.cloudflare.com/)
   - Don't have one?  This solution can be deployed to even a free account!
### Cloudflare Setup
> **_NOTE:_**  Naming within these instructions assume you are protecting an SSLVPN service.  Adjust the names if desired.
1. Log in to your [Cloudflare dashboard](https://dash.cloudflare.com), choose your account, select "Storage & Databases" and click "KV."  
2. Click "Create a namespace," enter "SSLUSERS" for the name, and click "Add."  
3. Click "Create a namespace," enter "SSLAUTHORIZED" for the name, and click "Add."  
4. Now click on "Overview" below the "Workers & Pages" menu option.  
5. Click "Create application"  
    - Click the "Create Worker" button  
    - Enter "vpn-auth" for the name and click "Deploy"  
    - IMPORTANT: Make note of the URL shown on the Congratulations page under, "Preview your worker."  
      - It will look something like https://vpn-auth.organization.workers.dev  
      - You will need this URL to set up the Canary webhook  
    - Click "Configure Worker"  
      - Click "Settings" above the summary section of the page  
      - Click the "Variables" menu option  
      - Under "Variables and Secrets" click "Add" and select "Secret" for the Type  
      - Enter "VPNAUTH" for the variable name and enter a pre-shared key of your choosing for the value (all authorized VPN users will need this in order to authenticate to the service)  
      - Under "KV Namespace Bindings" click "Add binding"  
      - Enter "SSLUSERS" for the variable name and select "SSLUSERS" for the KV namespace  
      - Click "Save and deploy"  
      - Again, click "Add binding"  
      - Enter "SSLAUTHORIZED" for the variable name and select "SSLAUTHORIZED" for the KV namespace  
      - Click "Save and deploy"  
    - Click on the "Quick Edit" button at the top right area of the page  
      - Copy and paste the full contents of the vpn-knocking.js file into the editor window  
      - Click "Save and deploy."  
6. Click "Create application"  
    - Click the "Create Worker" button  
    - Enter "vpn-allowlist" for the name and click "Deploy"
    - IMPORTANT: Make note of the URL shown on the Congratulations page under, "Preview your worker."  
      - It will look something like https://vpn-allowlist.organization.workers.dev  
      - You will need this URL for the security device (eg. firewall) or program that will be consuming this IP list  
    - Click "Configure Worker"  
      - Click "Settings" above the summary section of the page  
      - Click the "Variables" menu option  
      - Under "KV Namespace Bindings" click "Add binding"  
      - Enter "SSLAUTHORIZED" for the variable name and select "SSLAUTHORIZED" for the KV namespace  
      - Click "Save and deploy"  
   - Click on the "Quick Edit" button at the top right area of the page  
     - Copy and paste the full contents of the vpn-allowlist.js file into the editor window
     - Edit the AllowedIPs string variable to include only IP addresses that should be permitted to retrieve the IP blocklist and click "Save and deploy."
### Firewall Setup
1. Log in to your security device  
    - Configure an external threat list  
    - Set the source to the allowlist worker (https://vpn-allowlist.organization.workers.dev in this example)
      - No authentication is necessary, as the requests are filtered to only permitted IPs
    - Set the fetch interval to 1 minute or 60 seconds
    - Apply this IP list to your SSLVPN portal allow rule
      - It is recommended to also add a static IP group or list that should always have access to the SSLVPN service
### Using/Testing
#### Windows
1. Download SSLVPNAuth.ps1 to a Windows computer (Windows 10 1803 and later, as curl.exe is required)
2. Right-click the downloaded file, click "Properties"
3. Click "Unblock," then "OK"
4. Run SSLVPNAuth.ps1, entering a valid username and pre-shared key, and base URI (https://vpn-auth.organization.workers.dev for this example) when prompted
5. The PowerShell script will then complete a request and return the result
   - If authentication was successful, the client IP address should be added to the allowlist within 2 minutes
6. Attempt an SSLVPN connection to verify functionality
#### MacOS
1. Download SSLVPNAuth.sh to a MacOS computer
2. In a terminal, navigate to the location of the SSLVPNAuth.sh script, then run:  
   ```chmod +x SSLVPNAuth.sh```
4. Run SSLVPNAuth.sh, entering a valid username and pre-shared key, and base URI (https://vpn-auth.organization.workers.dev for this example) when prompted
5. The shell script will then complete a request and return the result
   - If authentication was successful, the client IP address should be added to the allowlist within 2 minutes
6. Attempt an SSLVPN connection to verify functionality

### Troubleshooting
#### I have a user that entered the wrong authentication details when running the PowerShell script and now they are rate-limited and cannot attempt to authenticate for another 8 hours!
- IP addresses can be manually added to the SSLAUTHORIZED KV store within the Cloudflare dashboard under, "Storage & Databases"
  - Be sure to remove this entry manually when necessary, as it is not automatically pruned in 8 hours  
  - This KV store can also be used to add persistent allowed IPs as desired -- Manual entires do not expire
#### The Authorized IP list shows IPv4 addresses only and clients are connecting via IPv6
- This solution assumes we are dealing with IPv4.  To allow IPv6 client addresses, simply remove the "-4" immediately following the curl.exe command in each of the client scripts.
#### I want to adjust the lifetime for successful authentication
- Change the TTL values found on lines 71 and 95 in vpn-knocking.js  
