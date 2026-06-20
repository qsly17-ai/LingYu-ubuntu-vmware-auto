[CmdletBinding()]
param(
    [string]$VmwareInstallerUrl = 'https://cf.comss.org/download/VMware-Workstation-Full-26H1-25388281.exe',
    [string]$VmwareInstallerPath,
    [string]$VmwareInstallerSha256,
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9.-]{0,62}$')]
    [string]$VmName = 'ubuntu-24.04-server-auto',
    [string]$VmRoot,
    [string]$RootPassword,
    [string]$RootPasswordHash,
    [ValidateRange(1, 64)]
    [int]$CpuCount = 2,
    [ValidateRange(1024, 1048576)]
    [int]$MemoryMB = 4096,
    [ValidateRange(10240, 10485760)]
    [int]$DiskMB = 40960,
    [string]$UbuntuIsoUrl = 'https://releases.ubuntu.com/24.04/ubuntu-24.04.4-live-server-amd64.iso',
    [string]$UbuntuIsoChecksum = 'sha256:e907d92eeec9df64163a7e454cbc8d7755e8ddc7ed42f99dbc80c40f1a138433',
    [switch]$DryRun,
    [switch]$BuildVm,
    [switch]$ForceRebuild,
    [switch]$ShowConsole,
    [switch]$SkipVmwareInstall,
    [switch]$LockBootstrapUser,
    [switch]$KeepBuildSecrets
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptRoot = Split-Path -Parent $PSCommandPath
if ([string]::IsNullOrWhiteSpace($VmRoot)) {
    $VmRoot = Join-Path $ScriptRoot 'machines'
}
$DownloadsDir = Join-Path $ScriptRoot 'downloads'
$BuildDir = Join-Path $ScriptRoot 'build'
$GeneratedDir = Join-Path $BuildDir $VmName
$HttpDir = Join-Path $GeneratedDir 'http'
$OutputDir = Join-Path $VmRoot $VmName
$PackerTemplate = Join-Path $ScriptRoot 'packer\ubuntu-server.pkr.hcl'
$UserDataTemplate = Join-Path $ScriptRoot 'cloud-init\user-data.tpl'
$MetaDataTemplate = Join-Path $ScriptRoot 'cloud-init\meta-data'
$DefaultVmwareInstallerUrlForHash = 'https://cf.comss.org/download/VMware-Workstation-Full-26H1-25388281.exe'
$DefaultVmwareInstallerSha256 = 'sha256:a0ef9087607d9cad20b08139e73e41242e044ad5bd8cee141d3bad314586737f'
$DefaultRootHash = '$6$codexroot$g7u9ONFT9aUgXnj/MaHVrj1Xqa2amNP2NIR7IriyJF1nJaScfV9V9yp9zzOA9kkE4Pzrl/9H2kzi1O/wZ..es.'

function Write-Step {
    param([string]$Message)
    Write-Host "[+] $Message"
}

function Write-Warn {
    param([string]$Message)
    Write-Warning $Message
}

function Assert-Administrator {
    $Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $Principal = [Security.Principal.WindowsPrincipal]::new($Identity)
    if (-not $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Please run this script from an elevated Administrator PowerShell session.'
    }
}

function Get-CommandPath {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [string[]]$FallbackPaths = @()
    )

    $Command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($Command) {
        return $Command.Source
    }

    foreach ($Path in $FallbackPaths) {
        if (Test-Path -LiteralPath $Path) {
            return $Path
        }
    }

    return $null
}

function Assert-Winget {
    $WingetPath = Get-CommandPath -Name 'winget.exe'
    if (-not $WingetPath) {
        throw 'winget.exe was not found. Install App Installer from Microsoft Store, then rerun.'
    }
    return $WingetPath
}

