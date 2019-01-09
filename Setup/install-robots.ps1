function Main {
    #setup temp dir in %appdata%\Local\Temp
    $script:tempDirectory = (Join-Path $ENV:TEMP "UiPath-$(Get-Date -f "yyyyMMddhhmmssfff")")
    New-Item -ItemType Directory -Path $script:tempDirectory | Out-Null

    #download UiPlatform
    $msiName = 'UiPathPlatform.msi'
    $msiPath = Join-Path $script:tempDirectory $msiName
    Download-File -url "https://download.uipath.com/versions/18.2.4/UiPathPlatform.msi" -outputFile $msiPath
    
    #install the Robot
    $msiFeatures = @("DesktopFeature","Robot","StartupLauncher","RegisterService","Packages")
    
    $installResult = Install-Robot -msiPath $msiPath -msiFeatures $msiFeatures 

        if ($installResult.MSIExecProcess.ExitCode -ne 0) {
                Write-Error "The msiexec process returned a non-zero exit code: $($installResult.MSIExecProcess.ExitCode). Please check the msiexec logs for more details: '$($installResult.LogPath)'"
                Write-Output $installResult
                Write-Debug (Get-Content $installResult.LogPath)
                Exit ($installResult.MSIExecProcess.ExitCode)
            }
    #starting Robot       
    $robotExePath = [System.IO.Path]::Combine(${ENV:ProgramFiles(x86)}, "UiPath", "Studio", "UiRobot.exe")
    
    start-process -filepath $robotExePath -verb runas

    #remove temp directory
    Write-Verbose "Removing temp directory $($script:tempDirectory)"
    Remove-Item $script:tempDirectory -Recurse -Force | Out-Null

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
Downloads a file from a URL

.PARAMETER url
The URL to download from

.PARAMETER outputFile
The local path where the file will be downloaded
#>
function Download-File {
    param (
        [Parameter(Mandatory = $true)]
        [string]$url,

        [Parameter(Mandatory = $true)]
        [string] $outputFile
    )

    Write-Verbose "Downloading file from $url to local path $outputFile"

    $webClient = New-Object System.Net.WebClient

    $webClient.DownloadFile($url,$outputFile)
    
}

function Install-Robot {

    param (
        [Parameter(Mandatory = $true)]
        [string] $msiPath,

        [string] $installationFolder,

        [string[]] $msiFeatures
    )

    if (!$msiProperties) {
        $msiProperties = @{}
    }


    if ($installationFolder) {
        $msiProperties["APPLICATIONFOLDER"] = $installationFolder;
    }

    $logPath = Join-Path $script:tempDirectory "install.log"

    Write-Verbose "Installing UiPath"

    $process = Invoke-MSIExec -msiPath $msiPath -logPath $logPath -features $msiFeatures

    return @{
        LogPath = $logPath;
        MSIExecProcess = $process;
    }
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
