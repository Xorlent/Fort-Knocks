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

function ConvertTo-UTF8Bytes {
    param([string]$InputString)
    $encoding = [System.Text.Encoding]::UTF8
    return $encoding.GetBytes($InputString)
}

function ConvertTo-HexString {
    param([byte[]]$Bytes)
    return [System.BitConverter]::ToString($Bytes).Replace("-", "").ToLower()
}

# Try to get stored credentials
$stored = Get-StoredCredentials

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

$Salt = 'default-salt-value'

# Create salted input
$saltedInput = "${username}:${Salt}"

# Convert to UTF-8 bytes
$bytes = ConvertTo-UTF8Bytes -InputString $saltedInput

# Calculate SHA-256 hash
$sha256 = [System.Security.Cryptography.SHA256]::Create()
$hashBytes = $sha256.ComputeHash($bytes)
$hashHex = ConvertTo-HexString -Bytes $hashBytes

# Construct the URL
$uri = "$baseUri/$hashHex"

# Force TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Make the request using curl with IPv4 flag
try {
    $response = curl.exe -4 -s -w "%{http_code}" -H "VPNAuth: $vpnAuth" $uri
    $httpResponse = $response.Trim()
    $httpResult = $httpResponse.Substring($httpResponse.Length - 3)

    Remove-Variable vpnAuth
    Remove-Variable uri
    Remove-Variable hashHex
    Remove-Variable hashBytes
    Remove-Variable saltedInput

    switch ($httpResult) {
        "200" {
            Write-Host "Success! Please wait up to 2 minutes before connecting to the SSLVPN. Your session will be valid for 8 hours." -ForegroundColor Green
        }
        "401" {
            Write-Host "Authentication failed. Invalid pre-shared key." -ForegroundColor Red
        }
        "404" {
            Write-Host "Invalid username hash or key not found." -ForegroundColor Red
        }
        "429" {
            Write-Host "Rate limit exceeded. Try again later." -ForegroundColor Yellow
        }
        default {
            Write-Host "Unexpected response from server (HTTP $httpCode)" -ForegroundColor Red
        }
    }
}
catch {
    Write-Host "Error occurred: $($_.Exception.Message)" -ForegroundColor Red
}
finally {
    [System.GC]::Collect()
}
