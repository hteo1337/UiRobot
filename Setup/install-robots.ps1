function Main {
    Param (
        [Parameter(Mandatory=$true)]
        [String]$orchestratorUrl,

        [Parameter(Mandatory=$true)]
        [String]$Tennant,

        [Parameter(Mandatory=$true)]
        [String] $orchAdmin,

        [Parameter(Mandatory=$true)]
        [String] $orchPassword,

	[Parameter()]
        [AllowEmptyString()]
        [String] $HostingType,

	[Parameter()]
        [AllowEmptyString()]
        [String] $RobotType

    )


    #define TLS for Invoke-WebRequest
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12


    #setup temp dir in %appdata%\Local\Temp
    $script:tempDirectory = (Join-Path $ENV:TEMP "UiPath-$(Get-Date -f "yyyyMMddhhmmssfff")")
    New-Item -ItemType Directory -Path $script:tempDirectory | Out-Null

    #download UiPlatform
    $msiName = 'UiPathPlatform.msi'
    $msiPath = Join-Path $script:tempDirectory $msiName
    Download-File -url "https://download.uipath.com/UiPathStudio.msi" -outputFile $msiPath

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
    #$robotExePath = [System.IO.Path]::Combine(${ENV:ProgramFiles(x86)}, "UiPath", "Studio", "UiRobot.exe")

    $robotExePath = Get-UiRobotExePath  -community:$community

    # start-process -filepath $robotExePath -verb runas


   $roboConnect = ConnectTo-Orchestrator-Perf -orchestratorUrl $orchestratorUrl -robotExePath $robotExePath -Tennant $Tennant -adminUsername $orchAdmin -orchPassword $orchPassword -HostingType $HostingType -RobotType $RobotType

    Write-Output $roboConnect

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

function ConnectTo-Orchestrator-Perf {

    param(
        [Parameter(Mandatory = $true)]
        [string] $robotExePath,

        [Parameter()]
        [AllowEmptyString()]
        [string] $orchestratorUrl,

		[Parameter()]
        [AllowEmptyString()]
        [string] $Tennant,

		[Parameter()]
        [AllowEmptyString()]
        [string] $adminUsername,

		[Parameter()]
        [AllowEmptyString()]
        [string] $orchPassword,

		[Parameter()]
        [AllowEmptyString()]
        [string] $HostingType,

		[Parameter()]
        [AllowEmptyString()]
        [string] $RobotType

    )

    if (!(Test-Path $robotExePath)) {
        throw "No UiRobot.exe file found at '$robotExePath'"
    }

	$dataLogin = @{
       tenancyName = $Tennant
       usernameOrEmailAddress = $adminUsername
       password = $orchPassword
       rememberMe = $true
       } | ConvertTo-Json
   Write-Host "**********************"
   $orchUrl_login = "$orchestratorUrl/account/login"
   Write-Host $orchUrl_login

   # login API call to get the login session used for all requests
   $webresponse = Invoke-WebRequest -Uri $orchUrl_login -Method Post -Body $dataLogin -ContentType "application/json" -UseBasicParsing -Session websession


   $cookies = $websession.Cookies.GetCookies($orchUrl_login)

   $dataRobot = @{
    MachineName = $env:computername
    Username = $adminUsername
    Type = $RobotType
    HostingType = $HostingType
    Password = $orchPassword
    Name = $env:computername
    ExecutionSettings=@{}} | ConvertTo-Json

    $orch_bot = "$orchestratorUrl/odata/Robots"
    Write-Host $orch_bot

    $webresponse = Invoke-RestMethod -Uri $orch_bot -Method Post -Body $dataRobot -ContentType "application/json" -UseBasicParsing -WebSession $websession
    $key = $webresponse.LicenseKey
    Write-Host $key
    &    $robotExePath --connect -url  $orchestratorUrl -key $key
	}


Main
