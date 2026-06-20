Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )
    if (-not $Condition) {
        throw $Message
    }
}

function Assert-Contains {
    param(
        [string]$Content,
        [string]$Expected,
        [string]$Message
    )
    Assert-True -Condition $Content.Contains($Expected) -Message $Message
}

$RequiredFiles = @(
    'Install-UbuntuVm.ps1',
    'Install-UbuntuVm.cmd',
    'bootstrap.ps1',
    '.gitignore',
    'packer/ubuntu-server.pkr.hcl',
    'cloud-init/user-data.tpl',
    'cloud-init/meta-data',
    'README.md'
)

foreach ($RelativePath in $RequiredFiles) {
    $Path = Join-Path $Root $RelativePath
    Assert-True -Condition (Test-Path -LiteralPath $Path) -Message "Missing required file: $RelativePath"
}

$InstallerScript = Get-Content -Raw -LiteralPath (Join-Path $Root 'Install-UbuntuVm.ps1')
$CmdLauncher = Get-Content -Raw -LiteralPath (Join-Path $Root 'Install-UbuntuVm.cmd')
$BootstrapScript = Get-Content -Raw -LiteralPath (Join-Path $Root 'bootstrap.ps1')
$GitIgnore = Get-Content -Raw -LiteralPath (Join-Path $Root '.gitignore')
$PackerTemplate = Get-Content -Raw -LiteralPath (Join-Path $Root 'packer/ubuntu-server.pkr.hcl')
$UserDataTemplate = Get-Content -Raw -LiteralPath (Join-Path $Root 'cloud-init/user-data.tpl')
$Readme = Get-Content -Raw -LiteralPath (Join-Path $Root 'README.md')

