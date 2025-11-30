#!/bin/bash

#TODO: Add some arguments so that you can distinguish between init, update and user running manually. Make the user run manually mode the one without arguments.

# Distinguish between essential packages and optionals.
# Essential: packages that you would want also on a raspberry pi or a 1 core VPS.
# Optional: heavier packages like Google Chrome, telegram. Not always needed.

# Present the user a choice during init about which packages to install.
# Make sure that the ones that gets installed are updated during update-config.
# Give the user the possibility to go back and run install-deps manually,
# selecting a package that was not choosen.

# SUPER EXTRA STRETCH GOAL: Make a terminal UI that when launched shows the installed
# packages with a [*] and non installed with [ ].
# It is possible to select multiple packages and install them.
# The same UI will auto run during init-config and can be manually triggered anytime.

# We want to install all these packages on all systems
# We may want to check if any of these are missing when running update-config
aptEssentialPackages=(
  "apt-transport-https"
  "apt-utils"
  "autoconf"
  "bash-completion"
  "bat"
  "bear"
  "bpfcc-tools"
  "bpftrace"
  "build-essential"
  "ca-certificates"
  "ccache"
  "clang"
  "clangd"
  "clang-format"
  "cmake"
  "curl"
  "dnsutils"
  "fonts-firacode"
  "fwupd"
  "g++"
  "gcc"
  "gdb"
  "git"
  "git-gui"
  "git-lfs"
  "gitk"
  "gnome-keyring"
  "gnupg"
  "gparted"
  "gzip"
  "htop"
  "locales-all"
  "locate"
  "libevdev-dev"
  "libudev-dev"
  "libconfig++-dev"
  "lsb-release"
  "lldb"
  "llvm"
  "lm-sensors"
  "nmap"
  "net-tools"
  "network-manager-openvpn"
  "nfs-common"
  "make"
  "openssl"
  "python3"
  "python3-venv"
  "ripgrep"
  "ssh"
  "sshfs"
  "ssl-cert"
  "systemd-timesyncd"
  "tcpdump"
  "trash-cli"
  "tmux"
  "unzip"
  "wget"
  "xclip"
  "zsh-autosuggestions"
  "zsh-syntax-highlighting"
)

openGLDevelopmentPackages=(
  "libgl1-mesa-dev"
  "libxcursor-dev"
  "libxi-dev"
  "libxinerama-dev"
  "libxrandr-dev"
  "libxss-dev"
)

# These packages will be asked one by one during init-config
# or if the user manually run install-deps
aptOptionalPackages=(
  "firmware-iwlwifi"
  "libreoffice"
  "nginx"
  "telegram-desktop"
  "tcpdump"
  "virt-manager"
)

function installAptPackages() {
  ${PKG_UPDATE} >/dev/null 2>&1
  for package in "${aptEssentialPackages[@]}"; do
    if ! dpkg-query -W -f='${Status}' ${package} 2>/dev/null | grep -q "ok installed"; then
      ${PKG_INSTALL} ${package}
    fi
  done
  # create a symbolic link for bat. This is better than an alias since it works also for `sudo bat`
  sudo ln -s /usr/bin/batcat /usr/local/bin/bat >/dev/null 2>&1
}

