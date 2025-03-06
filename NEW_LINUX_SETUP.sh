#!/bin/bash

# General notes:
## /boot partition:
#  To be on the safe side, allocate 2GB of space for the /boot partition.
#  Debian 13 seems to throw a rather annoying warning everytime you update
#  saying it needs 255MB of free space in the /boot partition.
#  Also, 500MB is not enough if you want to install more than 2/3 kernels anyway.

echo "New Linux installation setup:"

userName=$(whoami)
echo "Username is: ${userName}"

if [ "$userName" == "root" ]; then
    echo "WARNING: Run the script as your user, not root!"
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
	echo "Detected non Debian system, exiting the script"
	exit 1
else
	echo "Detected Debian"
	PKG_INSTALL="sudo apt install -y"
	DISTRO="Debian"
fi

# Checking if Xorg or Wayland is in use
if [ "$XDG_SESSION_TYPE" == "wayland" ]; then
	echo "You running Wayland, as expected!"
else
	echo "WARNING: you running Xorg, consider switching to Wayland"
fi

ARCH=$(dpkg --print-architecture)
echo "Detected architecture: ${ARCH}"

# Check if secure boot is enabled
if mokutil --sb-state | grep -q "SecureBoot enabled"; then
    echo "Secure Boot is enabled, as expected!"
else
    echo "WARNING: Secure Boot is disabled"
fi

# Check if hard drive is encrypted
if lsblk -nf | grep -qi "luk"; then
    echo "Hard drive seems to be encrypted, as expected!"
else
    echo "WARNING: Hard drive seems to not be encrypted"
fi



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
echo "  2a - Configuring touchpad gestures:"
echo "    Do you want to configure touchpad gestures (y/n)?"
read -r answer
if [ "$answer" == "${answer#[Yy]}" ]; then
	echo -e "    Skipping touchpad gestures configuration\n"
else
    currentDir=$(pwd)
	if [ "$DISTRO" == "Debian" ]; then
		${PKG_UPDATE}
		${PKG_INSTALL} make

		# Building libinput-gestures from github
		mkdir ~/dev
		cd ~/dev || exit
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

    mkdir -p ~/.config >/dev/null 2>&1

    echo "  2b - Pick either xdotool or ydotool:"
    echo "    Use (x)dotool on x11 and (y)dotool on Wayland (x/y)?"
    read -r answer
    if [ "$answer" == "${answer#[Xx]}" ]; then
        echo -e "    Configuring touchpad gestures to use xdotool\n"

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
        echo -e "    Configuring touchpad gestures to use ydotool\n"

        # Installing yodotool
        ${PKG_INSTALL} scdoc
        cd ~/dev
        git clone https://github.com/ReimuNotMoe/ydotool.git
        mkdir build && cd build
        cd build
        cmake ..
        make
        sudo make install

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

	sudo usermod -a -G input "${userName}"

	libinput-gestures-setup stop desktop autostart start

	# DEBUG IF NOT WORKING
	# check output of these commands:
	#   libinput-gestures -l
	#   libinput-gestures-setup status
	# this can be needed (run it in the repo folder):
	#   sudo libinput-gestures-setup install

    cd $currentDir
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

echo "  3b - Performinig .zshrc one time configuration:"
echo "    Do you want to perform .zshrc one time configuration (y/n)?"
read -r answer
if [ "$answer" == "${answer#[Yy]}" ]; then
	echo -e "    Skipping .zshrc configuration\n"
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

    # Not needed, just run update-config.sh
    # echo "Copying .zshrc_custom and .zsh_custom_aliases files"
	# cp .zshrc_custom $targetDir/.zshrc_custom
	# cp .zsh_custom_aliases $targetDir/.zsh_custom_aliases

    set -x
    # Add .zshrc_custom link to .zshrc file
    echo -e "\n# Custom .zshrc file:\nif [ -f ~/.zshrc_custom ]; then\n  . ~/.zshrc_custom\nfi" >> $targetDir/.zshrc
    set +x

    # Commenting out source since it's added in .zshrc_custom
    sed -i '/^source $ZSH/oh-my-zsh.sh/c\# source $ZSH/oh-my-zsh.sh)' ~/.zshrc

    # Not needed anymore
    # echo "Before: $(grep "^plugins=(" ~/.zshrc)"
    # sed -i '/^plugins=(/c\plugins=(git zsh-autosuggestions zsh-syntax-highlighting)' ~/.zshrc
    # echo "After: $(grep "^plugins=" ~/.zshrc)"

    # echo "Remember to set: ZSH_THEME=\"michelebira\", HYPHEN_INSENSITIVE=\"true\" and COMPLETION_WAITING_DOTS=\"true\" (or don't!)"
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
		git config --list --show-origin
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



# KDE CONFIGS.
# THIS IS NOT RECOMMENDED. JUST RE-DO THE CONFIGS MANUALLY,
# MESSING WITH THESE FILES CAN LEAD TO A BROKEN CONFIG IF KDE VERSIONS ARE NOT THE SAME.
#
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



echo "New Linux installation setup completed, rebooting is recommended"
echo "Reboot the system (y/n)?"
read -r answer
if [ "$answer" == "${answer#[Yy]}" ]; then
	echo "Skipping reboot"
else
	sudo reboot now
fi



# ON BOOT SCRIPTS:
# Add scripts from BootScripts repository (if necessary).
# Go to KDE settings "Startup and Shutdown"/"Autostart" and add
# `/home/michele/dev/BootScripts/onBoot.sh`
#
# LOGITECH TRACKBALL MOUSE:
# Configure "MX Ergo Multi-Device Trackball" buttons using https://github.com/PixlOne/logiops
