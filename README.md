# Ubuntu VMware 一键准备工具

这个项目提供一套可分发的 Windows PowerShell 工具，用来在一台新 Windows 机器上自动准备 Ubuntu + VMware 的本地虚拟机环境。

默认目标不是替用户直接启动虚拟机，而是完成这些准备工作：

- 检查管理员权限、CPU 虚拟化、磁盘空间和 `winget`
- 自动安装或发现 VMware Workstation
- 自动安装或发现 HashiCorp Packer
- 下载并校验 Ubuntu Server 24.04.4 LTS ISO
- 保留 Packer 和 cloud-init/autoinstall 模板，供用户后续按需构建 VM

默认不设置 VM 密码，不启动 VM，不把虚拟机自动跑起来。密码、构建和启动步骤由用户显式执行。

## 一句命令

仓库发布到 GitHub 后，可以用管理员 PowerShell 执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/qsly17-ai/LingYu-ubuntu-vmware-auto/main/bootstrap.ps1 | iex"
```

当前公开仓库地址为 `qsly17-ai/LingYu-ubuntu-vmware-auto`。

这条命令会把项目下载到：

```text
%USERPROFILE%\UbuntuVmwareAuto
```

然后运行主脚本完成依赖和 Ubuntu ISO 准备。

## 本地运行

如果已经克隆或下载了本项目：

```powershell
cd <项目目录>
.\Install-UbuntuVm.cmd
```

只做预检，不安装、不下载：

```powershell
.\Install-UbuntuVm.cmd -DryRun
```

## 可选：构建 VM

默认不构建 VM。确实要构建时，用户必须显式传入密码：

```powershell
.\Install-UbuntuVm.cmd -BuildVm -RootPassword "your-password" -ForceRebuild
```

Packer 构建完成后，脚本只输出 `.vmx` 路径，不会自动启动。用户可以在 VMware Workstation 里打开 `.vmx`，也可以手动运行：

```powershell
& "C:\Program Files\VMware\VMware Workstation\vmrun.exe" start "<vmx路径>" gui
```

## 默认配置

- Ubuntu：Ubuntu Server 24.04.4 LTS
- CPU：2 vCPU
- 内存：4096 MB
- 磁盘：40960 MB
- 网络：VMware NAT
- 语言环境：简体中文 `zh_CN.UTF-8`
- 时区：`Asia/Shanghai`
- 项目目录：默认由 bootstrap 安装到 `%USERPROFILE%\UbuntuVmwareAuto`
- VM 输出目录：默认在项目目录下的 `machines`

## VMware 下载源

默认 VMware 安装包地址：

```text
https://cf.comss.org/download/VMware-Workstation-Full-26H1-25388281.exe
```

这是第三方源。脚本会在安装前校验 Authenticode 签名，只接受签名发布者包含 `VMware` 或 `Broadcom` 的安装包。也可以传入 `-VmwareInstallerSha256` 做额外哈希校验。

## 常用参数

- `-VmwareInstallerUrl`：覆盖默认 VMware 安装包下载地址。
- `-VmwareInstallerPath`：使用本地 VMware 安装包。
- `-VmwareInstallerSha256`：强制校验 VMware 安装包 SHA256。
- `-VmName`：虚拟机名称，默认 `ubuntu-24.04-server-auto`。
- `-VmRoot`：虚拟机输出目录；默认是项目目录下的 `machines`。
- `-CpuCount`：CPU 数量，默认 `2`。
- `-MemoryMB`：内存大小，默认 `4096`。
- `-DiskMB`：磁盘大小，默认 `40960`。
- `-UbuntuIsoUrl`：Ubuntu ISO 地址或本地 ISO 路径。
- `-UbuntuIsoChecksum`：Ubuntu ISO 校验值。
- `-DryRun`：只预检，不执行安装和下载。
- `-BuildVm`：显式进入 Packer 构建流程。
- `-RootPassword`：构建 VM 时设置 root 密码。
- `-RootPasswordHash`：构建 VM 时直接传入 SHA-512 crypt 哈希。
- `-ForceRebuild`：删除并重建已有虚拟机输出目录。
- `-ShowConsole`：构建时显示 VMware 窗口。
- `-SkipVmwareInstall`：跳过 VMware 安装，只检查现有 VMware。

## 验证

运行静态检查：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Static.Tests.ps1
```

Packer 模板语法检查：

```powershell
packer validate -syntax-only .\packer\ubuntu-server.pkr.hcl
```

Packer 模板使用 VMware 插件源 `github.com/vmware/vmware`。

## 安全说明

不要把弱密码用于公网或不可信网络。默认准备模式不会写入任何 VM 密码，只有用户显式 `-BuildVm -RootPassword` 时才会把密码写入 cloud-init 配置。
