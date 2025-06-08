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
            exit 1
        }
    }
    exit 1
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

$username = $stored.Username
$vpnAuth = $stored.VPNAuth
$baseUri = $stored.URI

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

    if ($httpResult -eq "200") {
        exit 0
    } else {
        exit 1
    }
}
catch {
    exit 1
}
finally {
    [System.GC]::Collect()
}