function Assert-Virtualization {
    $Computer = Get-CimInstance -ClassName Win32_ComputerSystem
    if ($Computer.HypervisorPresent) {
        Write-Warn 'A hypervisor is already present. VMware can run, but nested/competing virtualization settings may affect performance.'
    }

    $Processor = Get-CimInstance -ClassName Win32_Processor | Select-Object -First 1
    $VirtualizationEnabled = $Processor.VirtualizationFirmwareEnabled
    if (-not $VirtualizationEnabled) {
        throw 'CPU virtualization is not enabled in firmware/BIOS. Enable Intel VT-x or AMD-V and rerun.'
    }
}

function Assert-FreeSpace {
    param([string]$Path, [int]$RequiredGB)

    $Root = [System.IO.Path]::GetPathRoot([System.IO.Path]::GetFullPath($Path))
    if ([string]::IsNullOrWhiteSpace($Root)) {
        throw "Could not determine drive root for path: $Path"
    }

    $Drive = Get-PSDrive -Name ($Root.TrimEnd('\').TrimEnd(':')) -ErrorAction Stop
    $FreeGB = [math]::Round($Drive.Free / 1GB, 2)
    if ($FreeGB -lt $RequiredGB) {
        throw "Not enough free disk space on $($Drive.Name):. Required ${RequiredGB}GB, available ${FreeGB}GB."
    }
}

function Get-VmwarePaths {
    $Candidates = @(
        'C:\Program Files (x86)\VMware\VMware Workstation',
        'C:\Program Files\VMware\VMware Workstation'
    )

    $VmwareExe = Get-CommandPath -Name 'vmware.exe' -FallbackPaths ($Candidates | ForEach-Object { Join-Path $_ 'vmware.exe' })
    $VmrunExe = Get-CommandPath -Name 'vmrun.exe' -FallbackPaths ($Candidates | ForEach-Object { Join-Path $_ 'vmrun.exe' })

    [pscustomobject]@{
        VmwareExe = $VmwareExe
        VmrunExe  = $VmrunExe
    }
}

function Get-PackerPath {
    Get-CommandPath -Name 'packer.exe' -FallbackPaths @(
        "$env:LOCALAPPDATA\Microsoft\WinGet\Links\packer.exe",
        "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\Hashicorp.Packer_Microsoft.Winget.Source_8wekyb3d8bbwe\packer.exe",
        'C:\Program Files\Packer\packer.exe'
    )
}

function Get-OpenSslPath {
    Get-CommandPath -Name 'openssl.exe' -FallbackPaths @(
        'C:\Program Files\Git\mingw64\bin\openssl.exe',
        'C:\Program Files\Git\usr\bin\openssl.exe'
    )
}

function Invoke-External {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$ArgumentList,
        [string]$ErrorMessage = 'External command failed.'
    )

    Write-Step "$FilePath $($ArgumentList -join ' ')"
    $Process = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -NoNewWindow -Wait -PassThru
    if ($Process.ExitCode -ne 0) {
        throw "$ErrorMessage Exit code: $($Process.ExitCode)"
    }
}

function Invoke-ExternalCapture {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$ArgumentList,
        [string]$ErrorMessage = 'External command failed.'
    )

    $TempOut = [System.IO.Path]::GetTempFileName()
    $TempErr = [System.IO.Path]::GetTempFileName()
    try {
        Write-Step "$FilePath $($ArgumentList -join ' ')"
        $Process = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -NoNewWindow -Wait -PassThru -RedirectStandardOutput $TempOut -RedirectStandardError $TempErr
        $StdOut = Get-Content -Raw -LiteralPath $TempOut
        $StdErr = Get-Content -Raw -LiteralPath $TempErr
        if ($Process.ExitCode -ne 0) {
            throw "$ErrorMessage Exit code: $($Process.ExitCode). $StdErr"
        }
        return $StdOut
    } finally {
        Remove-Item -LiteralPath $TempOut, $TempErr -Force -ErrorAction SilentlyContinue
    }
}

