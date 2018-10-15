Import-Module ServerManager -ErrorAction Stop

$win2k8xml = '.\features-w2k8.xml'
$win2k12xml = '.\RolesAndFeatures.xml'


$minOSVersion = [version] "6.1.7600" # Windows Server 2008 R2 RTM version
$os = Get-WmiObject Win32_OperatingSystem
$currentVersion = [version]$os.Version

if($currentVersion -lt $minOSVersion)
{
    throw "OS version equal or greater than ${minOSVersion} is required to run this script"
}
elseif($currentVersion.ToString().substring(0,3) -eq $minOSVersion.ToString().substring(0,3))
{
If (!(Test-Path $win2k8xml)) {Write-Host "For Windows Server 2008 R2 server make sure that you have Features-W2K8.xml in the current folder" -ForegroundColor Yellow; Pause}
}
elseif($currentVersion -gt $minOSVersion){                                                            

If (!(Test-Path $win2k12xml)) {Write-Host "For Windows Server 2012/2016 make sure that you have RolesAndFeatures.xml in the current folder" -ForegroundColor Yellow; Pause}
}

$OSVersionName = (get-itemproperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name ProductName).ProductName
Write-Host "Your OS version is:$OSVersionName" -ForegroundColor Green

$defaultComputerName = $env:computername
$ComputerName = Read-Host "Computername (Press Enter for current computer - $defaultComputerName)"


if ([string]::IsNullOrEmpty($ComputerName))
{
	$ComputerName = $defaultComputerName;
}

Write-host "Installation will take place on the following computers: $ComputerName"



function Invoke-WindowsFeatureBatchDeployment {
    param (
        [parameter(mandatory)]
        [string] $ComputerName,
        [parameter(mandatory)]
        [string] $ConfigurationFilePath
    )
   
    # Deploy the features on multiple computers simultaneously.
    $jobs = @()
	if(Test-Connection -ComputerName $ComputerName -Quiet){
		Write-Host "Connection succeeded to: " $ComputerName
        
        if ($currentVersion.ToString().substring(0,3) -eq $minOSVersion.ToString().substring(0,3)) {
        $jobs += Start-Job -Command {
		#Add-WindowsFeature -ConfigurationFilePath $using:ConfigurationFilePath -ComputerName $using:ComputerName -Restart
        $import = Import-Clixml $using:ConfigurationFilePath
        $import | Add-WindowsFeature
	    } 
        } 
        elseif ($currentVersion -gt $minOSVersion) {
		$jobs += Start-Job -Command {
		Install-WindowsFeature -ConfigurationFilePath $using:ConfigurationFilePath -ComputerName $using:ComputerName -Restart
		} 
        }    
  
	}
	else{
		Write-Host "Configuration failed for: "+ $ComputerName + "! Check computer name and execute again"
	}
        
    
    Receive-Job -Job $jobs -Wait | Select-Object Success, RestartNeeded, ExitCode, FeatureResult
}
if ($currentVersion.ToString().substring(0,3) -eq $minOSVersion.ToString().substring(0,3)) {$FilePath = Resolve-Path $win2k8xml}
elseif ($currentVersion -gt $minOSVersion) {$FilePath = Resolve-Path $win2k12xml}

Invoke-WindowsFeatureBatchDeployment $ComputerName $FilePath

