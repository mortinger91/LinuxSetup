#!/bin/bash

#####################################################
# How to download and run this script:
#
# 1 - su -c "apt update"
# 2 - su -c "apt install curl"
# 3 - cd ~
# 4 - curl -O https://raw.githubusercontent.com/mortinger91/LinuxSetup/master/scripts/NEW_LINUX_SETUP.sh
# 5 - chmod +x NEW_LINUX_SETUP.sh
# 6 - ./NEW_LINUX_SETUP.sh
#####################################################


echo "New Linux installation setup:"
echo "Run the script as your user, not root"
echo "Do you want to configure the system (y/n)?"
read -r answer
if [ "$answer" == "${answer#[Yy]}" ]
then
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

userName=$(whoami)
echo "Username is: ${userName}"


# Section 1
echo "  1 - Configuring sudo:"
echo "    Configure sudo (y/n)?"
read -r answer
if [ "$answer" == "${answer#[Yy]}" ]; then
	echo -e "    Skipping sudo\n"
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
echo "    Configure touchpad gestures (y/n)?"
read -r answer
if [ "$answer" == "${answer#[Yy]}" ]; then
	echo -e "    Skipping touchpad gestures\n"
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

	echo -e "# Swipe threshold (0-100) \n swipe_threshold 0 \n \n # Gestures \n gesture swipe left 3 xdotool key ctrl+shift+Tab \n gesture swipe right 3 xdotool key ctrl+Tab \n gesture swipe left 4 xdotool key ctrl+w \n gesture swipe right 4 xdotool key ctrl+t \n gesture swipe up 3 xdotool key ctrl+alt+Up \n gesture swipe down 3 xdotool key ctrl+alt+Down" \
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
echo "  3 - Configuring .bashrc and .bash_aliases:"
echo "    Configure .bashrc and .bash_aliases (y/n)?"
read -r answer
if [ "$answer" == "${answer#[Yy]}" ]; then
	echo -e "    Skipping bash\n"
