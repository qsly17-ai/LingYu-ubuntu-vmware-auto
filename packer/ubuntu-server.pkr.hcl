packer {
  required_version = ">= 1.10.0"

  required_plugins {
    vmware = {
      version = ">= 2.1.3"
      source  = "github.com/vmware/vmware"
    }
  }
}

variable "vm_name" {
  type = string
}

variable "output_dir" {
  type = string
}

variable "iso_url" {
  type = string
}

variable "iso_checksum" {
  type = string
}

variable "http_dir" {
  type = string
}

variable "ssh_username" {
  type = string
}

variable "ssh_password" {
  type      = string
  sensitive = true
}

variable "bootstrap_username" {
  type = string
}

variable "lock_bootstrap_user" {
  type = bool
}

variable "cpu_count" {
  type = number
}

variable "memory_mb" {
  type = number
}

variable "disk_size_mb" {
  type = number
}

variable "headless" {
  type = bool
}

source "vmware-iso" "ubuntu_server" {
  vm_name          = var.vm_name
  output_directory = var.output_dir
  iso_url          = var.iso_url
  iso_checksum     = var.iso_checksum

  guest_os_type = "ubuntu-64"
  firmware      = "bios"
  version       = 21
  headless      = var.headless
  format        = "vmx"

  cpus      = var.cpu_count
  memory    = var.memory_mb
  disk_size = var.disk_size_mb

  vmdk_name            = var.vm_name
  network              = "nat"
  network_adapter_type = "e1000"
  disk_adapter_type    = "scsi"
  disk_type_id         = "1"
  sound                = false
  usb                  = false
  skip_compaction      = false

  http_directory = var.http_dir
  boot_wait      = "10s"
  boot_command = [
    "e<wait><down><down><down><end> autoinstall 'ds=nocloud;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/'<F10>"
  ]

  communicator           = "ssh"
  ssh_username           = var.ssh_username
  ssh_password           = var.ssh_password
  ssh_timeout            = "90m"
  ssh_handshake_attempts = 120
  shutdown_command       = "shutdown -P now"
}

build {
  sources = ["source.vmware-iso.ubuntu_server"]

  provisioner "shell" {
    inline = [
      "cloud-init status --wait",
      "systemctl is-active ssh",
      "sudo sshd -T | grep -i '^permitrootlogin '",
      "vmtoolsd --version || true",
      "sudo rm -f /etc/sudoers.d/90-codex-bootstrap",
      "if [ \"$LOCK_BOOTSTRAP_USER\" = \"true\" ]; then sudo passwd -l \"$BOOTSTRAP_USER\"; else echo \"Leaving bootstrap user enabled for first-login fallback.\"; fi"
    ]
    environment_vars = [
      "BOOTSTRAP_USER=${var.bootstrap_username}",
      "LOCK_BOOTSTRAP_USER=${var.lock_bootstrap_user ? "true" : "false"}"
    ]
  }
}
