param (
    [string]$adminUsername
)

[System.Environment]::SetEnvironmentVariable('adminUsername', $adminUsername,[System.EnvironmentVariableTarget]::Machine)

$CdRomDriveLetter = "F:"
$CdRomCurrentLetter = (Get-WmiObject -Class Win32_CDROMDrive).Drive
$CdRomVolumeName = mountvol $CdRomCurrentLetter /l
$CdRomVolumeName = $CdRomVolumeName.Trim()
mountvol $CdRomCurrentLetter /d
mountvol $CdRomDriveLetter $CdRomVolumeName

$PartitionStyle = (Get-Disk | Where Number -eq 1).PartitionStyle
if ($PartitionStyle -ne "MBR"){
    Get-Disk |
    Where Number -eq 1 |
    Initialize-Disk -PartitionStyle MBR -PassThru |
    New-Partition -AssignDriveLetter -UseMaximumSize |
    Format-Volume -FileSystem NTFS -NewFileSystemLabel "Data Drive" -Confirm:$false    
}

$chocolateyAppList = "az.powershell,azure-cli,sql-server-management-studio,git,powerbi,powerbi-reportbuilder"

Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))

if ([string]::IsNullOrWhiteSpace($chocolateyAppList) -eq $false){   
    Write-Host "Chocolatey Apps Specified"  

    $appsToInstall = $chocolateyAppList -split "," | foreach { "$($_.Trim())" }

    foreach ($app in $appsToInstall)
    {
        Write-Host "Installing $app"
        & choco install $app -y --ignore-checksums
    }
}

Set-Location D:\

New-Item -Path "C:\" -Name "tmp" -ItemType "directory"

New-Item -Path "D:\" -Name "temp" -ItemType "directory"

Set-Location D:\temp

Start-Process -FilePath "c:\program files\git\bin\git.exe" -ArgumentList "clone https://github.com/MicrosoftLearning/DA-100-Analyzing-Data-with-Power-BI.git" -NoNewWindow -Wait

Move-Item -Path D:\temp\DA-100-Analyzing-Data-with-Power-BI\Allfiles\DA-100-Allfiles -Destination D:\DA-100

Set-Location D:\

Remove-Item -Path D:\temp -Recurse -Force

# Creating PowerShell Logon Script
$LogonScript = @'
Start-Transcript -Path C:\tmp\LogonScript.log

Write-Host "Installing SQL Server and PowerShell Module"
If(-not(Get-InstalledModule SQLServer -ErrorAction silentlycontinue)){
    Install-Module SQLServer -Confirm:$False -Force
}
choco install sql-server-2019 -y --params="'/IgnorePendingReboot /INSTANCENAME=MSSQLSERVER'"
Set-Service -Name SQLBrowser -StartupType Automatic
Start-Service -Name SQLBrowser
Write-Host "Enable SQL TCP"
$env:PSModulePath = $env:PSModulePath + ";C:\Program Files (x86)\Microsoft SQL Server\150\Tools\PowerShell\Modules"
Import-Module -Name "sqlps"
$smo = 'Microsoft.SqlServer.Management.Smo.'  
$wmi = new-object ($smo + 'Wmi.ManagedComputer').  
# List the object properties, including the instance names.  
$Wmi
# Enable the TCP protocol on the default instance.  
$uri = "ManagedComputer[@Name='" + (get-item env:\computername).Value + "']/ServerInstance[@Name='MSSQLSERVER']/ServerProtocol[@Name='Tcp']" 
$Tcp = $wmi.GetSmoObject($uri)  
$Tcp.IsEnabled = $true  
$Tcp.Alter()  
$Tcp
# Enable the named pipes protocol for the default instance.  
$uri = "ManagedComputer[@Name='" + (get-item env:\computername).Value + "']/ServerInstance[@Name='MSSQLSERVER']/ServerProtocol[@Name='Np']"  
$Np = $wmi.GetSmoObject($uri)  
$Np.IsEnabled = $true  
$Np.Alter()  
$Np
Restart-Service -Name 'MSSQLSERVER'
Unregister-ScheduledTask -TaskName "LogonScript" -Confirm:$False
'@ > C:\tmp\LogonScript.ps1

# Creating LogonScript Windows Scheduled Task
$Trigger = New-ScheduledTaskTrigger -AtLogOn
$Action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument 'C:\tmp\LogonScript.ps1'
Register-ScheduledTask -TaskName "LogonScript" -Trigger $Trigger -User "${adminUsername}" -Action $Action -RunLevel "Highest" -Force

# Disabling Windows Server Manager Scheduled Task
Get-ScheduledTask -TaskName ServerManager | Disable-ScheduledTask
