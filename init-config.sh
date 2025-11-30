#!/bin/bash

function init_config() {
  if [ "$USERNAME" == "root" ]; then
    print_color red "WARNING: Run the script as your user, not root!"
    exit 1
  fi

  echo "Do you want to configure the system? (y/n)"
  read -r answer
  if [[ "$answer" == "${answer#[Yy]}" ]]; then
    print_color yellow "Exiting configuration script"
    exit 1
  fi

  # Detecting distribution
  if ! command -v apt >/dev/null 2>&1; then
    print_color red "Detected non Debian system, exiting the script"
    exit 1
  fi

  # Checking if Xorg is in use.
  # If this is run from ssh it will return tty, ignore it
  if [ "$XDG_SESSION_TYPE" == "xorg" ]; then
    print_color yellow "WARNING: you running Xorg, consider switching to Wayland"
  fi

  echo "Detected architecture: $(dpkg --print-architecture)"

  # Check if secure boot is enabled
  if ! command -v mokutil >/dev/null 2>&1; then
    print_color yellow "Could not check if secure boot is enabled or not"
  else
    if mokutil --sb-state | grep -q "SecureBoot enabled"; then
      echo "Secure Boot is enabled, as expected!"
    else
      print_color red "WARNING: Secure Boot is disabled"
    fi
  fi

  # Check if hard drive is encrypted
  if lsblk -nf | grep -qi "luk"; then
    echo "Hard drive is encrypted, as expected!"
  else
    print_color red "WARNING: Hard drive seems to not be encrypted"
  fi
}

function init_sudo() {
  echo "Do you want to configure sudo? (y/n)"
  read -r answer
  if [[ "$answer" == "${answer#[Yy]}" ]]; then
    print_color yellow "Skipped sudo configuration"
    return
  fi

  su -c "/sbin/usermod -a -G sudo ${USERNAME}"

  # Right now NOPASSWD is on ALL which is not ideal (but still quite convenient).
  # Change it to something like this to include only some commands:
  # NOPASSWD:/usr/bin/apt update, /usr/bin/apt upgrade
  su -c "echo \"${USERNAME} ALL=(ALL:ALL) NOPASSWD: ALL\" | tee /etc/sudoers.d/${USERNAME}"

  echo "sudo configuration completed!"

  # TODO: Add check that /etc/sudoers.d/${USERNAME} exists and is correct

  print_color green "Open a new shell, relaunch the script and skip sudo configuration"
  exit 0
}

function init_touchpad_gestures() {
  echo "Do you want to configure touchpad gestures? (y/n)"
  read -r answer
  if [[ "$answer" == "${answer#[Yy]}" ]]; then
    print_color yellow "Skipped touchpad gestures configuration"
    return
  fi

  ${PKG_UPDATE}
  ${PKG_INSTALL} make

  # Building libinput-gestures from github
  mkdir -p ~/dev >/dev/null 2>&1
  git clone https://github.com/bulletmark/libinput-gestures.git ~/dev/libinput-gestures
  sudo make -C ~/dev/libinput-gestures install
  # or "sudo ./libinput-gestures-setup install"

  ${PKG_INSTALL} wmctrl
  ${PKG_INSTALL} libinput-tools

  mkdir -p ~/.config >/dev/null 2>&1

  echo "Pick either xdotool or ydotool:"
  echo "Use (x)dotool on x11 and (y)dotool on Wayland (x/y)"
  read -r answer
  if [[ "$answer" == "${answer#[Xx]}" ]]; then
    echo "Configuring touchpad gestures to use xdotool"

    ${PKG_INSTALL} xdotool

    echo -e '# Swipe threshold (0-100)
swipe_threshold 0\n
# Gestures:
gesture swipe left 3 xdotool key ctrl+shift+Tab
gesture swipe right 3 xdotool key ctrl+Tab
gesture swipe left 4 xdotool key ctrl+w
gesture swipe right 4 xdotool key ctrl+t
# These have no effect due to Kwin KDE6 already using these gestures (ARGH!)
# gesture swipe up 3 xdotool key ctrl+alt+Up
# gesture swipe down 3 xdotool key ctrl+alt+Down' \
    > ~/.config/libinput-gestures.conf

  else
    echo "Configuring touchpad gestures to use ydotool"

    # Installing yodotool
    ${PKG_INSTALL} scdoc
    git clone https://github.com/ReimuNotMoe/ydotool.git ~/dev/ydotool
    mkdir ~/dev/ydotool/build
    cmake -B ~/dev/ydotool/build -S ~/dev/ydotool
    make -C ~/dev/ydotool/build
    sudo make -C ~/dev/ydotool/build install

    # Creating the ydotool service for the ydotoold daemon
    sudo touch /etc/systemd/system/ydotool.service

    echo -e '[Unit]
Description=ydotool daemon
Documentation=https://github.com/ReimuNotMoe/ydotool\n
[Service]
Type=simple
ExecStart=/usr/local/bin/ydotoold --socket-path=/run/user/1000/.ydotool_socket --socket-perm 0666
Restart=always\n
[Install]
WantedBy=multi-user.target' \
    | sudo tee /etc/systemd/system/ydotool.service

    # Running the ydotool service
    sudo systemctl daemon-reload
    sudo systemctl enable ydotool
    sudo systemctl start ydotool

    # Checking that the service is running as expected
    sudo systemctl status ydotool

    echo -e '# Swipe threshold (0-100)
swipe_threshold 0\n
# Gestures:
gesture swipe left 3 ydotool key 29:1 42:1 15:1 15:0 29:0 42:0
gesture swipe right 3 ydotool key 29:1 15:1 15:0 29:0
gesture swipe left 4 ydotool key 29:1 17:1 17:0 29:0
gesture swipe right 4 ydotool key 29:1 20:1 20:0 29:0
# These have no effect due to Kwin KDE6 already using these gestures (ARGH!)
# gesture swipe up 3 ydotool key ctrl+alt+Up
# gesture swipe down 3 ydotool key ctrl+alt+Down' \
    > ~/.config/libinput-gestures.conf
  fi

  sudo usermod -a -G input "${USERNAME}"

  libinput-gestures-setup stop desktop autostart start

  # DEBUG IF NOT WORKING
  # check output of these commands:
  #   libinput-gestures -l
  #   libinput-gestures-setup status
  # this can be needed (run it in the repo folder):
  #   sudo libinput-gestures-setup install
}