function Download-File {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$Destination,
        [int]$Retries = 3
    )

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null
    for ($Attempt = 1; $Attempt -le $Retries; $Attempt++) {
        try {
            Write-Step "Downloading $Url (attempt $Attempt/$Retries)"
            Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing
            return
        } catch {
            Remove-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue
            if ($Attempt -ge $Retries) {
                throw "Download failed after $Retries attempts: $Url. $($_.Exception.Message)"
            }
            Start-Sleep -Seconds ([math]::Min(5 * $Attempt, 20))
        }
    }
}

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Assert-Sha256 {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ExpectedSha256
    )

    $Expected = $ExpectedSha256.ToLowerInvariant().Replace('sha256:', '')
    $Actual = Get-Sha256 -Path $Path
    if ($Actual -ne $Expected) {
        throw "SHA256 mismatch for $Path. Expected $Expected, got $Actual."
    }
}

function Assert-TrustedVmwareInstaller {
    param([Parameter(Mandatory = $true)][string]$Path)

    $Signature = Get-AuthenticodeSignature -LiteralPath $Path
    if ($Signature.Status -ne 'Valid') {
        throw "VMware installer signature is not valid. Status: $($Signature.Status)."
    }

    $Subject = $Signature.SignerCertificate.Subject
    if ($Subject -notmatch 'VMware|Broadcom') {
        throw "VMware installer publisher is not allowed. Signer subject: $Subject"
    }

    Write-Step "Verified installer signature: $Subject"
}