Assert-Contains $InstallerScript 'https://cf.comss.org/download/VMware-Workstation-Full-26H1-25388281.exe' 'Default VMware mirror URL is missing.'
Assert-Contains $InstallerScript 'a0ef9087607d9cad20b08139e73e41242e044ad5bd8cee141d3bad314586737f' 'Default VMware installer SHA256 pin is missing.'
Assert-Contains $InstallerScript 'ubuntu-24.04.4-live-server-amd64.iso' 'Default Ubuntu ISO URL is missing.'
Assert-Contains $InstallerScript 'e907d92eeec9df64163a7e454cbc8d7755e8ddc7ed42f99dbc80c40f1a138433' 'Default Ubuntu ISO SHA256 is missing.'
Assert-Contains $InstallerScript '$6$codexroot$g7u9ONFT9aUgXnj/MaHVrj1Xqa2amNP2NIR7IriyJF1nJaScfV9V9yp9zzOA9kkE4Pzrl/9H2kzi1O/wZ..es.' 'Default root/root SHA-512 crypt hash is missing.'
Assert-Contains $InstallerScript 'Get-AuthenticodeSignature' 'VMware installer signature verification is missing.'
Assert-Contains $InstallerScript 'VMware|Broadcom' 'VMware/Broadcom publisher allow-list is missing.'
Assert-True -Condition (-not $InstallerScript.Contains('$LASTEXITCODE')) -Message 'Installer script must not read $LASTEXITCODE under strict mode.'
Assert-Contains $InstallerScript 'function ConvertTo-HclPath' 'Windows path normalization for Packer HCL is missing.'
Assert-Contains $InstallerScript '.Replace([char]92, ''/'')' 'Packer HCL path slash conversion is missing.'
Assert-Contains $InstallerScript 'function Prepare-UbuntuIso' 'Ubuntu ISO download/checksum preparation is missing.'
Assert-Contains $InstallerScript 'Assert-Sha256 -Path $Destination -ExpectedSha256 $IsoChecksum' 'Ubuntu ISO checksum verification is missing.'
Assert-Contains $InstallerScript 'Microsoft\WinGet\Links\packer.exe' 'Packer winget links fallback path is missing.'
Assert-Contains $InstallerScript 'function Wait-TcpPort' 'SSH port wait logic is missing.'
Assert-Contains $InstallerScript 'Test-NetConnection' 'TCP port verification is missing.'
Assert-Contains $InstallerScript '[System.IO.Path]::GetPathRoot([System.IO.Path]::GetFullPath($Path))' 'Disk-space check should resolve the target drive root.'
Assert-Contains $InstallerScript 'Hashicorp.Packer' 'Packer winget package ID is missing.'
Assert-Contains $InstallerScript '[switch]$BuildVm' 'BuildVm switch is missing.'
Assert-Contains $InstallerScript 'Join-Path $ScriptRoot ''machines''' 'Default VM root should be relative to the project directory.'
Assert-Contains $InstallerScript 'Preparation completed.' 'Default preparation completion output is missing.'
Assert-Contains $InstallerScript 'default mode prepares dependencies and downloads only' 'Dry run should describe the non-building default mode.'
Assert-Contains $InstallerScript 'Pass -RootPassword when using -BuildVm' 'Build mode must require an explicit bootstrap/Packer password.'
Assert-True -Condition (-not $InstallerScript.Contains('if (-not $RootPasswordHash -and [string]::IsNullOrWhiteSpace($RootPassword))')) -Message 'RootPasswordHash alone must not be accepted because Packer needs a plaintext bootstrap password.'
Assert-Contains $InstallerScript 'bootstrap_password_hash' 'Bootstrap password hash must be generated separately from the root password hash.'
Assert-True -Condition (-not $InstallerScript.Contains("[string]`$RootPassword = 'root'")) -Message 'RootPassword must not default to root in the distributable script.'
Assert-True -Condition (-not $InstallerScript.Contains('Start-BuiltVm -VmrunPath')) -Message 'The distributable script must not auto-start the VM after build.'
Assert-Contains $InstallerScript 'ssh_username  = $BootstrapUser' 'Packer must use the bootstrap user for the first SSH handshake.'
Assert-Contains $InstallerScript 'bootstrap_username = $BootstrapUser' 'Packer vars must include the bootstrap username.'
Assert-Contains $InstallerScript 'lock_bootstrap_user = $LockBootstrapUser.IsPresent' 'Packer vars must include the bootstrap lock policy.'
Assert-Contains $InstallerScript '[switch]$LockBootstrapUser' 'LockBootstrapUser switch is missing.'
Assert-Contains $InstallerScript '[switch]$KeepBuildSecrets' 'KeepBuildSecrets switch is missing.'
Assert-Contains $InstallerScript 'Remove-BuildSecrets' 'Build secret cleanup is missing.'
Assert-Contains $InstallerScript '[ValidateRange(1, 64)]' 'CpuCount range validation is missing.'
Assert-Contains $InstallerScript '[ValidateRange(1024, 1048576)]' 'MemoryMB range validation is missing.'
Assert-Contains $InstallerScript '[ValidateRange(10240, 10485760)]' 'DiskMB range validation is missing.'
Assert-Contains $InstallerScript '[switch]$DryRun' 'DryRun switch is missing.'
Assert-Contains $InstallerScript '[switch]$ForceRebuild' 'ForceRebuild switch is missing.'
Assert-Contains $InstallerScript '[switch]$SkipVmwareInstall' 'SkipVmwareInstall switch is missing.'
Assert-Contains $InstallerScript 'vmrun.exe' 'vmrun discovery/start logic is missing.'

Assert-Contains $CmdLauncher '-ExecutionPolicy Bypass' 'CMD launcher must bypass PowerShell policy for this process.'
Assert-Contains $CmdLauncher 'Install-UbuntuVm.ps1' 'CMD launcher must invoke the PowerShell script.'

