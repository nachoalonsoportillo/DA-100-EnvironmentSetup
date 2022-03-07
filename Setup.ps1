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

New-Item -Path "D:\" -Name "temp" -ItemType "directory"

Set-Location D:\temp

Start-Process -FilePath "c:\program files\git\bin\git.exe" -ArgumentList "clone https://github.com/MicrosoftLearning/DA-100-Analyzing-Data-with-Power-BI.git" -NoNewWindow -Wait

Move-Item -Path D:\temp\DA-100-Analyzing-Data-with-Power-BI\Allfiles\DA-100-Allfiles -Destination D:\DA-100

Set-Location D:\

Remove-Item -Path D:\temp -Recurse -Force

New-Item -Path "C:\" -Name "tmp" -ItemType "directory"

$LogonScript = @'
Start-Transcript -Path C:\tmp\LogonScript.log
Install-PackageProvider -Name "NuGet" -RequiredVersion "2.8.5.216" -Force
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

$Wmi

$uri = "ManagedComputer[@Name='" + (get-item env:\computername).Value + "']/ServerInstance[@Name='MSSQLSERVER']/ServerProtocol[@Name='Tcp']" 
$Tcp = $wmi.GetSmoObject($uri)  
$Tcp.IsEnabled = $true  
$Tcp.Alter()  
$Tcp

$uri = "ManagedComputer[@Name='" + (get-item env:\computername).Value + "']/ServerInstance[@Name='MSSQLSERVER']/ServerProtocol[@Name='Np']"  
$Np = $wmi.GetSmoObject($uri)  
$Np.IsEnabled = $true  
$Np.Alter()  
$Np
Restart-Service -Name 'MSSQLSERVER'

Invoke-Sqlcmd -ServerInstance . -Database master -Query "RESTORE DATABASE  [TailspinToys2020-US] FROM  DISK = N'D:\DA-100\DatabaseBackup\TailspinToys2020-US.bak' WITH  FILE = 1,  NOUNLOAD,  STATS = 5"
Invoke-Sqlcmd -ServerInstance . -Database master -Query "RESTORE DATABASE [AdventureWorksDW2020] FROM  DISK = N'D:\DA-100\DatabaseBackup\AdventureWorksDW2020.bak' WITH  FILE = 1,  MOVE N'AdventureWorksDW2020' TO N'C:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\DATA\AdventureWorksDW2020.mdf',  MOVE N'AdventureWorksDW2020_Log' TO N'C:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\DATA\AdventureWorksDW2020_Log.ldf',  NOUNLOAD,  STATS = 5"

Unregister-ScheduledTask -TaskName "LogonScript" -Confirm:$False
'@ > C:\tmp\LogonScript.ps1

$Trigger = New-ScheduledTaskTrigger -AtLogOn
$Action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument 'C:\tmp\LogonScript.ps1'
Register-ScheduledTask -TaskName "LogonScript" -Trigger $Trigger -User "${adminUsername}" -Action $Action -RunLevel "Highest" -Force

Get-ScheduledTask -TaskName ServerManager | Disable-ScheduledTask
