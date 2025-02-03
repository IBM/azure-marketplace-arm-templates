# Script to download and install webMethod on a Windows VM
# Read the parameters file
try {
    $jsonString = Get-Content '.\parameters.json' | Out-String
} catch {
    Write-Error "Unable to read parameters file $_"
    Exit
} 

# Convert input parameter to object
try {
    $parameters = $jsonString | ConvertFrom-Json
} catch {
    Write-Error "Error parsing JSON $_"
    Exit
}

# Download webMethod installer binary
$webMethodsInstaller = ".\$($parameters.installerName)"
if (-not(Test-Path -path $webMethodsInstaller)) {
    Write-Output "Attempting to download webMethod Installer binary"
    [DownloadWithRetry]::DoDownloadWithRetry($($parameters.installerURL),5, 10, $null,  $webMethodsInstaller, $false)
} else {
    Write-Output "webMethod installer already exists on server"
}

# Create the script file
$scriptFile = ".\script-file"
if (-not(Test-Path -path $scriptFile)) {
    Write-Output "Creating script file"
    New-Item -Path $scriptFile
    Add-Content -Path $scriptFile "ServerURL=$($parameters.wmServerUrl)"
    Add-Content -Path $scriptFile "selectedFixes=$($parameters.selectedFixes)"
    Add-Content -Path $scriptFile "Username=$($parameters.emailAddress)"
    Add-Content -Path $scriptFile "StartMenuFolder=Software AG"
    Add-Content -Path $scriptFile "HostName=$env:computername"
    Add-Content -Path $scriptFile "InstallProducts=$($parameters.installProducts)"
    Add-Content -Path $scriptFile "Password=$($parameters.entitlementKey)"
    Add-Content -Path $scriptFile "InstallDir=$($parameters.installDirectory)"
} else {
    Write-Output "Script file already exists"
}

# Run the installer
if ($($parameters.licenseAccepted )) {
    Write-Output "Attempting to install base webMethods"
    try {
        cmd.exe /c $webMethodsInstaller -readScript $scriptFile 
    } catch {
        Write-Error "Failed to install webMethods"
        Exit
    }
} else {
    Write-Output "License not accepted. Not installing."
}

# Copy the installer to the install dir
$webMethodDirectory = $($parameters.installDirectory).Replace("\:",":").Replace("\\","\") 
Copy-Item -Path $webMethodsInstaller -Destination "$webMethodDirectory\install\bin\"

# Clean up the script file
Remove-Item -Path $scriptFile

class DownloadWithRetry {
    static [string] DoDownloadWithRetry([string] $uri, [int] $maxRetries, [int] $retryWaitInSeconds, [string] $authToken, [string] $outFile, [bool] $metadata) {
        $retryCount = 0
        $headers = @{}
        if (-not ([string]::IsNullOrEmpty($authToken))) {
            $headers = @{
                'Authorization' = $authToken
            }
        }
        if ($metadata) {
            $headers.Add('Metadata', 'true')
        }

        while ($retryCount -le $maxRetries) {
            try {
                if ($headers.Count -ne 0) {
                    if ([string]::IsNullOrEmpty($outFile)) {
                        $result = Invoke-WebRequest -Uri $uri -Headers $headers -UseBasicParsing
                        return $result.Content
                    }
                    else {
                        $result = Invoke-WebRequest -Uri $uri -Headers $headers -UseBasicParsing -OutFile $outFile
                        return ""
                    }
                }
                else {
                    throw;
                }
            }
            catch {
                if ($headers.Count -ne 0) {
                    write-host "download of $uri failed"
                }
                try {
                    if ([string]::IsNullOrEmpty($outFile)) {
                        $result = Invoke-WebRequest -Uri $uri -UseBasicParsing
                        return $result.Content
                    }
                    else {
                        $result = Invoke-WebRequest -Uri $uri -UseBasicParsing -OutFile $outFile
                        return ""
                    }
                }
                catch {
                    write-host "download of $uri failed"
                    $retryCount++;
                    if ($retryCount -le $maxRetries) {
                        Start-Sleep -Seconds $retryWaitInSeconds
                    }            
                }
            }
        }
        return ""
    }
}

 