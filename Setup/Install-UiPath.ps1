<#
.DESCRIPTION
Downloads and installes the latest UiPath version (or a specific version). You can use the -beta switch if you like :)

.PARAMETER licenseCode
The license code with which the UiPath product will be activated

.PARAMETER version
The UiPath version that needs to be installed. Wildcards are allowed. If not specified, the latest version will be installed

.PARAMETER component
The UiPath component that will be installed (Studio or Orchestrator). Defaults to Studio

.PARAMETER beta
If the latest available UiPath beta should be installed

.PARAMETER community
If the UiPath Studio Community edition should be installed

.PARAMETER orchestratorUrl
If specified along with -machineKey, connects the robot to the respective Orchestrator instance

.PARAMETER machineKey
If specified along with -orchestratorUrl, connects the robot to the respective Orchestrator instance

.PARAMETER orchestratorConnectionString
If specified, connects the robot to the respective Orchestrator instance

.PARAMETER cleanup
If any installation log files generated during this execution should be deleted afterwards

#>
[CmdletBinding(
    DefaultParameterSetName = "Install"
)]
param(

    [Parameter(ParameterSetName = "Install", Mandatory = $true)]
    [Parameter(ParameterSetName = "ConnectToOrchestrator", Mandatory = $true)]
    [Parameter(ParameterSetName = "ConnectToOrchestratorWithMachineKey", Mandatory = $true)]
    [Parameter(ParameterSetName = "ConnectToOrchestratorWithConnectionString", Mandatory = $true)]
    [string] $licenseCode,

    [Parameter(ParameterSetName = "Install")]
    [string] $version,

    [Parameter(ParameterSetName = "Install")]
    [ValidateSet("Studio", "Orchestrator")]
    [string] $component = "Studio",

    [Parameter(ParameterSetName = "Install")]
    [switch] $beta,

    [Parameter(ParameterSetName = "Install")]
    [switch] $community,

    [Parameter(ParameterSetName = "Install")]
    [int] $communityInstallTimeoutSeconds = 30,

    [Parameter(ParameterSetName = "Install")]
    [Parameter(ParameterSetName = "ConnectToOrchestratorWithMachineKey", Mandatory = $true)]
    [string] $orchestratorUrl,

    [Parameter(ParameterSetName = "Install")]
    [Parameter(ParameterSetName = "ConnectToOrchestratorWithMachineKey", Mandatory = $true)]
    [string] $machineKey,

    [Parameter(ParameterSetName = "Install")]
    [Parameter(ParameterSetName = "ConnectToOrchestratorWithConnectionString", Mandatory = $true)]
    [string] $orchestratorConnectionString,

    [Parameter(ParameterSetName = "Install")]
    [Parameter(ParameterSetName = "ConnectToOrchestratorWithMachineKey")]
    [Parameter(ParameterSetName = "ConnectToOrchestratorWithConnectionString")]
    [switch] $cleanup
)

$ErrorActionPreference = "Stop"

function Main {

    $script:tempDirectory = (Join-Path $ENV:TEMP "ui$(Get-Date -f "yyyyMMddhhmmssfff")")

    New-Item -ItemType Directory -Path $script:tempDirectory | Out-Null

    $installerName = Get-UiPathInstallerName -version $version -component $component -community:$community
    $installerPath = Join-Path $script:tempDirectory $installerName

    Download-UiPathInstaller -version $version -component $component -outputPath $installerPath -beta:$beta -community:$community | Out-Null

    if ($community) {

        $process = Install-UiPathStudioCommunity -studioInstallerPath $installerPath

        if ($process.ExitCode -and $process.ExitCode -ne 0) {
            Write-Error "The UiPath Studio setup process returned a non-zero exit code: $($process.ExitCode)."
            Exit ($process.ExitCode)
        }
        
    } else {

        $msiFeatures = @(
            "DesktopFeature",
            "Robot",
            "Studio",
            "StartupLauncher",
            "RegisterService",
            "Packages"
        )

        $installResult = Install-UiPathEnterprise -msiPath $installerPath -licenseCode $licenseCode -msiFeatures $msiFeatures

        if ($installResult.MSIExecProcess.ExitCode -ne 0) {
            Write-Error "The msiexec process returned a non-zero exit code: $($installResult.MSIExecProcess.ExitCode). Please check the msiexec logs for more details: '$($installResult.LogPath)'"
            Write-Output $installResult
            Write-Debug (Get-Content $installResult.LogPath)
            Exit ($installResult.MSIExecProcess.ExitCode)
        }
    }

    $shouldConnect = $orchestratorUrl -or $orchestratorConnectionString
    $connectionData = $null

    if ($shouldConnect) {
        
        $robotExePath = Get-UiRobotExePath -community:$community
    
        $connectionData = ConnectTo-Orchestrator -orchestratorUrl $orchestratorUrl -machineKey $machineKey -orchestratorConnectionString $orchestratorConnectionString -robotExePath $robotExePath
    }

    Write-Output $installResult
    Write-Output $connectionData

    if ($cleanup) {
        Write-Verbose "Removing temp directory $($script:tempDirectory)"
        Remove-Item $script:tempDirectory -Recurse -Force | Out-Null
    }
}

