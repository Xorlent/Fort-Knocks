# Fort Knocks
_Cloudflare Worker solution with port knock-like functionality for time-limited access to public-facing services like an SSLVPN portal_  
![Fort Knocks Image](https://github.com/Xorlent/Fort-Knocks/blob/8010b189ad012e2c6d395550cf6041b73037c1d2/img/FortKnocks.jpeg)
### Background
User access controls and multifactor authentication are important, but what if the public-facing service itself has a pre-authentication vulnerability?  This tool implements a secure pre-authentication, pre-connection "knock" that dynamically adds the validated requestor's IP to a temporary allow list so they may connect to the protected service.
### Solution
#### The solution is comprised of Cloudflare workers that:
  - Authenticate client requests for time-limited access to a protected service
    - Includes strict brute force protection  
  - Produce a real-time IP allow list for a security device like a firewall to consume  
#### and a Chrome browser extension, Windows and MacOS scripts, and a Windows Task script that:
  - Clients run to authenticate against the Cloudflare Worker to receive time-limited access to the desired resource
    - To change the default of 8 hours, please refer to the "Troubleshooting" section of this document
### Prerequisites
1. A firewall that supports external IP threat feeds (most do, including Cisco, Palo Alto, Fortinet)
2. A Cloudflare account (https://www.cloudflare.com/)
   - Don't have one?  This solution can be deployed to even a free account!
### Cloudflare Setup
> **_NOTE:_**  Naming within these instructions assume you are protecting an SSLVPN service.  Adjust the names if desired.
1. Log in to your [Cloudflare dashboard](https://dash.cloudflare.com), choose your account, select "Storage & Databases" and click "KV."  
2. Click "Create a namespace," enter "SSLUSERS" for the name, and click "Add."
   - Add all valid usernames to this KV store; the key is the username (case insensitive) and the value can be any notes related to the user
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
#### Google Chrome (IPv6 only)
1. Download the latest release and place the /Plugin directory somewhere within your user home directory
2. Update manifest.json, adding your Worker URL to the host_permissions section
   - Example: "https://vpn-auth.organization.workers.dev/*"
   - _If you forget this step, the plugin will give you guidance when you attempt authentication_
3. Open Google Chrome and navigate to chrome://extensions
4. Enable Developer Mode
5. Click "Load Unpacked"
6. Navigate to the Plugin directory and click "Select Folder"
7. Authenticate by clicking on the puzzle icon at the right side of the address bar and selecting "Fort Knocks," entering a valid username and pre-shared key, and base URI (https://vpn-auth.organization.workers.dev for this example) when prompted
8. Attempt an SSLVPN connection to verify functionality  
#### Windows
1. Download SSLVPNAuth.ps1 to a Windows computer (Windows 10 1803 and later, as curl.exe is required)
2. Right-click the downloaded file, click "Properties"
3. Click "Unblock," then "OK"
4. Run SSLVPNAuth.ps1, entering a valid username and pre-shared key, and base URI (https://vpn-auth.organization.workers.dev for this example) when prompted
5. The PowerShell script will then complete a request and return the result
   - If authentication was successful, the client IP address should be added to the allowlist within 2 minutes
6. Attempt an SSLVPN connection to verify functionality
7. (optional) After a successful connection, you can configure automatic authentication on login, simply run Install-SSLVPNLoginTask.ps1 from the "/Windows Task" directory
#### MacOS
1. Download SSLVPNAuth.sh to a MacOS computer
2. In a terminal, navigate to the location of the SSLVPNAuth.sh script, then run:  
   ```chmod +x SSLVPNAuth.sh```
4. Run SSLVPNAuth.sh, entering a valid username and pre-shared key, and base URI (https://vpn-auth.organization.workers.dev for this example) when prompted
5. The shell script will then complete a request and return the result
   - If authentication was successful, the client IP address should be added to the allowlist within 2 minutes
6. Attempt an SSLVPN connection to verify functionality

### Advanced Features
#### Paranoid mode
- To help prevent dictionary attacks against hashed username request URLs, each source file has an admin-configurable salt value.  These must all match:
  - vpn_knocking.js line 112
  - background.js line 2
  - SSLVPNAuth.sh line 14
  - SSLVPNAuth.ps1 line 97
  - SSLVPNLoginTask.ps1 line 77

### Troubleshooting
#### Windows says the script cannot be loaded because running scripts is disabled on this system
- Run the following command in a PowerShell window:
  ```set-executionpolicy remotesigned -Scope CurrentUser```
#### I have a user that entered the wrong authentication details when running a client script and now they are rate-limited!
- This rate limiting feature prevents brute force attempts
- Once the user provides valid authentication details, the request will be processed as normal  
#### The Authorized IP list shows IPv4 addresses only and clients are connecting to my protected service via IPv6
- This solution assumes we are dealing with IPv4.  To allow IPv6 client addresses, simply remove the "-4" immediately following the curl.exe command in each of the client scripts.
#### I want to adjust the lifetime for successful authentication
- Change the expirationTtl value (in seconds) found on line 124 in vpn-knocking.js  
#### On Windows 11 the PowerShell script fails with a HTTP 000 code
- Update Windows!  In 2024, Microsoft compiled a buggy version of curl.exe in Windows.
#### Nothing is working
- Did you add valid usernames to the SSLUSERS KV store?  See step 2 under, "Cloudflare Setup"
- The pre-shared key value should be no more than 255 printable characters