Assert-Contains $BootstrapScript 'RepoZipUrl' 'Bootstrap script must accept a repository zip URL.'
Assert-Contains $BootstrapScript 'https://github.com/qsly17-ai/LingYu-ubuntu-vmware-auto/archive/refs/heads/main.zip' 'Bootstrap default repository URL is missing.'
Assert-Contains $BootstrapScript 'Invoke-WebRequest' 'Bootstrap script must download the repository archive.'
Assert-Contains $BootstrapScript 'Expand-Archive' 'Bootstrap script must expand the repository archive.'
Assert-Contains $BootstrapScript 'Install-UbuntuVm.ps1' 'Bootstrap script must run the main installer.'
Assert-Contains $BootstrapScript 'OWNER placeholder' 'Bootstrap script must guard against an unpublished placeholder URL.'
Assert-True -Condition (-not $BootstrapScript.Contains("Copy-Item -LiteralPath (Join-Path `$SourceRoot.FullName '*')")) -Message 'Bootstrap must not use -LiteralPath with a wildcard when copying repository files.'
Assert-Contains $BootstrapScript 'Get-ChildItem -LiteralPath $SourceRoot.FullName -Force' 'Bootstrap must enumerate extracted repository files before copying.'
Assert-True -Condition (-not $BootstrapScript.Contains('$Args')) -Message 'Bootstrap must not use $Args because it collides with PowerShell automatic $args under strict mode.'
Assert-True -Condition (-not $BootstrapScript.Contains('@Args')) -Message 'Bootstrap must not splat @Args because it collides with PowerShell automatic $args under strict mode.'
Assert-Contains $BootstrapScript '$ForwardArgs' 'Bootstrap must use a non-automatic variable name for forwarded arguments.'
Assert-Contains $BootstrapScript 'LockBootstrapUser' 'Bootstrap must forward LockBootstrapUser.'
Assert-Contains $BootstrapScript 'KeepBuildSecrets' 'Bootstrap must forward KeepBuildSecrets.'

Assert-Contains $GitIgnore 'downloads/' 'Git ignore must exclude downloads.'
Assert-Contains $GitIgnore 'machines/' 'Git ignore must exclude VM outputs.'
Assert-Contains $GitIgnore 'packer_cache/' 'Git ignore must exclude Packer cache.'
Assert-Contains $GitIgnore '*.iso' 'Git ignore must exclude ISO files.'
Assert-Contains $GitIgnore '*.vmdk' 'Git ignore must exclude virtual disks.'

Assert-Contains $PackerTemplate 'packer {' 'Packer required plugin block is missing.'
Assert-Contains $PackerTemplate 'vmware-iso' 'VMware ISO builder is missing.'
Assert-Contains $PackerTemplate 'required_version = ">= 1.10.0"' 'Packer required_version is missing.'
Assert-Contains $PackerTemplate 'version = ">= 2.1.3"' 'VMware plugin minimum version is missing.'
Assert-Contains $PackerTemplate 'source  = "github.com/vmware/vmware"' 'Current VMware plugin source is missing.'
Assert-Contains $PackerTemplate 'firmware      = "bios"' 'BIOS firmware setting is missing.'
Assert-Contains $PackerTemplate 'network              = "nat"' 'NAT network setting is missing.'
Assert-Contains $PackerTemplate 'format        = "vmx"' 'VMX output format is missing.'
Assert-Contains $PackerTemplate 'http_directory' 'NoCloud HTTP directory is missing.'
Assert-Contains $PackerTemplate 'autoinstall ''ds=nocloud;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/''' 'Ubuntu autoinstall boot command is missing.'
Assert-Contains $PackerTemplate 'ssh_username' 'SSH communicator config is missing.'
Assert-Contains $PackerTemplate 'ssh_password' 'SSH password config is missing.'
Assert-Contains $PackerTemplate 'variable "bootstrap_username"' 'Bootstrap username variable is missing.'
Assert-Contains $PackerTemplate 'variable "lock_bootstrap_user"' 'Bootstrap lock policy variable is missing.'
Assert-Contains $PackerTemplate 'sudo rm -f /etc/sudoers.d/90-codex-bootstrap' 'Bootstrap sudoers cleanup is missing.'
Assert-Contains $PackerTemplate 'LOCK_BOOTSTRAP_USER' 'Bootstrap user locking must be conditional.'
Assert-Contains $PackerTemplate 'sudo passwd -l \"$BOOTSTRAP_USER\"' 'Bootstrap user should be locked after Packer connects successfully.'