else

	# ~/.bashrc file
	myrc="# ~/.bashrc: executed by bash(1) for non-login shells."
	myrc="${myrc}\n"
	myrc="${myrc}\n# If not running interactively, don't do anything"
	myrc="${myrc}\ncase \$- in"
	myrc="${myrc}\n    *i*) ;;"
	myrc="${myrc}\n      *) return;;"
	myrc="${myrc}\nesac"
	myrc="${myrc}\n"
	myrc="${myrc}\n# do not put duplicate lines or lines starting with space in the history."
	myrc="${myrc}\n# See bash(1) for more options"
	myrc="${myrc}\n# Not adding clear, hist and history calls to the history"
	myrc="${myrc}\nexport HISTIGNORE=\"clear:hist*\""
	myrc="${myrc}\nexport HISTCONTROL=ignoreboth"
	myrc="${myrc}\n"
	myrc="${myrc}\n# append to the history file, don't overwrite it"
	myrc="${myrc}\nshopt -s histappend"
	myrc="${myrc}\n"
	myrc="${myrc}\n# for setting history length see HISTSIZE and HISTFILESIZE in bash(1)"
	myrc="${myrc}\n# 100k commands are probably enough"
	myrc="${myrc}\nHISTSIZE=100000"
	myrc="${myrc}\n# 2m means roughly 320MBs file"
	myrc="${myrc}\nHISTFILESIZE=2000000"
	myrc="${myrc}\n"
	myrc="${myrc}\n# add a command to the history just before it is executed"
	myrc="${myrc}\nexport PROMPT_COMMAND=\"history -a; history -c; history -r; \$PROMPT_COMMAND\""
	myrc="${myrc}\n# check the window size after each command and, if necessary,"
	myrc="${myrc}\n# update the values of LINES and COLUMNS."
	myrc="${myrc}\nshopt -s checkwinsize"
	myrc="${myrc}\n"
	myrc="${myrc}\n# If set, the pattern \"**\" used in a pathname expansion context will"
	myrc="${myrc}\n# match all files and zero or more directories and subdirectories."
	myrc="${myrc}\n#shopt -s globstar"
	myrc="${myrc}\n"
	myrc="${myrc}\n# ccache makes compilation faster by caching built files"
	myrc="${myrc}\n# this works even if you change branch or delete your build files"
	myrc="${myrc}\nexport COMPILER_LAUNCHER=ccache"
	myrc="${myrc}\n"
	myrc="${myrc}\n# make less more friendly for non-text input files, see lesspipe(1)"
	myrc="${myrc}\n#[ -x /usr/bin/lesspipe ] && eval \""\"$(SHELL=/bin/sh lesspipe)\""\""
	myrc="${myrc}\n"
	myrc="${myrc}\n# set variable identifying the chroot you work in (used in the prompt below)"
	myrc="${myrc}\nif [ -z \"""\${debian_chroot:-}""\" ] && [ -r /etc/debian_chroot ]; then"
	myrc="${myrc}\n    debian_chroot=""\$(cat /etc/debian_chroot)"
	myrc="${myrc}\nfi"
	myrc="${myrc}\n"
	myrc="${myrc}\n# functions for git branch of the current directory"
	myrc="${myrc}\nfunction git_branch_arrow() {"
	myrc="${myrc}\n    onGitFolder=\$(git branch 2> /dev/null)"
	myrc="${myrc}\n    if [[ \$onGitFolder != \"\" ]];"
	myrc="${myrc}\n    then"
	myrc="${myrc}\n        echo \"->\""
	myrc="${myrc}\n    fi"
	myrc="${myrc}\n}"
	myrc="${myrc}\ngit_branch() {"
	myrc="${myrc}\n    git branch 2> /dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/(\1)/' # -e 's/^/->/'"
	myrc="${myrc}\n}"
	myrc="${myrc}\n"
	myrc="${myrc}\nPS1=\"""\${debian_chroot:+(\$debian_chroot)}""\[\è033[0;31m\]""\342\224\214\342\224\200\\\$([[ \\\$? != 0 ]] && echo \\\"[""\[\è033[0;37m\]""\342\234\227""\[\è033[0;31m\]""]\342\224\200\\\")[\$(if [[ \${EUID} == 0 ]]; then echo '""\[\è033[01;31m\]""root""\[\è033[01;33m\]""@""\[\è033[01;96m\]""\h'; else echo '""\[\è033[0;39m\]""\u""\[\è033[01;33m\]""@""\[\è033[01;96m\]""\h'; fi)""\[\è033[1;33m\]""\\\$(git_branch_arrow)""\[\è033[1;35m\]""\\\$(git_branch)""\[\è033[0;31m\]""]\342\224\200[""\[\è033[0;32m\]""\w""\[\è033[0;31m\]""]\èn""\[\è033[0;31m\]""\342\224\224\342\224\200\342\224\200\342\225\274 ""\[\è033[0m\]""\[\èe[01;33m\]""\è\è$è\[\èe[0m\] \""
	myrc="${myrc}\n"
	myrc="${myrc}\n# If this is an xterm set the title to user@host:dir"
	myrc="${myrc}\ncase \"\$TERM\" in"
	myrc="${myrc}\nxterm*|rxvt*)"
	myrc="${myrc}\n    PS1=\"\[\èe]0;""\${debian_chroot:+(\$debian_chroot)}""\u@\h: \w\èa\]\$PS1\""
	myrc="${myrc}\n    ;;"
	myrc="${myrc}\n*)"
	myrc="${myrc}\n    ;;"
	myrc="${myrc}\nesac"
	myrc="${myrc}\n"
	myrc="${myrc}\n# colored GCC warnings and errors"
	myrc="${myrc}\nexport GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'"
	myrc="${myrc}\n"
	myrc="${myrc}\n# Aliases definitions."
	myrc="${myrc}\nif [ -f ~/.bash_aliases ]; then"
	myrc="${myrc}\n    . ~/.bash_aliases"
	myrc="${myrc}\nfi"
	myrc="${myrc}\n"
	myrc="${myrc}\n# Custom aliases definitions."
	myrc="${myrc}\nif [ -f ~/.bash_custom_aliases ]; then"
	myrc="${myrc}\n    . ~/.bash_custom_aliases"
	myrc="${myrc}\nfi"
	myrc="${myrc}\n"
	myrc="${myrc}\n# Enable programmable completion features (you do not need to enable"
	myrc="${myrc}\n# this, if it is already enabled in /etc/bash.bashrc and /etc/profile"
	myrc="${myrc}\n# sources /etc/bash.bashrc)."
	myrc="${myrc}\nif ! shopt -oq posix; then"
	myrc="${myrc}\n  if [ -f /usr/share/bash-completion/bash_completion ]; then"
	myrc="${myrc}\n    . /usr/share/bash-completion/bash_completion"
	myrc="${myrc}\n  elif [ -f /etc/bash_completion ]; then"
	myrc="${myrc}\n    . /etc/bash_completion"
	myrc="${myrc}\n  fi"
	myrc="${myrc}\nfi"
	myrc="${myrc}\n. \"\$HOME/.cargo/env\""
	myrc="${myrc}\n"
	myrc="${myrc}\n# Add directories to the PATH"
	myrc="${myrc}\n# Example: export PATH=/usr/lib/jvm/java-11-openjdk-amd64/bin:\$PATH"
	myrc="${myrc}\n"
	myrc="${myrc}\n export PATH=/home/m/.cargo/bin:\$PATH"
	myrc="${myrc}\n"

	touch ~/.bashrc
	echo -e "${myrc}" > ~/.bashrc
	sed -i 's/è//g' ~/.bashrc

	# Writing ~/.bash_aliases file
	mydefaliases="# My Bash default aliases:"
	# Package update
	if [ "$DISTRO" == "Debian" ]; then
		mydefaliases="${mydefaliases}\n   alias up='sudo apt update && sudo apt full-upgrade -y'"
	else
		mydefaliases="${mydefaliases}\n   alias up='sudo pacman -Syyu'"
	fi
	# Other default aliases
	mydefaliases="${mydefaliases}\n   alias ls='ls -lah --color'"
	mydefaliases="${mydefaliases}\n   alias myip='echo -e \"Current IP address: \$(dig +short myip.opendns.com @resolver1.opendns.com)\"'"
	mydefaliases="${mydefaliases}\n   # Use hist -nX to print last X elements in the history."
	mydefaliases="${mydefaliases}\n   # Use hist -nX git clone to print last X elements in the history"
	mydefaliases="${mydefaliases}\n   # that contains 'git clone'"
	mydefaliases="${mydefaliases}\n   hist() {"
	mydefaliases="${mydefaliases}\n     SEARCH_STR=\"\""
	mydefaliases="${mydefaliases}\n     LINES_COUNT=10"
	mydefaliases="${mydefaliases}\n     for param in \"$@\"; do"
	mydefaliases="${mydefaliases}\n       if [[ \"$param\" =~ -n[0-9]+ ]]; then"
    mydefaliases="${mydefaliases}\n         LINES_COUNT=${param:2}"
    mydefaliases="${mydefaliases}\n       else"
    mydefaliases="${mydefaliases}\n        SEARCH_STR=\"${SEARCH_STR} ${param}\""
    mydefaliases="${mydefaliases}\n       fi"
    mydefaliases="${mydefaliases}\n     done"
    mydefaliases="${mydefaliases}\n     history | grep -i \"$SEARCH_STR\" | tail -n \"$LINES_COUNT\""
    mydefaliases="${mydefaliases}\n   }"

	touch ~/.bash_aliases
	echo -e "${mydefaliases}" > ~/.bash_aliases

	# Writing ~/.bash_custom_aliases file
	myaliases="# My Bash custom aliases:"
	myaliases="${myaliases}\n   # alias myalias='mycmd'"
	myaliases="${myaliases}\n"

	touch ~/.bash_custom_aliases
	echo -e "${myaliases}" > ~/.bash_custom_aliases