function Install-VMwareWorkstation {
    param(
        [string]$InstallerUrl,
        [string]$InstallerPath,
        [string]$ExpectedSha256
    )

    $Paths = Get-VmwarePaths
    if ($Paths.VmwareExe -and $Paths.VmrunExe) {
        Write-Step "VMware Workstation already installed: $($Paths.VmwareExe)"
        return Get-VmwarePaths
    }

    if ($SkipVmwareInstall) {
        throw 'VMware Workstation is not installed and -SkipVmwareInstall was specified.'
    }

    $UsingPinnedDefaultInstaller = [string]::IsNullOrWhiteSpace($InstallerPath) -and [string]::Equals($InstallerUrl, $DefaultVmwareInstallerUrlForHash, [System.StringComparison]::OrdinalIgnoreCase)
    if ([string]::IsNullOrWhiteSpace($InstallerPath)) {
        $FileName = Split-Path -Leaf ([Uri]$InstallerUrl).AbsolutePath
        if ([string]::IsNullOrWhiteSpace($FileName)) {
            $FileName = 'VMware-Workstation-Installer.exe'
        }
        $InstallerPath = Join-Path $DownloadsDir $FileName
        if (-not (Test-Path -LiteralPath $InstallerPath)) {
            if ($DryRun) {
                Write-Step "Dry run: would download VMware installer to $InstallerPath"
            } else {
                Download-File -Url $InstallerUrl -Destination $InstallerPath
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($ExpectedSha256) -and $UsingPinnedDefaultInstaller) {
        $ExpectedSha256 = $DefaultVmwareInstallerSha256
        Write-Step "Using pinned SHA256 for default VMware installer: $ExpectedSha256"
    }

    if ($DryRun) {
        Write-Step "Dry run: would verify and silently install VMware from $InstallerPath"
        return $Paths
    }

    if (-not (Test-Path -LiteralPath $InstallerPath)) {
        throw "VMware installer was not found: $InstallerPath"
    }

    if ($ExpectedSha256) {
        Assert-Sha256 -Path $InstallerPath -ExpectedSha256 $ExpectedSha256
    }
    Assert-TrustedVmwareInstaller -Path $InstallerPath

    $Arguments = @('/s', '/v"/qn EULAS_AGREED=1 AUTOSOFTWAREUPDATE=0 DATACOLLECTION=0 REBOOT=ReallySuppress"')
    Invoke-External -FilePath $InstallerPath -ArgumentList $Arguments -ErrorMessage 'VMware Workstation silent install failed.'

    $Paths = Get-VmwarePaths
    if (-not $Paths.VmwareExe -or -not $Paths.VmrunExe) {
        throw 'VMware Workstation install finished, but vmware.exe or vmrun.exe was not found.'
    }

    return $Paths
}

function Install-Packer {
    param([string]$WingetPath)

    $Packer = Get-PackerPath
    if ($Packer) {
        Write-Step "Packer already installed: $Packer"
        return $Packer
    }

    if ($DryRun) {
        Write-Step 'Dry run: would install Packer with winget package Hashicorp.Packer'
        return $null
    }

    Invoke-External -FilePath $WingetPath -ArgumentList @(
        'install',
        '--id',
        'Hashicorp.Packer',
        '-e',
        '--accept-package-agreements',
        '--accept-source-agreements'
    ) -ErrorMessage 'Packer installation failed.'

    $Packer = Get-PackerPath
    if (-not $Packer) {
        throw 'Packer installation finished, but packer.exe was not found in PATH or known locations.'
    }
    return $Packer
}

function New-Sha512CryptHash {
    param([Parameter(Mandatory = $true)][string]$Password)

    if ($Password -eq 'root') {
        return $DefaultRootHash
    }

    $OpenSsl = Get-OpenSslPath
    if (-not $OpenSsl) {
        throw 'A custom -RootPassword requires openssl.exe to generate the temporary bootstrap SHA-512 crypt hash. Install Git for Windows/OpenSSL, or use -RootPassword root for a local test build.'
    }

    $Salt = -join ((48..57 + 65..90 + 97..122) | Get-Random -Count 16 | ForEach-Object { [char]$_ })
    $Hash = Invoke-ExternalCapture -FilePath $OpenSsl -ArgumentList @('passwd', '-6', '-salt', $Salt, $Password) -ErrorMessage 'openssl failed to generate a SHA-512 crypt password hash.'
    if ([string]::IsNullOrWhiteSpace($Hash)) {
        throw 'openssl failed to generate a SHA-512 crypt password hash.'
    }
    return $Hash.Trim()
}

function ConvertTo-PackerStringLiteral {
    param([Parameter(Mandatory = $true)][string]$Value)
    $Escaped = $Value.Replace([string][char]92, '\\').Replace('"', '\"')
    return '"' + $Escaped + '"'
}

function ConvertTo-HclPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    return ([System.IO.Path]::GetFullPath($Path)).Replace([char]92, '/')
}

function ConvertTo-HclIsoSource {
    param([Parameter(Mandatory = $true)][string]$Source)

    if ([Uri]::IsWellFormedUriString($Source, [UriKind]::Absolute)) {
        $Uri = [Uri]$Source
        if ($Uri.Scheme -in @('http', 'https')) {
            return $Source
        }
    }

    return ConvertTo-HclPath -Path $Source
}

function Expand-Template {
    param(
        [Parameter(Mandatory = $true)][string]$Template,
        [Parameter(Mandatory = $true)][hashtable]$Values
    )

    $Result = $Template
    foreach ($Key in $Values.Keys) {
        $Result = $Result.Replace('${' + $Key + '}', [string]$Values[$Key])
    }
    return $Result
}

function New-GeneratedConfig {
    param(
        [Parameter(Mandatory = $true)][string]$RootAccountPasswordHash,
        [Parameter(Mandatory = $true)][string]$BootstrapPasswordHash,
        [Parameter(Mandatory = $true)][string]$IsoSource
    )

    if (Test-Path -LiteralPath $GeneratedDir) {
        Remove-Item -LiteralPath $GeneratedDir -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $HttpDir | Out-Null

    $BootstrapUser = 'codex-bootstrap'
    $UserData = Get-Content -Raw -LiteralPath $UserDataTemplate
    $UserData = Expand-Template -Template $UserData -Values @{
        root_password_hash      = $RootAccountPasswordHash
        bootstrap_password_hash = $BootstrapPasswordHash
        bootstrap_username = $BootstrapUser
        hostname           = $VmName
    }

    $MetaData = Get-Content -Raw -LiteralPath $MetaDataTemplate
    $MetaData = Expand-Template -Template $MetaData -Values @{
        instance_id = $VmName
        hostname    = $VmName
    }

    Set-Content -LiteralPath (Join-Path $HttpDir 'user-data') -Value $UserData -Encoding utf8
    Set-Content -LiteralPath (Join-Path $HttpDir 'meta-data') -Value $MetaData -Encoding ascii

    $Vars = @{
        vm_name       = $VmName
        output_dir    = ConvertTo-HclPath -Path $OutputDir
        iso_url       = ConvertTo-HclIsoSource -Source $IsoSource
        iso_checksum  = $UbuntuIsoChecksum
        http_dir      = ConvertTo-HclPath -Path $HttpDir
        bootstrap_username = $BootstrapUser
        ssh_username  = $BootstrapUser
        ssh_password  = $RootPassword
        lock_bootstrap_user = $LockBootstrapUser.IsPresent
        cpu_count     = $CpuCount
        memory_mb     = $MemoryMB
        disk_size_mb  = $DiskMB
        headless      = (-not $ShowConsole.IsPresent).ToString().ToLowerInvariant()
    }

    $VarFile = Join-Path $GeneratedDir 'ubuntu-server.auto.pkrvars.hcl'
    $VarLines = foreach ($Key in $Vars.Keys) {
        $Value = $Vars[$Key]
        if ($Value -is [int]) {
            "$Key = $Value"
        } elseif ($Value -is [bool]) {
            "$Key = $($Value.ToString().ToLowerInvariant())"
        } elseif ($Value -in @('true', 'false')) {
            "$Key = $Value"
        } else {
            "$Key = $(ConvertTo-PackerStringLiteral -Value ([string]$Value))"
        }
    }
    Set-Content -LiteralPath $VarFile -Value ($VarLines -join "`n") -Encoding ascii

    [pscustomobject]@{
        VarFile      = $VarFile
        HttpDir      = $HttpDir
        GeneratedDir = $GeneratedDir
    }
}

function Remove-BuildSecrets {
    param([Parameter(Mandatory = $true)]$GeneratedConfig)

    if ($KeepBuildSecrets) {
        Write-Warn "Keeping generated build secrets in $($GeneratedConfig.GeneratedDir) because -KeepBuildSecrets was specified."
        return
    }

    if ($GeneratedConfig.GeneratedDir -and (Test-Path -LiteralPath $GeneratedConfig.GeneratedDir)) {
        Remove-Item -LiteralPath $GeneratedConfig.GeneratedDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Step "Removed generated build secrets: $($GeneratedConfig.GeneratedDir)"
    }
}

function Prepare-UbuntuIso {
    param(
        [Parameter(Mandatory = $true)][string]$IsoUrl,
        [Parameter(Mandatory = $true)][string]$IsoChecksum
    )

    if (Test-Path -LiteralPath $IsoUrl) {
        if ($DryRun) {
            Write-Step "Dry run: would verify local Ubuntu ISO $IsoUrl"
        } else {
            Assert-Sha256 -Path $IsoUrl -ExpectedSha256 $IsoChecksum
        }
        return (Resolve-Path -LiteralPath $IsoUrl).Path
    }

    if (-not [Uri]::IsWellFormedUriString($IsoUrl, [UriKind]::Absolute)) {
        throw "Ubuntu ISO source is neither an existing file nor an absolute URL: $IsoUrl"
    }

    $FileName = Split-Path -Leaf ([Uri]$IsoUrl).AbsolutePath
    if ([string]::IsNullOrWhiteSpace($FileName)) {
        throw "Could not determine Ubuntu ISO file name from URL: $IsoUrl"
    }

    $Destination = Join-Path $DownloadsDir $FileName
    if ($DryRun) {
        Write-Step "Dry run: would download Ubuntu ISO to $Destination"
        Write-Step "Dry run: would verify Ubuntu ISO checksum $IsoChecksum"
        return $Destination
    }

    if (-not (Test-Path -LiteralPath $Destination)) {
        Download-File -Url $IsoUrl -Destination $Destination
    } else {
        Write-Step "Ubuntu ISO already exists: $Destination"
    }

    Assert-Sha256 -Path $Destination -ExpectedSha256 $IsoChecksum
    return $Destination
}

function Invoke-PackerBuild {
    param(
        [Parameter(Mandatory = $true)][string]$PackerPath,
        [Parameter(Mandatory = $true)][string]$VarFile
    )

    Invoke-External -FilePath $PackerPath -ArgumentList @('init', $PackerTemplate) -ErrorMessage 'Packer init failed.'

    if (Test-Path -LiteralPath $OutputDir) {
        if (-not $ForceRebuild) {
            throw "VM output directory already exists: $OutputDir. Pass -ForceRebuild to remove and recreate it."
        }
        Remove-Item -LiteralPath $OutputDir -Recurse -Force
    }

    Invoke-External -FilePath $PackerPath -ArgumentList @(
        'build',
        '-force',
        "-var-file=$VarFile",
        $PackerTemplate
    ) -ErrorMessage 'Packer build failed.'
}

function Start-BuiltVm {
    param(
        [Parameter(Mandatory = $true)][string]$VmrunPath
    )

    $Vmx = Get-ChildItem -Path $OutputDir -Recurse -Filter '*.vmx' | Select-Object -First 1
    if (-not $Vmx) {
        throw "No .vmx file found under $OutputDir."
    }

    Invoke-External -FilePath $VmrunPath -ArgumentList @('start', $Vmx.FullName, 'nogui') -ErrorMessage 'vmrun failed to start the virtual machine.'
    Write-Step "Started VM: $($Vmx.FullName)"
    return $Vmx.FullName
}

function Show-GuestHints {
    param([string]$VmrunPath, [string]$VmxPath)

    Write-Step 'Waiting briefly for VMware Tools guest IP reporting.'
    Start-Sleep -Seconds 20
    $Ip = $null
    try {
        $Ip = & $VmrunPath getGuestIPAddress $VmxPath -wait
    } catch {
        Write-Warn "vmrun could not read guest IP yet: $($_.Exception.Message)"
    }

    Write-Host ''
    Write-Host 'VM ready information:'
    Write-Host "  VMX: $VmxPath"
    if ($Ip) {
        Wait-TcpPort -ComputerName $Ip -Port 22 -TimeoutSeconds 300
        Write-Host "  IP: $Ip"
        Write-Host "  SSH: ssh root@$Ip"
    } else {
        Write-Host '  IP: not available yet; check VMware NAT/DHCP or open the VM console.'
    }
    Write-Host '  Username: root'
    Write-Host "  Password: $RootPassword"
}

function Show-PreparedNextSteps {
    param(
        [Parameter(Mandatory = $true)][string]$PackerPath,
        [Parameter(Mandatory = $true)][string]$IsoSource
    )

    Write-Host ''
    Write-Host 'Preparation completed.'
    Write-Host "  Project root: $ScriptRoot"
    Write-Host "  VMware machines directory: $VmRoot"
    Write-Host "  Ubuntu ISO: $IsoSource"
    Write-Host "  Packer: $PackerPath"
    Write-Host ''
    Write-Host 'Next step if you want to build the VM image yourself:'
    Write-Host '  .\Install-UbuntuVm.cmd -BuildVm -RootPassword "<your-password>" -ForceRebuild'
    Write-Host ''
    Write-Host 'After Packer finishes, start the .vmx from VMware Workstation or vmrun manually.'
}

function Wait-TcpPort {
    param(
        [Parameter(Mandatory = $true)][string]$ComputerName,
        [int]$Port = 22,
        [int]$TimeoutSeconds = 300
    )

    $Deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    Write-Step "Waiting for TCP $ComputerName`:$Port"
    do {
        if (Test-NetConnection -ComputerName $ComputerName -Port $Port -InformationLevel Quiet -WarningAction SilentlyContinue) {
            Write-Step "TCP $ComputerName`:$Port is reachable."
            return
        }
        Start-Sleep -Seconds 5
    } while ((Get-Date) -lt $Deadline)

    throw "Timed out waiting for TCP $ComputerName`:$Port."
}

function Invoke-Main {
    Assert-Administrator
    $WingetPath = Assert-Winget
    Assert-Virtualization
    Assert-FreeSpace -Path $VmRoot -RequiredGB ([math]::Ceiling(($DiskMB / 1024) + 12))

    foreach ($Path in @($DownloadsDir, $BuildDir, $VmRoot)) {
        if ($DryRun) {
            Write-Step "Dry run: would ensure directory $Path"
        } else {
            New-Item -ItemType Directory -Force -Path $Path | Out-Null
        }
    }

    $VmwarePaths = Install-VMwareWorkstation -InstallerUrl $VmwareInstallerUrl -InstallerPath $VmwareInstallerPath -ExpectedSha256 $VmwareInstallerSha256
    $PackerPath = Install-Packer -WingetPath $WingetPath
    $IsoSource = Prepare-UbuntuIso -IsoUrl $UbuntuIsoUrl -IsoChecksum $UbuntuIsoChecksum

    if ($DryRun) {
        if ($BuildVm) {
            Write-Step "Dry run: would render cloud-init and Packer var files for $VmName"
            Write-Step "Dry run: would run packer init/build with $PackerTemplate"
        } else {
            Write-Step 'Dry run: default mode prepares dependencies and downloads only; it would not build or start a VM.'
        }
        Write-Host ''
        Write-Host 'Dry run completed.'
        return
    }

    if (-not $BuildVm) {
        Show-PreparedNextSteps -PackerPath $PackerPath -IsoSource $IsoSource
        return
    }

    if ([string]::IsNullOrWhiteSpace($RootPassword)) {
        throw 'Pass -RootPassword when using -BuildVm. Packer needs this plaintext password for the temporary bootstrap SSH user; -RootPasswordHash only overrides the final root account hash.'
    }

    $BootstrapPasswordHash = New-Sha512CryptHash -Password $RootPassword
    $RootAccountPasswordHash = if ([string]::IsNullOrWhiteSpace($RootPasswordHash)) { $BootstrapPasswordHash } else { $RootPasswordHash }
    $Generated = New-GeneratedConfig -RootAccountPasswordHash $RootAccountPasswordHash -BootstrapPasswordHash $BootstrapPasswordHash -IsoSource $IsoSource
    try {
        Invoke-PackerBuild -PackerPath $PackerPath -VarFile $Generated.VarFile
    } finally {
        Remove-BuildSecrets -GeneratedConfig $Generated
    }

    $VmwarePaths = Get-VmwarePaths
    if (-not $VmwarePaths.VmrunExe) {
        throw 'vmrun.exe was not found after build.'
    }
    $Vmx = Get-ChildItem -Path $OutputDir -Recurse -Filter '*.vmx' | Select-Object -First 1
    if (-not $Vmx) {
        throw "Packer finished, but no .vmx file was found under $OutputDir."
    }

    Write-Host ''
    Write-Host 'Build completed. The VM was not started automatically.'
    Write-Host "  VMX: $($Vmx.FullName)"
    Write-Host 'Start it manually from VMware Workstation, or run:'
    Write-Host "  `"$($VmwarePaths.VmrunExe)`" start `"$($Vmx.FullName)`" gui"
}

Invoke-Main