Assert-Contains $UserDataTemplate '#cloud-config' 'cloud-init header is missing.'
Assert-Contains $UserDataTemplate 'autoinstall:' 'Ubuntu autoinstall root is missing.'
Assert-Contains $UserDataTemplate 'locale: zh_CN.UTF-8' 'Simplified Chinese locale is missing.'
Assert-Contains $UserDataTemplate 'timezone: Asia/Shanghai' 'Asia/Shanghai timezone is missing.'
Assert-Contains $UserDataTemplate 'language-pack-zh-hans' 'Simplified Chinese language pack is missing.'
Assert-Contains $UserDataTemplate 'fonts-noto-cjk' 'CJK font package is missing.'
Assert-Contains $UserDataTemplate 'locale-gen zh_CN.UTF-8' 'Simplified Chinese locale generation is missing.'
Assert-Contains $UserDataTemplate 'update-locale LANG=zh_CN.UTF-8 LANGUAGE=zh_CN:zh' 'Simplified Chinese locale activation is missing.'
Assert-Contains $UserDataTemplate 'password: ${bootstrap_password_hash}' 'Bootstrap identity password must use its own hash.'
Assert-Contains $UserDataTemplate 'openssh-server' 'OpenSSH package install is missing.'
Assert-Contains $UserDataTemplate 'open-vm-tools' 'VMware tools package install is missing.'
Assert-Contains $UserDataTemplate 'PermitRootLogin yes' 'Root SSH enablement is missing.'
Assert-Contains $UserDataTemplate 'root:${root_password_hash}' 'Root password hash placeholder is missing.'
Assert-True -Condition (-not $UserDataTemplate.Contains('passwd -l ${bootstrap_username}')) -Message 'Bootstrap user must not be locked before Packer SSH connects.'
Assert-Contains $UserDataTemplate '90-codex-bootstrap' 'Bootstrap sudoers setup is missing.'

Assert-Contains $Readme '.\Install-UbuntuVm.cmd -DryRun' 'README dry-run example is missing.'
Assert-Contains $Readme 'https://raw.githubusercontent.com/qsly17-ai/LingYu-ubuntu-vmware-auto/main/bootstrap.ps1' 'README one-line bootstrap command is missing.'
Assert-Contains $Readme 'zh_CN.UTF-8' 'README simplified Chinese locale note is missing.'
Assert-Contains $Readme 'Asia/Shanghai' 'README timezone note is missing.'
Assert-Contains $Readme '第三方源' 'README third-party source warning is missing.'
Assert-Contains $Readme 'a0ef9087607d9cad20b08139e73e41242e044ad5bd8cee141d3bad314586737f' 'README default VMware SHA256 pin is missing.'
Assert-Contains $Readme '-LockBootstrapUser' 'README LockBootstrapUser documentation is missing.'
Assert-Contains $Readme '-KeepBuildSecrets' 'README KeepBuildSecrets documentation is missing.'
Assert-Contains $Readme 'github.com/vmware/vmware' 'README current VMware Packer plugin source is missing.'

$AllContent = @($InstallerScript, $PackerTemplate, $UserDataTemplate, $Readme) -join "`n"
foreach ($Forbidden in @('TBD', 'TODO', '<placeholder>')) {
    Assert-True -Condition (-not $AllContent.Contains($Forbidden)) -Message "Forbidden placeholder text found: $Forbidden"
}

Write-Host 'Static tests passed.'
