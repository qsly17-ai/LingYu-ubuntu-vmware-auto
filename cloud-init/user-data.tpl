#cloud-config
autoinstall:
  version: 1
  locale: zh_CN.UTF-8
  keyboard:
    layout: us
  timezone: Asia/Shanghai
  identity:
    hostname: ${hostname}
    username: ${bootstrap_username}
    password: ${bootstrap_password_hash}
  ssh:
    install-server: true
    allow-pw: true
  packages:
    - openssh-server
    - open-vm-tools
    - language-pack-zh-hans
    - fonts-noto-cjk
  storage:
    layout:
      name: direct
  late-commands:
    - curtin in-target --target=/target -- /bin/sh -c "locale-gen zh_CN.UTF-8 && update-locale LANG=zh_CN.UTF-8 LANGUAGE=zh_CN:zh"
    - curtin in-target --target=/target -- timedatectl set-timezone Asia/Shanghai
    - curtin in-target --target=/target -- /bin/sh -c "echo 'root:${root_password_hash}' | chpasswd -e"
    - curtin in-target --target=/target -- /bin/sh -c "install -d -m 0755 /etc/ssh/sshd_config.d"
    - curtin in-target --target=/target -- /bin/sh -c "printf '%s\n' 'PermitRootLogin yes' 'PasswordAuthentication yes' > /etc/ssh/sshd_config.d/99-root-login.conf"
    - curtin in-target --target=/target -- /bin/sh -c "printf '%s\n' '${bootstrap_username} ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/90-codex-bootstrap && chmod 0440 /etc/sudoers.d/90-codex-bootstrap"
    - curtin in-target --target=/target -- systemctl enable ssh
    - curtin in-target --target=/target -- systemctl enable open-vm-tools
