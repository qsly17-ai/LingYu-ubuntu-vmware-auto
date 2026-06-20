[CmdletBinding()]
param(
    [string]$RepoZipUrl = 'https://github.com/qsly17-ai/LingYu-ubuntu-vmware-auto/archive/refs/heads/main.zip',
    [string]$InstallRoot = (Join-Path $env:USERPROFILE 'UbuntuVmwareAuto'),
    [string]$VmwareInstallerUrl,
    [string]$VmwareInstallerPath,
    [string]$VmwareInstallerSha256,
    [string]$VmName,
    [string]$VmRoot,
    [int]$CpuCount = 0,
    [int]$MemoryMB = 0,
    [int]$DiskMB = 0,
    [string]$UbuntuIsoUrl,
    [string]$UbuntuIsoChecksum,
    [switch]$SkipVmwareInstall,
    [switch]$DryRun,
    [switch]$BuildVm,
    [string]$RootPassword,
    [string]$RootPasswordHash,
    [switch]$ForceRebuild,
    [switch]$ShowConsole,
    [switch]$LockBootstrapUser,
    [switch]$KeepBuildSecrets
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Administrator {
    $Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $Principal = [Security.Principal.WindowsPrincipal]::new($Identity)
    if (-not $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Please run this bootstrap command from an elevated Administrator PowerShell session.'
    }
}

function Add-ArgIfValue {
    param(
        [string[]]$Arguments,
        [string]$Name,
        [string]$Value
    )

    if (-not [string]::IsNullOrWhiteSpace($Value)) {
        return $Arguments + @($Name, $Value)
    }
    return $Arguments
}

function Add-ArgIfPositiveInt {
    param(
        [string[]]$Arguments,
        [string]$Name,
        [int]$Value
    )

    if ($Value -gt 0) {
        return $Arguments + @($Name, [string]$Value)
    }
    return $Arguments
}

Assert-Administrator

if ($RepoZipUrl -match 'OWNER/') {
    throw 'RepoZipUrl still contains the OWNER placeholder. Replace it with the real GitHub repository zip URL.'
}

$TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('ubuntu-vmware-auto-' + [guid]::NewGuid().ToString('N'))
$ZipPath = Join-Path $TempRoot 'repo.zip'
$ExtractPath = Join-Path $TempRoot 'extract'

try {
    New-Item -ItemType Directory -Force -Path $TempRoot, $ExtractPath, $InstallRoot | Out-Null
    Write-Host "[+] Downloading project: $RepoZipUrl"
    Invoke-WebRequest -Uri $RepoZipUrl -OutFile $ZipPath -UseBasicParsing
    Expand-Archive -LiteralPath $ZipPath -DestinationPath $ExtractPath -Force

    $SourceRoot = Get-ChildItem -LiteralPath $ExtractPath -Directory | Select-Object -First 1
    if (-not $SourceRoot) {
        throw 'Downloaded repository archive did not contain a project directory.'
    }

    Write-Host "[+] Installing project files to $InstallRoot"
    $ProjectItems = Get-ChildItem -LiteralPath $SourceRoot.FullName -Force
    if (-not $ProjectItems) {
        throw 'Downloaded repository archive did not contain project files.'
    }
    $ProjectItems | Copy-Item -Destination $InstallRoot -Recurse -Force -ErrorAction Stop

    $MainScript = Join-Path $InstallRoot 'Install-UbuntuVm.ps1'
    if (-not (Test-Path -LiteralPath $MainScript)) {
        throw "Main script was not found after install: $MainScript"
    }

    $Args = @()
    $Args = Add-ArgIfValue -Arguments $Args -Name '-VmwareInstallerUrl' -Value $VmwareInstallerUrl
    $Args = Add-ArgIfValue -Arguments $Args -Name '-VmwareInstallerPath' -Value $VmwareInstallerPath
    $Args = Add-ArgIfValue -Arguments $Args -Name '-VmwareInstallerSha256' -Value $VmwareInstallerSha256
    $Args = Add-ArgIfValue -Arguments $Args -Name '-VmName' -Value $VmName
    $Args = Add-ArgIfValue -Arguments $Args -Name '-VmRoot' -Value $VmRoot
    $Args = Add-ArgIfPositiveInt -Arguments $Args -Name '-CpuCount' -Value $CpuCount
    $Args = Add-ArgIfPositiveInt -Arguments $Args -Name '-MemoryMB' -Value $MemoryMB
    $Args = Add-ArgIfPositiveInt -Arguments $Args -Name '-DiskMB' -Value $DiskMB
    $Args = Add-ArgIfValue -Arguments $Args -Name '-UbuntuIsoUrl' -Value $UbuntuIsoUrl
    $Args = Add-ArgIfValue -Arguments $Args -Name '-UbuntuIsoChecksum' -Value $UbuntuIsoChecksum
    $Args = Add-ArgIfValue -Arguments $Args -Name '-RootPassword' -Value $RootPassword
    $Args = Add-ArgIfValue -Arguments $Args -Name '-RootPasswordHash' -Value $RootPasswordHash

    if ($SkipVmwareInstall) { $Args += '-SkipVmwareInstall' }
    if ($DryRun) { $Args += '-DryRun' }
    if ($BuildVm) { $Args += '-BuildVm' }
    if ($ForceRebuild) { $Args += '-ForceRebuild' }
    if ($ShowConsole) { $Args += '-ShowConsole' }
    if ($LockBootstrapUser) { $Args += '-LockBootstrapUser' }
    if ($KeepBuildSecrets) { $Args += '-KeepBuildSecrets' }

    Write-Host "[+] Running installer: $MainScript $($Args -join ' ')"
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $MainScript @Args
} finally {
    Remove-Item -LiteralPath $TempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
