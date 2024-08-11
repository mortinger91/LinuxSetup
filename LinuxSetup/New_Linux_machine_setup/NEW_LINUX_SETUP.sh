#!/bin/bash

#####################################################
# How to download and run this script:
#
# 1 - su -c "apt update"
# 2 - su -c "apt install curl"
# 3 - cd ~
# 4 - curl -L -O https://github.com/mortinger91/LinuxSetup/raw/master/LinuxSetup/New_Linux_machine_setup.zip
# 5 - unzip New_Linux_machine_setup.zip
# 6 - cd New_Linux_machine_setup
# 7 - ./NEW_LINUX_SETUP.sh
#####################################################


echo "New Linux installation setup:"

userName=$(whoami)
echo "Username is: ${userName}"

if [ "$userName" == "root" ]; then
    echo "Run the script as your user, not root!"
    exit 1
fi

echo "Do you want to configure the system (y/n)?"
read -r answer
if [ "$answer" == "${answer#[Yy]}" ]; then
    echo "Exiting configuration script"
	exit
fi


# Section 0
echo "  0 - initial setup:"

# Detecting distribution (Debian or Manjaro)
apt --version >/dev/null 2>&1
if [ $? -ne 0 ]; then
	echo "Detected Manjaro"
	PKG_INSTALL="sudo pacman -S --noconfirm"
	DISTRO="Manjaro"
else
	echo "Detected Debian"
	PKG_INSTALL="sudo apt install -y"
	DISTRO="Debian"
fi

# Checking if Xorg or Wayland is in use
if [ "$XDG_SESSION_TYPE" == "x11" ]; then
	echo "Xorg in use as expected!"
else
	echo "Wayland in use, consider switching to Xorg!"
fi

ARCH=$(dpkg --print-architecture)
echo "Detected architecture: ${ARCH}"


# Section 1
echo "  1 - Configuring sudo:"
echo "    Do you want to configure sudo (y/n)?"
read -r answer
if [ "$answer" == "${answer#[Yy]}" ]; then
	echo -e "    Skipping sudo configuration\n"
else

	su -c "/sbin/usermod -a -G sudo ${userName}"

	# Right now NOPASSWD is on ALL which is not ideal (but still quite convenient).
	# Change it to something like this to include only some commands:
	# NOPASSWD:/usr/bin/apt update, /usr/bin/apt upgrade
	su -c "echo \"${userName} ALL=(ALL:ALL) NOPASSWD: ALL\" | tee /etc/sudoers.d/${userName}"

	echo "sudo configuration completed!"

    # TODO: Add check that /etc/sudoers.d/${userName} exists and is correct

	echo "Open a new shell, relaunch the script and skip sudo configuration"
	exit
fi


# Section 2
echo "  2 - Configuring touchpad gestures:"
echo "    Do you want to configure touchpad gestures (y/n)?"
read -r answer
if [ "$answer" == "${answer#[Yy]}" ]; then
	echo -e "    Skipping touchpad gestures configuration\n"
else
	if [ "$DISTRO" == "Debian" ]; then
		${PKG_UPDATE}
		${PKG_INSTALL} make

		# Building libinput-gestures from github
		mkdir ~/temp
		cd ~/temp || exit
		git clone https://github.com/bulletmark/libinput-gestures.git
		cd libinput-gestures || exit
		sudo make install
		# or "sudo ./libinput-gestures-setup install"
	else
		# This package may be available only on AUR
		${PKG_INSTALL} libinput-gestures
	fi

	${PKG_INSTALL} wmctrl
	${PKG_INSTALL} libinput-tools
	${PKG_INSTALL} xdotool

	mkdir ~/.config >/dev/null 2>&1

	echo -e "# Swipe threshold (0-100)\nswipe_threshold 0\n\n# Gestures\n gesture swipe left 3 xdotool key ctrl+shift+Tab\ngesture swipe right 3 xdotool key ctrl+Tab\ngesture swipe left 4 xdotool key ctrl+w\ngesture swipe right 4 xdotool key ctrl+t\ngesture swipe up 3 xdotool key ctrl+alt+Up\ngesture swipe down 3 xdotool key ctrl+alt+Down" \
	> ~/.config/libinput-gestures.conf

	sudo usermod -a -G input "${userName}"

	libinput-gestures-setup stop desktop autostart start

	# DEBUG IF NOT WORKING
	# check output of these commands:
	#   libinput-gestures -l
	#   libinput-gestures-setup status
	# this can be needed (run it in the repo folder):
	#   sudo libinput-gestures-setup install
fi