function installManualPackages() {
  echo "Do you want to clone michelebira oh-my-zsh theme? (y/n)"
  read -r answer
  if [[ "$answer" == [Yy]* ]]; then
    echo "Cloning the best theme ever (michelebira)..."
    curl -fsSL https://raw.githubusercontent.com/mortinger91/michelebira/refs/heads/master/michelebira.zsh-theme -o ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/themes/michelebira.zsh-theme
  fi

  echo "Do you want to install Xozide? (y/n)"
  read -r answer
  if [[ "$answer" == [Yy]* ]]; then
    echo "Installing Xozide..."
    curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh
  fi

  echo "Do you want to install Visual Studio Code? (y/n)"
  read -r answer
  if [[ "$answer" == [Yy]* ]]; then
    echo " Installing Visual Studio Code..."
    sudo mkdir -m 0755 -p /etc/apt/keyrings
    curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /tmp/packages.microsoft.gpg
    sudo install -D -o root -g root -m 644 /tmp/packages.microsoft.gpg /etc/apt/keyrings/packages.microsoft.gpg
    echo "Types: deb
URIs: https://packages.microsoft.com/repos/code/
Suites: stable
Components: main
Signed-By: /etc/apt/keyrings/packages.microsoft.gpg" \
    | sudo tee /etc/apt/sources.list.d/vscode.sources > /dev/null
    ${PKG_UPDATE}
    ${PKG_INSTALL} code
  fi

  echo "Do you want to install Google Chrome? (y/n)"
  read -r answer
  if [[ "$answer" == [Yy]* ]]; then
    echo "Installing Google Chrome..."
    wget https://dl.google.com/linux/direct/google-chrome-stable_current_${ARCH}.deb
    wget -O /tmp/google-chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_${ARCH}.deb
    sudo dpkg -i /tmp/google-chrome.deb
  fi

  echo "Do you want to install Wireshark? (y/n)"
  read -r answer
  if [[ "$answer" == [Yy]* ]]; then
    echo "Installing Wireshark..."
    ${PKG_INSTALL} wireshark
    sudo usermod -a -G wireshark "${USERNAME}"
  fi

  echo "Do you want to install the Rust Toolchain? (y/n)?"
  read -r answer
  if [[ "$answer" == [Yy]* ]]; then
    echo "Installing Rust Toolchain..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
  fi

  # TODO: Currently broken, fix it
#   echo "Do you want to install Docker? (y/n)"
#   read -r answer
#   if [[ "$answer" == [Yy]* ]]; then
#     echo "Installing Docker..."
#     echo "Docker installation is currently broken"; return
#     sudo mkdir -m 0755 -p /etc/apt/keyrings
#     curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /tmp/docker.gpg
#     sudo install -D -o root -g root -m 644 /tmp/docker.gpg /etc/apt/keyrings/docker.gpg
#     echo "Types: deb
# URIs: https://download.docker.com/linux/debian/
# Suites: trixie
# Components: stable
# Signed-By: /etc/apt/keyrings/docker.gpg" \
#     | sudo tee /etc/apt/sources.list.d/docker.sources > /dev/null
#     ${PKG_UPDATE}
#     # If update throws an error try this command:
#     # sudo chmod a+r /etc/apt/keyrings/docker.gpg
#     ${PKG_INSTALL} docker docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
#     sudo groupadd docker
#     sudo usermod -aG docker "${USERNAME}"
#     echo "Testing docker installation, reboot to test without sudo"
#     sudo docker run hello-world
#   fi

  echo "Do you want to install fzf? (y/n)"
  read -r answer
  if [[ "$answer" == [Yy]* ]]; then
    echo "Installing fzf..."
    git clone --depth 1 https://github.com/junegunn/fzf.git /home/${USERNAME}/dev/fzf
    git -C /home/${USERNAME}/dev/fzf fetch --tags
    # Switch to latest tag
    git -C /home/${USERNAME}/dev/fzf switch --detach $(git -C /home/${USERNAME}/dev/fzf describe --tags `git -C /home/${USERNAME}/dev/fzf rev-list --tags --max-count=1`)
    /home/${USERNAME}/dev/fzf/install --bin
    # Used for fzf and other user installed binaries
    mkdir -p /home/${USERNAME}/.local/bin
    sudo mv -i /home/${USERNAME}/dev/fzf/bin/fzf /home/${USERNAME}/.local/bin
  fi

  # This eliminates the need for process decoration or swapping the actual binary
  # in /usr/bin/gdb.
  # The gdb binary can be updated normally via apt and this needs to be
  # done only once
  echo "Do you want to install run_gdb_as_root for root debugging in VSCode? (y/n)"
  read -r answer
  if [[ "$answer" == [Yy]* ]]; then
    echo "Installing run_gdb_as_root..."
    mkdir -p /home/${USERNAME}/.local/bin
    echo -e '#!/bin/bash
sudo /usr/bin/gdb "$@"' \
    > /home/${USERNAME}/.local/bin/run_gdb_as_root
    chmod +x /home/${USERNAME}/.local/bin/run_gdb_as_root
  fi
}

function initInstall() {
  print_color green "Running install script in init mode"
  installAptPackages
  installManualPackages
}

function updateInstall() {
  installAptPackages
}

function manualInstall() {
  print_color green "Running install script in manual mode"
  installManualPackages
}

PKG_UPDATE="sudo apt-get update"
PKG_INSTALL="sudo apt-get install -y"
USERNAME=$(whoami)
ARCH=$(dpkg --print-architecture)

SCRIPT_PATH=$(dirname "${BASH_SOURCE[0]}")
if [[ "${SCRIPT_PATH:0:1}" != "/" ]]; then
  echo "This script needs to be called with the absolute path"
  exit 1
fi
cd $SCRIPT_PATH

source print-color.sh

case "$1" in
  init)
    initInstall ;;
  update)
    updateInstall ;;
  *)
    manualInstall ;;
esac

print_color white "Deps were installed!"
