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

    $ForwardArgs = @()
    $ForwardArgs = Add-ArgIfValue -Arguments $ForwardArgs -Name '-VmwareInstallerUrl' -Value $VmwareInstallerUrl
    $ForwardArgs = Add-ArgIfValue -Arguments $ForwardArgs -Name '-VmwareInstallerPath' -Value $VmwareInstallerPath
    $ForwardArgs = Add-ArgIfValue -Arguments $ForwardArgs -Name '-VmwareInstallerSha256' -Value $VmwareInstallerSha256
    $ForwardArgs = Add-ArgIfValue -Arguments $ForwardArgs -Name '-VmName' -Value $VmName
    $ForwardArgs = Add-ArgIfValue -Arguments $ForwardArgs -Name '-VmRoot' -Value $VmRoot
    $ForwardArgs = Add-ArgIfPositiveInt -Arguments $ForwardArgs -Name '-CpuCount' -Value $CpuCount
    $ForwardArgs = Add-ArgIfPositiveInt -Arguments $ForwardArgs -Name '-MemoryMB' -Value $MemoryMB
    $ForwardArgs = Add-ArgIfPositiveInt -Arguments $ForwardArgs -Name '-DiskMB' -Value $DiskMB
    $ForwardArgs = Add-ArgIfValue -Arguments $ForwardArgs -Name '-UbuntuIsoUrl' -Value $UbuntuIsoUrl
    $ForwardArgs = Add-ArgIfValue -Arguments $ForwardArgs -Name '-UbuntuIsoChecksum' -Value $UbuntuIsoChecksum
    $ForwardArgs = Add-ArgIfValue -Arguments $ForwardArgs -Name '-RootPassword' -Value $RootPassword
    $ForwardArgs = Add-ArgIfValue -Arguments $ForwardArgs -Name '-RootPasswordHash' -Value $RootPasswordHash

    if ($SkipVmwareInstall) { $ForwardArgs += '-SkipVmwareInstall' }
    if ($DryRun) { $ForwardArgs += '-DryRun' }
    if ($BuildVm) { $ForwardArgs += '-BuildVm' }
    if ($ForceRebuild) { $ForwardArgs += '-ForceRebuild' }
    if ($ShowConsole) { $ForwardArgs += '-ShowConsole' }
    if ($LockBootstrapUser) { $ForwardArgs += '-LockBootstrapUser' }
    if ($KeepBuildSecrets) { $ForwardArgs += '-KeepBuildSecrets' }

    Write-Host "[+] Running installer: $MainScript $($ForwardArgs -join ' ')"
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $MainScript @ForwardArgs
} finally {
    Remove-Item -LiteralPath $TempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