<#
.DESCRIPTION
Installs an MSI by calling msiexec.exe, with verbose logging

.PARAMETER msiPath
Path to the MSI to be installed

.PARAMETER logPath
Path to a file where the MSI execution will be logged via "msiexec [...] /lv*"

.PARAMETER features
A list of features that will be installed via ADDLOCAL="..."

.PARAMETER properties
Additional MSI properties to be passed to msiexec
#>
function Invoke-MSIExec {

    param (
        [Parameter(Mandatory = $true)]
        [string] $msiPath,
        
        [Parameter(Mandatory = $true)]
        [string] $logPath,

        [string[]] $features,

        [System.Collections.Hashtable] $properties
    )

    if (!(Test-Path $msiPath)) {
        throw "No .msi file found at path '$msiPath'"
    }

    $msiExecArgs = "/i `"$msiPath`" /q /lv* `"$logPath`" "

    if ($features) {
        $msiExecArgs += "ADDLOCAL=`"$($features -join ',')`" "
    }

    if ($properties) {
        $msiExecArgs += (($properties.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join " ")
    }

    $process = Start-Process "msiexec" -ArgumentList $msiExecArgs -Wait -PassThru

    return $process
}

<#
.DESCRIPTION
Installs UiPath by calling Invoke-MSIExec

.PARAMETER msiPath
Path to the MSI to be installed

.PARAMETER installationFolder
Where UiPath will be installed

.PARAMETER licenseCode
License code used to activate Studio

.PARAMETER msiFeatures
A list of MSI features to pass to Invoke-MSIExec

.PARAMETER msiProperties
A list of MSI properties to pass to Invoke-MSIExec
#>
function Install-UiPathEnterprise {

    param (
        [Parameter(Mandatory = $true)]
        [string] $msiPath,

        [string] $installationFolder,

        [string] $licenseCode,

        [string[]] $msiFeatures,

        [System.Collections.Hashtable] $msiProperties
    )

    if (!$msiProperties) {
        $msiProperties = @{}
    }

    if ($licenseCode) {
        $msiProperties["CODE"] = $licenseCode;
    }

    if ($installationFolder) {
        $msiProperties["APPLICATIONFOLDER"] = $installationFolder;
    }

    $logPath = Join-Path $script:tempDirectory "install.log"

    Write-Verbose "Installing UiPath"

    $process = Invoke-MSIExec -msiPath $msiPath -logPath $logPath -features $msiFeatures -properties $msiProperties

    return @{
        LogPath = $logPath;
        MSIExecProcess = $process;
    }
}


<#
.DESCRIPTION
Installs UiPath Studio Community edition by calling UiPathStudioSetup.exe

.PARAMETER studioInstallerPath
Path to UiPathStudioSetup.exe
#>
function Install-UiPathStudioCommunity {

    param(
        [Parameter(Mandatory = $true)]
        [string] $studioInstallerPath
    )
    
    if (!(Test-Path $studioInstallerPath)) {
        throw "No Studio installer was found at '$studioInstallerPath'"
    }

    Write-Verbose "Installing Community Studio"

    $process = Start-Process $studioInstallerPath -ArgumentList @("--machine", "--silent") -Wait -NoNewWindow -PassThru

    if ($process.HasExited -and $process.ExitCode -ne 0) {
        $processErrors = $process.StandardError.ReadToEnd()
        throw "An error has occured while installing Studio Community:`n$processErrors"
    }

    if (Get-Process "UiPathStudioSetup" -ErrorAction "SilentlyContinue") {
        Wait-Process "UiPathStudioSetup"
    } else {
        Start-Sleep -Seconds $communityInstallTimeoutSeconds
    }

    return $process
}

<#
.DESCRIPTION
Gets the name of the UiPath installer, depending on the version, component and edition

.PARAMETER version
The version of UiPath

.PARAMETER component
The UiPath component (Studio or Orchestrator)

.PARAMETER community
If the component is Studio Community edition. Can only be used when -component is "Studio"
#>
function Get-UiPathInstallerName {

    param(
        [string] $version,

        [ValidateSet("Studio", "Orchestrator")]
        [string] $component = "Studio",

        [switch] $community
    )

    # Only Studio has a Community edition
    if ($community -and $component -ne "Studio") {
        throw "Only Studio has a Community edition"
    }

    if ($community) {
        return "UiPathStudioSetup.exe"
    }

    $platformMsiName = "UiPathPlatform.msi"
    $componentMsiNames = @{
        Studio = "UiPathStudio.msi";
        Orchestrator = "UiPathOrchestrator.msi";
    }

    if (!$version) {
        return $componentMsiNames."$component"
    }

    $versionParts = $version -split "\."
    $versionMajor = [int]::Parse($versionParts[0])
    $versionMinor = [int]::Parse($versionParts[1])

    # If it's 18.x or more, use individual component MSI name
    if (($versionMajor -ge 18) -and ($versionMinor -ge 3) -and ($versionMajor -lt 2000)) {
        return $componentMsiNames."$component"
    }

    # If it's 2016.x, use Studio's MSI name. Careful, because there was no Orchestrator MSI in 2016.x
    if ($versionMajor -eq 2016) {

        if ($component -eq "Orchestrator") {
            throw "There was no Orchestrator MSI in 2016.x"
        } else {
            return $componentMsiNames["Studio"]
        }
    }

    return $platformMsiName
}

