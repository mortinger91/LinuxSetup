#!/bin/bash

function installAptPackages() {
  ${PKG_UPDATE}
  ${PKG_INSTALL} apt-transport-https
  ${PKG_INSTALL} apt-utils
  ${PKG_INSTALL} autoconf
  ${PKG_INSTALL} bash-completion
  ${PKG_INSTALL} bat
  ${PKG_INSTALL} bear
  ${PKG_INSTALL} bpfcc-tools
  ${PKG_INSTALL} bpftrace
  ${PKG_INSTALL} build-tools
  ${PKG_INSTALL} ca-certificates
  ${PKG_INSTALL} ccache
  ${PKG_INSTALL} clang
  ${PKG_INSTALL} clangd
  ${PKG_INSTALL} clang-format
  ${PKG_INSTALL} cmake
  ${PKG_INSTALL} curl
  ${PKG_INSTALL} dnsutils
  ${PKG_INSTALL} firmware-iwlwifi
  ${PKG_INSTALL} fonts-firacode
  ${PKG_INSTALL} g++
  ${PKG_INSTALL} gcc
  ${PKG_INSTALL} gdb
  ${PKG_INSTALL} git
  ${PKG_INSTALL} git-gui
  ${PKG_INSTALL} git-lfs
  ${PKG_INSTALL} gitk
  ${PKG_INSTALL} gnome-keyring
  ${PKG_INSTALL} gnupg
  ${PKG_INSTALL} gparted
  ${PKG_INSTALL} gzip
  ${PKG_INSTALL} htop
  ${PKG_INSTALL} locales-all
  ${PKG_INSTALL} locate
  ${PKG_INSTALL} libevdev-dev
  ${PKG_INSTALL} libudev-dev
  ${PKG_INSTALL} libconfig++-dev
  ${PKG_INSTALL} libreoffice
  # OpenGL development
  ${PKG_INSTALL} libgl1-mesa-dev
  ${PKG_INSTALL} libxcursor-dev
  ${PKG_INSTALL} libxi-dev
  ${PKG_INSTALL} libxinerama-dev
  ${PKG_INSTALL} libxrandr-dev
  ${PKG_INSTALL} libxss-dev
  # End of OpenGL development
  ${PKG_INSTALL} lsb-release
  ${PKG_INSTALL} lldb
  ${PKG_INSTALL} llvm
  ${PKG_INSTALL} lm-sensors
  ${PKG_INSTALL} nmap
  ${PKG_INSTALL} net-tools
  ${PKG_INSTALL} network-manager-openvpn
  ${PKG_INSTALL} nginx
  ${PKG_INSTALL} make
  ${PKG_INSTALL} openssl
  ${PKG_INSTALL} python3
  ${PKG_INSTALL} python3-venv
  ${PKG_INSTALL} ripgrep
  ${PKG_INSTALL} tcpdump
  ${PKG_INSTALL} ssh
  ${PKG_INSTALL} sshfs
  ${PKG_INSTALL} ssl-cert
  ${PKG_INSTALL} telegram-desktop
  ${PKG_INSTALL} trash-cli
  ${PKG_INSTALL} tmux
  ${PKG_INSTALL} unzip
  ${PKG_INSTALL} wget
  ${PKG_INSTALL} whereis
  ${PKG_INSTALL} xclip
}

function installManualPackages() {
  echo "Cloning zsh-autosuggestions plugin"
  git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions

  echo "Cloning zsh-syntax-highlighting plugin"
  git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting

  echo "Cloning the best theme ever (michelebira)"
  ${PKG_INSTALL} wget
  wget https://raw.githubusercontent.com/mortinger91/michelebira/refs/heads/master/michelebira.zsh-theme -P ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/themes

  echo "Configure Xozide"
  curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh

  echo " Install Visual Studio Code"
  mkdir ~/temp
  cd ~/temp || exit
  # Visual Studio Code installation
  wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg
  sudo install -D -o root -g root -m 644 packages.microsoft.gpg /etc/apt/keyrings/packages.microsoft.gpg
  sudo sh -c 'echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list'
  rm -f packages.microsoft.gpg
  ${PKG_UPDATE}
  ${PKG_INSTALL} code

  echo "Install Google Chrome"
  mkdir ~/temp
  cd ~/temp || exit
  # Google Chrome installation
  wget https://dl.google.com/linux/direct/google-chrome-stable_current_${ARCH}.deb
  sudo dpkg -i google-chrome-stable_current_${ARCH}.deb


  echo "Install Wireshark"
  ${PKG_INSTALL} wireshark
  sudo usermod -a -G wireshark "${userName}"

  echo "Install Rust Toolchain"
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

  echo "Install Docker"
  sudo mkdir -m 0755 -p /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  ${PKG_UPDATE}
  # If update throws an error try this command:
  # sudo chmod a+r /etc/apt/keyrings/docker.gpg
  ${PKG_INSTALL} docker docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  sudo groupadd docker
  sudo usermod -aG docker "${userName}"
  echo "Testing docker installation, reboot to test without sudo"
  sudo docker run hello-world

  echo "Install fzf"
  # Used for fzf and other user installed binaries
  mkdir -p /home/${userName}/.local/bin
  echo -e "Download fzf from the Github official page:\nhttps://github.com/junegunn/fzf/releases\nBe careful to choose the right architecture: ${ARCH}.\nThen copy the fzf binary to /home/${userName}/.local/bin"
}

PKG_UPDATE="sudo apt-get update"
PKG_INSTALL="sudo apt-get install -y"
userName=$(whoami)
ARCH=$(dpkg --print-architecture)

installAptPackages
installManualPackages