# Section 3
echo "  3a - Installing oh my zsh:"
echo "    Do you want to install oh my zsh (y/n)?"
read -r answer
if [ "$answer" == "${answer#[Yy]}" ]; then
	echo -e "    Skipping oh my zsh installation\n"
else
    ${PKG_INSTALL} zsh
    sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

echo "  3b - Configuring .zshrc and aliases:"
echo "    Do you want to configure .zshrc and aliases (y/n)?"
read -r answer
if [ "$answer" == "${answer#[Yy]}" ]; then
	echo -e "    Skipping .zshrc and aliases configuration\n"
else
    echo "    Do you want to perform a dry-run (y/n)?"
    read -r answer
    if [ "$answer" == "${answer#[Yy]}" ]; then
        targetDir="/home/${userName}"
    else
        echo -e "    Performing .zshrc dry run\n"
        mkdir test >/dev/null 2>&1
        targetDir="test"
        rm "$targetDir/.zshrc" >/dev/null 2>&1
        touch "$targetDir/.zshrc"
    fi

    set -x
	echo "Copying .zshrc_custom and .zsh_custom_aliases files"
	cp .zshrc_custom $targetDir/.zshrc_custom
	cp .zsh_custom_aliases $targetDir/.zsh_custom_aliases

    echo "Adding .zshrc_custom link to ~/.zshrc file"
    echo -e "\n# Custom .zshrc file:\nif [ -f ~/.zshrc_custom ]; then\n  . ~/.zshrc_custom\nfi" >> $targetDir/.zshrc
    set +x
fi


# Section 4
echo "  4 - Installing useful packages:"
echo "    Do you want to install useful packages (y/n)?"
read -r answer
if [ "$answer" == "${answer#[Yy]}" ]; then
	echo -e "    Skipping useful packages installation\n"
else
	if [ "$DISTRO" == "Debian" ]; then
		${PKG_UPDATE}

		# Debian packages
		${PKG_INSTALL} apt-transport-https
		${PKG_INSTALL} apt-utils
		${PKG_INSTALL} autoconf
		${PKG_INSTALL} bash-completion
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
		${PKG_INSTALL} tcpdump
		${PKG_INSTALL} tlp
		${PKG_INSTALL} ssh
		${PKG_INSTALL} sshfs
		${PKG_INSTALL} ssl-cert
		${PKG_INSTALL} telegram-desktop
		${PKG_INSTALL} unzip
		${PKG_INSTALL} wget
		${PKG_INSTALL} whereis
		${PKG_INSTALL} xclip

		echo "    Do you want to install Visual Studio Code (y/n)?"
		read -r answer
		if [ "$answer" == "${answer#[Yy]}" ]; then
			echo "Skipping VSCode"
		else
			mkdir ~/temp
			cd ~/temp || exit

			# Visual Studio Code installation
			wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg
			sudo install -D -o root -g root -m 644 packages.microsoft.gpg /etc/apt/keyrings/packages.microsoft.gpg
			sudo sh -c 'echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list'
			rm -f packages.microsoft.gpg
			${PKG_UPDATE}
			${PKG_INSTALL} code
		fi

		echo "    Do you want to install Google Chrome (y/n)?"
		read -r answer
		if [ "$answer" == "${answer#[Yy]}" ]; then
			echo "Skipping Google Chrome"
		else
			mkdir ~/temp
			cd ~/temp || exit

			# Google Chrome installation
			wget https://dl.google.com/linux/direct/google-chrome-stable_current_${ARCH}.deb
			sudo dpkg -i google-chrome-stable_current_${ARCH}.deb
		fi

		echo "    Do you want to install Wireshark (y/n)?"
		read -r answer
		if [ "$answer" == "${answer#[Yy]}" ]; then
			echo "Skipping Wireshark"
		else
			${PKG_INSTALL} wireshark
			sudo usermod -a -G wireshark "${userName}"
		fi

		echo "    Do you want to install Rust Toolchain (y/n)?"
		read -r answer
		if [ "$answer" == "${answer#[Yy]}" ]; then
			echo "Skipping Rust Toolchain"
		else
			curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
		fi

		echo "    Do you want to install Docker (y/n)?"
		read -r answer
		if [ "$answer" == "${answer#[Yy]}" ]; then
			echo "Skipping Docker"
		else
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
		fi

        echo "    Do you want to install fzf (y/n)?"
		read -r answer
		if [ "$answer" == "${answer#[Yy]}" ]; then
			echo "Skipping fzf"
		else
            # Used for fzf and other user installed binaries
            mkdir /home/${userName}/bin

            echo -e "Download fzf from the Github official page:\nhttps://github.com/junegunn/fzf/releases\nBe careful to choose the right architecture.\nThen copy the fzf binary to /home/${userName}/bin"
        fi
	else
		# Manjaro packages
		${PKG_INSTALL} git
		${PKG_INSTALL} dnsutils
	fi