function init_install_ohmyzsh() {
  echo "Do you want to install oh my zsh? (y/n)"
  read -r answer
  if [[ "$answer" == "${answer#[Yy]}" ]]; then
    print_color yellow "Skipped oh my zsh installation"
    return
  fi

  ${PKG_UPDATE}
  ${PKG_INSTALL} zsh
  ${PKG_INSTALL} curl
  echo "After oh-my-zsh installation, exit to continue the setup"
  set -e
  sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
  set +e
}

function init_configure_zsh() {
  echo "Do you want to configure zsh? (y/n)"
  read -r answer
  if [[ "$answer" == "${answer#[Yy]}" ]]; then
    print_color yellow "Skipped zsh configuration"
    return
  fi

  cat ~/.bash_history >> ~/.zsh_history

  # Add .zshrc_custom link to .zshrc file
  CONFIG_DIR=$SCRIPT_PATH
  CONFIG_DIR=${CONFIG_DIR%/}
  echo "CONFIG_DIR: $CONFIG_DIR"
  echo -e "
export CONFIG_DIR=${CONFIG_DIR}
# Custom .zshrc file:
if [ -f ~/.zshrc_custom ]; then
  . ~/.zshrc_custom
fi" \
  >> ~/.zshrc

  # Commented out since it's added back in .zshrc_custom
  sed -i 's/^source $ZSH\/oh-my-zsh.sh/#source $ZSH\/oh-my-zsh.sh/' ~/.zshrc

  print_color white "Showing ~/.zshrc file after changes:"
  cat ~/.zshrc
}

function init_git() {
  echo "Do you want to perform git configuration? (y/n)"
  read -r answer
  if [[ "$answer" == "${answer#[Yy]}" ]]; then
    print_color yellow "Skipped git configuration"
    return
  fi

  ${PKG_UPDATE}
  ${PKG_INSTALL} git
  ${PKG_INSTALL} git-lfs

  echo "Insert git user.name:"
  read -r name
  git config --global user.name "${name}"
  echo "Insert git user.email:"
  read -r email
  git config --global user.email "${email}"
  git config --global credential.usehttppath true
  git config --global pull.ff only
  git config --global pull.rebase false
  git config --global init.defaultBranch master
  touch /home/$USERNAME/.gitignore_global
  git config --global core.excludesfile /home/$USERNAME/.gitignore_global
  echo "Do you want to setup git signing? (y/n)"
  read -r answer
  if [[ "$answer" == "${answer#[Nn]}" ]]; then
    echo "Insert gpg key ID:"
    read -r keyid
    git config --global user.signingKey "${keyid}"
    git config --global commit.gpgSign true
  else
      git config --global commit.gpgSign false
  fi

  # Configuring git lfs
  git lfs install

  print_color white "Review your git configuration"
  git config --global --list --show-origin
}

function init_grub() {
  echo "Do you want to perform grub configuration? (y/n)"
  read -r answer
  if [[ "$answer" == "${answer#[Yy]}" ]]; then
    print_color yellow "Skipped grub configuration"
    return
  fi
  echo -e "\n# User defined resolution for grub\nGRUB_GFXMODE=640x480\n" \
  | sudo tee -a /etc/default/grub
  sudo update-grub
}

function install_packages() {
  echo "Do you want to install the packages? (y/n)"
  read -r answer
  if [[ "$answer" == "${answer#[Yy]}" ]]; then
    print_color yellow "Skipped packages installation"
    return
  fi
  $SCRIPT_PATH/install-deps.sh init
}

function init_config_files() {
  echo "Do you want to sync the config files? (y/n)"
  read -r answer
  if [[ "$answer" == "${answer#[Yy]}" ]]; then
    print_color yellow "Skipped config files sync"
    return
  fi
  # The init argument will make the script skip the deps check
  $SCRIPT_PATH/update-config.sh init
}

SCRIPT_PATH=$(dirname "${BASH_SOURCE[0]}")
if [[ "${SCRIPT_PATH:0:1}" != "/" ]]; then
  echo "This script needs to be called with the absolute path"
  exit 1
fi
cd $SCRIPT_PATH

source print-color.sh

print_color green "New Linux installation setup"

USERNAME=$(whoami)
PKG_UPDATE="sudo apt-get update"
PKG_INSTALL="sudo apt-get install -y"

init_config
init_sudo
init_touchpad_gestures
init_install_ohmyzsh
init_configure_zsh
init_git
init_grub
install_packages
init_config_files

print_color green "First setup completed!"
print_color white "Close the terminal for all the changes to take place"
