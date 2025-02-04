# Script to download and install webMethod on a Windows VM

# Read command line parameters
param (
    $jsonString
)

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
    Write-Host "Attempting to download webMethod Installer binary"
    [DownloadWithRetry]::DoDownloadWithRetry($($parameters.installerURL),5, 10, $null,  $webMethodsInstaller, $false)
} else {
    Write-Host "webMethod installer already exists on server"
}

# Create the script file
$scriptFile = ".\script-file"
if (-not(Test-Path -path $scriptFile)) {
    Write-Host "Creating script file"
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
    Write-Host "Script file already exists"
}

# Below requires a headless installation option for the webMethods installer which is not currently available.
# # Run the installer
# if ($($parameters.licenseAccepted )) {
#     Write-Host "Attempting to install base webMethods"
#     try {
#         cmd.exe /c $webMethodsInstaller -readScript $scriptFile 
#     } catch {
#         Write-Error "Failed to install webMethods"
#         Exit
#     }
# } else {
#     Write-Host "License not accepted. Not installing."
# }

# # Copy the installer to the install dir
# $webMethodDirectory = $($parameters.installDirectory).Replace("\:",":").Replace("\\","\") 
# Copy-Item -Path $webMethodsInstaller -Destination "$webMethodDirectory\install\bin\"

# # Clean up the script file
# Remove-Item -Path $scriptFile

# Move the installer and script to the admin users directory
New-Item -ItemType Directory -Force -Path C:\Users\$($parameters.vmUser)\webMethods
Move-Item $webMethodsInstaller C:\Users\$($parameters.vmUser)\webMethods
Move-Item $scriptFile C:\Users\$($parameters.vmUser)\webMethods

# Create the run script
New-Item -Path C:\Users\$($parameters.vmUser)\webMethods\runme.bat
Add-Content -Path C:\Users\$($parameters.vmUser)\webMethods\runme.bat "cmd.exe /c $webMethodInstaller -readScript $scriptFile"

# Create README file
New-Item -Path C:\Users\$($parameters.vmUser)\webMethods\README.txt
Add-Content -Path C:\Users\$($parameters.vmUser)\webMethods\README.txt "To complete installation, run the runme.bat file as an Administator."

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

 