# Configuration file path
$configPath = Join-Path $env:USERPROFILE "vpn_config.xml"

function Get-EncryptedString {
    param([string]$plainText)
    
    $secureString = ConvertTo-SecureString -String $plainText -AsPlainText -Force
    $encrypted = ConvertFrom-SecureString $secureString
    return $encrypted
}

function Get-DecryptedString {
    param([string]$encryptedString)
    
    $secureString = ConvertTo-SecureString $encryptedString
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureString)
    $plainText = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    return $plainText
}

function Get-StoredCredentials {
    if (Test-Path $configPath) {
        try {
            $config = Import-Clixml -Path $configPath
            $username = Get-DecryptedString $config.Username
            $vpnAuth = Get-DecryptedString $config.VPNAuth
            $uri = Get-DecryptedString $config.URI
            return @{
                Username = $username
                VPNAuth = $vpnAuth
                URI = $uri
            }
        }
        catch {
            Write-Host "Error reading stored credentials. Will prompt for new ones." -ForegroundColor Yellow
            return $null
        }
    }
    return $null
}

function Save-Credentials {
    param(
        [string]$username,
        [string]$vpnAuth,
        [string]$uri
    )
    
    $config = @{
        Username = Get-EncryptedString $username
        VPNAuth = Get-EncryptedString $vpnAuth
        URI = Get-EncryptedString $uri
    }
    
    Export-Clixml -Path $configPath -InputObject $config -Force
    Write-Host "Credentials saved securely to $configPath" -ForegroundColor Green
}

# Try to get stored credentials
$stored = Get-StoredCredentials
$baseUri = ""

if ($stored) {
    $useStored = Read-Host "Found stored credentials. Use them? (Y/N)"
    if ($useStored.ToUpper() -eq 'Y') {
        $username = $stored.Username
        $vpnAuth = $stored.VPNAuth
        $baseUri = $stored.URI
    }
}

# If no stored credentials or user wants new ones, prompt
if (-not $stored -or $useStored.ToUpper() -ne 'Y') {
    $userentered = Read-Host "Enter username"
    $username = $userentered.ToLower()
    $vpnAuth = Read-Host "Enter pre-shared key"
    $baseUri = Read-Host "Enter request URL (e.g., https://vpn-auth.organization.workers.dev)"
    
    $saveCredentials = Read-Host "Save credentials for future use? (Y/N)"
    if ($saveCredentials.ToUpper() -eq 'Y') {
        Save-Credentials -username $username -vpnAuth $vpnAuth -uri $baseUri
    }
}

Remove-Variable stored

# Create SHA256 hash of username
$sha256 = New-Object System.Security.Cryptography.SHA256CryptoServiceProvider
$utf8 = New-Object System.Text.UTF8Encoding
$hash = [System.BitConverter]::ToString(
    $sha256.ComputeHash($utf8.GetBytes($username))
).Replace("-", "").ToLower()

Remove-Variable username

# Prepare the request
$uri = "$baseUri/$hash"
$headers = @{
    "VPNAuth" = $vpnAuth
}

Remove-Variable vpnAuth

# Force TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

try {
    # Make the request using curl with IPv4 flag
    $response = curl.exe -4 -s -w "%{http_code}" -H "VPNAuth: $vpnAuth" $uri
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Success! Please wait up to 2 minutes before connecting to the SSLVPN.  Your session will be valid for 8 hours." -ForegroundColor Green
        Read-Host -Prompt "Press ENTER to exit."
        [System.GC]::Collect()
    } else {
        [System.GC]::Collect()
        throw "Curl request failed with exit code $LASTEXITCODE"
    }
}
catch {
    # Check if the error message contains common HTTP status codes
    if ($response -match "401") {
        Write-Host "Authentication failed. Invalid pre-shared key." -ForegroundColor Red
    }
    elseif ($response -match "429") {
        Write-Host "Rate limit exceeded. Successful requests are valid for 8 hours." -ForegroundColor Yellow
    }
    elseif ($response -match "404") {
        Write-Host "Invalid username hash or key not found." -ForegroundColor Red
    }
    else {
        Write-Host "Error occurred: $($_.Exception.Message)" -ForegroundColor Red
    }
    Read-Host -Prompt "Press ENTER to exit."
}