fi


# Section 5
echo "  5 - Perform git configuration:"
echo "    Do you want to perform git configuration (y/n)?"
read -r answer
if [ "$answer" == "${answer#[Yy]}" ]; then
	echo -e "    Skipping git configuration\n"
else
	# Configuring git
	echo "Insert git user.name:"
	read -r name
	git config --global user.name "${name}"
	echo "Insert git user.email:"
	read -r email
	git config --global user.email "${email}"
	git config --global credential.helper store
	git config --global pull.ff only
	git config --global pull.rebase false
	echo "Insert git default branch name:"
	read -r default
	git config --global init.defaultBranch "${default}"
	echo "Do you want to setup git signing (y/n)?"
	read -r answer
	if [ "$answer" == "${answer#[Nn]}" ]; then
		echo "Insert gpg key ID:"
		read -r keyid
		git config --global user.signingKey "${keyid}"
		git config --global commit.gpgSign true
    else
        git config --global commit.gpgSign false
	fi
	echo "Do you want to review your git configuration (y/n)?"
	read -r answer
	if [ "$answer" == "${answer#[Nn]}" ]; then
		git config --list
	fi

	# Configuring git lfs
	git lfs install --system
fi


# Section 6
echo "  6 - Perform grub configuration:"
echo "    Do you want to perform grub configuration (y/n)?"
read -r answer
if [ "$answer" == "${answer#[Yy]}" ]; then
	echo -e "    Skipping grub configuration\n"
else
	echo -e "#User defined resolution for grub\nGRUB_GFXMODE=640x480\n" | sudo tee -a /etc/default/grub
	sudo update-grub
fi


# Section 7
echo "  7 - Perform KDE configuration:"
echo "    Do you want to perform KDE configuration (y/n)?"
read -r answer
if [ "$answer" == "${answer#[Yy]}" ]; then
	echo -e "    Skipping KDE configuration\n"
else
	echo "    Copying KDE configuration..."
	# COPY THESE FOLDERS AND FILES IN ORDER TO
	# HAVE THE SAME KDE CONFIGURATION ACROSS MULTIPLE MACHINES
	#
	# ~/.local/share/konsole/*
	# ~/.local/share/kservices5/*
	# ~/.local/share/kwin/*
	# ~/.local/share/kxmlgui5/konsole/*
	# ~/.local/share/kxmlgui5/dolphin/*
	# ~/.local/share/networkmanagement/*
	#
	# This contains the user installed widgets, it is advised to
	# download them again in the new system and do not copy this folder
	# ~/.local/share/plasma/plasmoids/*
	#
	# ~/.cargo/*
	# ~/.kde/*
	# ~/.config/autostart/*
	# ~/.config/kdedefaults/*
	# ~/.config/xsettingsd/*
	# ~/.config/dolphinrc
	# ~/.config/kmcfonts
	# ~/.config/kcminputrc
	# ~/.config/kconf_updaterc
	# ~/.config/kded5rc
	# ~/.config/kdeglobals
	# ~/.config/kdeglobalshortcutsrc
	# ~/.config/konsolerc
	# ~/.config/kscreenlockerrc
	# ~/.config/ktimezonedrc
	# ~/.config/kwinrc
	# ~/.config/kwinrulesrc
	# ~/.config/plasma-localerc
	# ~/.config/plasma-org.kde.plasma.desktop-appletsrc
	# ~/.config/powermanagementprofilesrc
	# ~/.config/touchpadxlibinputrc
	#
	#
	# WIDGETS USED:
	#
	# System Load Viewer
	# Thermal Monitor
	# Configurable button
	#
	# Non-KDE specific
	# ~/.local/share/fonts/*
	# ~/.selected_editor
	# ~/.local/share/TelegramDesktop/*
	# ~/Templates/*
fi


echo "New Linux installation setup completed, rebooting is recommended"
echo "Reboot the system (y/n)?"
read -r answer
if [ "$answer" == "${answer#[Yy]}" ]; then
	echo "Skipping reboot"
else
	sudo reboot now
fi

# Add scripts from BootScripts repository for a machine specific configuration:
# Go to KDE settings "Startup and Shutdown"/"Autostart" and add:
# /home/michele/dev/BootScripts/fixKDE/fixKDE.sh
# Configure "MX Ergo Multi-Device Trackball " device using https://github.com/PixlOne/logiops