<#
.DESCRIPTION
Gets the path to the UiRobot.exe file

.PARAMETER community
Whether to search for the UiPath Studio Community edition executable
#>
function Get-UiRobotExePath {

    param(
        [switch] $community
    )

    $robotExePath = [System.IO.Path]::Combine(${ENV:ProgramFiles(x86)}, "UiPath", "Studio", "UiRobot.exe")

    if ($community) {
        $robotExePath = Get-ChildItem ([System.IO.Path]::Combine($ENV:LOCALAPPDATA, "UiPath")) -Recurse -Include "UiRobot.exe" | `
            Select-Object -ExpandProperty FullName -Last 1
    }

    return $robotExePath
}

<#
.DESCRIPTION
Downloads the UiPath installer from the web

.PARAMETER outputPath
The local path where the installer will be downloaded

.PARAMETER version
The UiPath version that needs to be downloaded. Wildcards are allowed. If not specified, the latest version will be downloaded

.PARAMETER component
The UiPath component that will be downloaded (Studio or Orchestrator). Defaults to Studio

.PARAMETER beta
If the latest available UiPath beta should be downloaded
#>
function Download-UiPathInstaller {

    param(
        [string] $outputPath,

        [string] $version,

        [ValidateSet("Studio", "Orchestrator")]
        [string] $component = "Studio",

        [switch] $beta,

        [switch] $community
    )

    $installerName = Get-UiPathInstallerName -version $version -component $component -community:$community

    if (!$outputPath) {
        $outputPath = Join-Path $script:tempDirectory $installerName
    }

    if ($beta) {
        Download-File -url "https://download.uipath.com/beta/$installerName" -outputFile $outputPath
        return $outputPath
    }

    if (!$version) {
        Download-File -url "https://download.uipath.com/$installerName" -outputFile $outputPath
        return $outputPath
    }

    $versionsJsonPath = Join-Path $script:tempDirectory "versions.json"
    $versionsJsonUrl = "https://download.uipath.com/versions.json"

    Download-File -url $versionsJsonUrl -outputFile $versionsJsonPath

    $versionsInfo = ConvertFrom-Json -InputObject ([System.IO.File]::ReadAllText($versionsJsonPath))

    $versionInfo = $versionsInfo.versions | `
        Where-Object {
            $_.version -like $version
        } | `
        Select-Object -First 1

    if (!$versionInfo) {
        throw "No UiPath version matching '$version' is available for download"
    }

    Write-Verbose "Found version $($versionInfo.version) matching '$version'"

    $fileInfo = $versionInfo.files | `
        Where-Object {
            $_.fileName -eq $installerName
        } | `
        Select-Object -First 1

    if (!$fileInfo) {
        throw "No file matching installer name '$installerName' is available for download for selected version $($versionInfo.version)"
    }

    if (!$fileInfo.blobUri) {
        throw "The file info object doesn't have the expected structure. Missing property 'blobUri'"
    }

    Download-File -url $fileInfo.blobUri -outputFile $outputPath

    return $outputPath
}

<#
.DESCRIPTION
Downloads a file from a URL

.PARAMETER url
The URL to download from

.PARAMETER outputFile
The local path where the file will be downloaded
#>
function Download-File {

    param(
        [Parameter(Mandatory = $true)]
        [string] $url,

        [Parameter(Mandatory = $true)]
        [string] $outputFile
    )

    Write-Verbose "Downloading file from $url to local path $outputFile"

    $webClient = New-Object System.Net.WebClient
    
    $webClient.DownloadFile($url, $outputFile)
}

<#
.DESCRIPTION
Connects the robot to an Orchestrator instance
#>
function ConnectTo-Orchestrator {

    param(
        [Parameter(Mandatory = $true)]
        [string] $robotExePath,

        [Parameter()]
        [AllowEmptyString()]
        [string] $orchestratorUrl,

        [Parameter()]
        [AllowEmptyString()]
        [string] $machineKey,

        [Parameter()]
        [AllowEmptyString()]
        [string] $orchestratorConnectionString
    )

    if (!(Test-Path $robotExePath)) {
        throw "No UiRobot.exe file found at '$robotExePath'"
    }

    $connectionResult = if ($orchestratorConnectionString) {
        Write-Verbose "Connecting robot to Orchestrator at $orchestratorConnectionString"
        & $robotExePath --connect -connectionString "$orchestratorConnectionString"
    } else {
        Write-Verbose "Connecting robot to Orchestrator at $orchestratorUrl with key $machineKey"
        & $robotExePath --connect -url "$orchestratorUrl" -key "$machineKey"
    }

    return $connectionResult
}

Main