fi


# Section 4
echo "  4 - Installing useful packages:"
echo "    Install useful packages (y/n)?"
read -r answer
if [ "$answer" == "${answer#[Yy]}" ]; then
	echo -e "    Skipping useful packages\n"
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
		${PKG_INSTALL} whereis

		echo "    Install Visual Studio Code (y/n)?"
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

		echo "    Install Google Chrome (y/n)?"
		read -r answer
		if [ "$answer" == "${answer#[Yy]}" ]; then
			echo "Skipping Google Chrome"
		else
			mkdir ~/temp
			cd ~/temp || exit

			# Google Chrome installation
			wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
			sudo dpkg -i google-chrome-stable_current_amd64.deb
		fi

		echo "    Install Wireshark (y/n)?"
		read -r answer
		if [ "$answer" == "${answer#[Yy]}" ]; then
			echo "Skipping Wireshark"
		else
			${PKG_INSTALL} wireshark
			sudo usermod -a -G wireshark "${userName}"
		fi

		echo "    Install Rust Toolchain (y/n)?"
		read -r answer
		if [ "$answer" == "${answer#[Yy]}" ]; then
			echo "Skipping Rust Toolchain"
		else
			curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
		fi

		echo "    Install Docker (y/n)?"
		read -r answer
		if [ "$answer" == "${answer#[Yy]}" ]; then
			echo "Skipping Docker"
		else
			sudo mkdir -m 0755 -p /etc/apt/keyrings
			curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
			echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
			${PKG_UPDATE}
			# If update throws an error try this command:
			# sudo chmod a+r /etc/apt/keyrings/docker.gpg
			${PKG_INSTALL} docker docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
			sudo groupadd docker
			sudo usermod -aG docker "${userName}"
			echo "Testing docker installation, reboot to test without sudo"
			sudo docker run hello-world
		fi
	else
		# Manjaro packages
		${PKG_INSTALL} git
		${PKG_INSTALL} dnsutils
	fi

fi


# Section 5
echo "  5 - Perform git configuration:"
echo "    Perform git configuration (y/n)?"
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
echo "  6 - Perform KDE configuration:"
echo "    Perform KDE configuration (y/n)?"
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


# Section 7
echo "  7 - Perform grub configuration:"
echo "    Perform grub configuration (y/n)?"
read -r answer
if [ "$answer" == "${answer#[Yy]}" ]; then
	echo -e "    Skipping grub configuration\n"
else
	echo -e "#User defined resolution for grub\nGRUB_GFXMODE=640x480\n" | sudo tee -a /etc/default/grub
	sudo update-grub
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
