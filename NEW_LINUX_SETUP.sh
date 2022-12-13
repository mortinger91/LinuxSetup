echo "New Linux installation setup:"


# Section 0
echo "  0 - initial setup:"

# Detecting distribution (Debian or Manjaro)
if [ sudo apt --version >/dev/null 2>&1 ]
then
	echo "Detected Manjaro"
	PKG_MANAGER="sudo pacman -S --noconfirm"
	DISTRO="Manjaro"
else
	echo "Detected Debian"
	PKG_MANAGER="sudo apt install -y"
	DISTRO="Debian"
fi

userName=$(whoami)
echo "Username is: ${userName}"


# Section 1
echo "  1 - Configuring sudo:"
echo "    Configure sudo (y/n)?"
read answer
if [ "$answer" == "${answer#[Yy]}" ]
then
	echo "    Skipping sudo"
else

	su -c "usermod -a -G sudo ${userName}"

	su -c "echo \"${userName} ALL=(ALL:ALL) NOPASSWD: ALL\" | tee /etc/sudoers.d/${userName}"

fi


# Section 2
echo "  2 - Configuring touchpad gestures:"
echo "    Configure touchpad gestures (y/n)?"
read answer
if [ "$answer" == "${answer#[Yy]}" ]
then
	echo "    Skipping touchpad gestures"
else

	${PKG_MANAGER} libinput-tools libinput-gestures xdotool

	mkdir ~/.config >/dev/null 2>&1

	echo -e "# Swipe threshold (0-100) \n swipe_threshold 0 \n \n # Gestures \n gesture swipe left 3 xdotool key ctrl+shift+Tab \n gesture swipe right 3 xdotool key ctrl+Tab \n gesture swipe left 4 xdotool key ctrl+w \n gesture swipe right 4 xdotool key ctrl+t \n gesture swipe up 3 xdotool key ctrl+alt+Up \n gesture swipe down 3 xdotool key ctrl+alt+Down" \
	> ~/.config/libinput-gestures.conf

	sudo usermod -a -G input ${userName}

	libinput-gestures-setup stop desktop autostart start

	# DEBUG IF NOT WORKING
	# check output of these commands:
	#   libinput-gestures -l
	#   libinput-gestures-setup status
	# this can be needed:
	#   sudo libinput-gestures-setup install

fi


# Section 3
echo "  3 - Configuring .bashrc and .bash_aliases:"
echo "    Configure .bashrc and .bash_aliases (y/n)?"
read answer
if [ "$answer" == "${answer#[Yy]}" ]
then
	echo "    Skipping bash"
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
	myrc="${myrc}\nHISTCONTROL=ignoreboth"
	myrc="${myrc}\n"
	myrc="${myrc}\n# append to the history file, don't overwrite it"
	myrc="${myrc}\nshopt -s histappend"
	myrc="${myrc}\n"
	myrc="${myrc}\n# for setting history length see HISTSIZE and HISTFILESIZE in bash(1)"
	myrc="${myrc}\nHISTSIZE=10000"
	myrc="${myrc}\nHISTFILESIZE=20000"
	myrc="${myrc}\n"
	myrc="${myrc}\n# check the window size after each command and, if necessary,"
	myrc="${myrc}\n# update the values of LINES and COLUMNS."
	myrc="${myrc}\nshopt -s checkwinsize"
	myrc="${myrc}\n"
	myrc="${myrc}\n# If set, the pattern \"**\" used in a pathname expansion context will"
	myrc="${myrc}\n# match all files and zero or more directories and subdirectories."
	myrc="${myrc}\n#shopt -s globstar"
	myrc="${myrc}\n"
	myrc="${myrc}\n# make less more friendly for non-text input files, see lesspipe(1)"
	myrc="${myrc}\n#[ -x /usr/bin/lesspipe ] && eval \""'$(SHELL=/bin/sh lesspipe)'"\""
	myrc="${myrc}\n"
	myrc="${myrc}\n# set variable identifying the chroot you work in (used in the prompt below)"
	myrc="${myrc}\nif [ -z \"""\${debian_chroot:-}""\" ] && [ -r /etc/debian_chroot ]; then"
	myrc="${myrc}\n    debian_chroot=""\$(cat /etc/debian_chroot)"
	myrc="${myrc}\nfi"
	myrc="${myrc}\n"
	myrc="${myrc}\n# functions for git branch of the current directory"
	myrc="${myrc}\ngit_branch_arrow() {"
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
	myrc="${myrc}\n# export PATH=/newdir:\$PATH"
	myrc="${myrc}\n"

	touch ~/.bashrc
	echo -e $myrc > ~/.bashrc
	sed -i 's/è//g' ~/.bashrc

	# Writing ~/.bash_aliases file
	mydefaliases="# My Bash default aliases:"
	# Package update
	if [ "$DISTRO" == "Debian" ]
	then
		mydefaliases="${mydefaliases}\n   alias up='sudo apt update && sudo apt full-upgrade -y'"
	else
		mydefaliases="${mydefaliases}\n   alias up='sudo pacman -Syyu'"
	fi
	# Other default aliases
	mydefaliases="${mydefaliases}\n   alias ls='ls -lah --color'"
	mydefaliases="${mydefaliases}\n   alias myip='echo -e \"Current IP address: \$(dig +short myip.opendns.com @resolver1.opendns.com)\"'"
	mydefaliases="${mydefaliases}\n"

	touch ~/.bash_aliases
	echo -e $mydefaliases > ~/.bash_aliases

	# Writing ~/.bash_custom_aliases file
	myaliases="# My Bash custom aliases:"
	myaliases="${myaliases}\n   # alias myalias='mycmd'"
	myaliases="${myaliases}\n"

	touch ~/.bash_custom_aliases
	echo -e $myaliases > ~/.bash_custom_aliases

fi


# Section 4
echo "  4 - Installing useful packages:"
echo "    Install useful packages (y/n)?"
read answer
if [ "$answer" == "${answer#[Yy]}" ]
then
	echo "    Skipping useful packages"
else
	if [ "$DISTRO" == "Debian" ]
	then
		# Debian packages
		${PKG_MANAGER} apt-transport-https apt-utils bear build-tools clang curl dnsutils fonts-firacode gcc g++ gdb git git-gui git-lfs gitk gnome-keyring gnupg gzip htop libreoffice lldb llvm net-tools openssl python3 tlp ssh sshfs ssl-cert unzip nmap
	else
		# Manjaro packages
		${PKG_MANAGER} git dnsutils
	fi

fi 


# Section 5
echo "  5 - Perform configuration:"
echo "    Perform configuration (y/n)?"
read answer
if [ "$answer" == "${answer#[Yy]}" ]
then
	echo "    Skipping configuration"
else
	# Configuring git
	echo "Insert git user.name:"
	read name
	git config --global user.name $name
	echo "Insert git user.email:"
	read email
	git config --global user.email $email
	git config --global credential.helper store
	git config --global pull.ff only
	git config --global pull.rebase false
	git config --global init.defaultBranch master
	echo "Do you want to setup git signing (y/n)?"
	read answer
	if [ "$answer" == "${answer#[Nn]}" ]
	then
		echo "Insert gpg key ID:"
		read keyid
		git config --global user.signingKey $keyid
		git config --global commit.gpgSign true
	fi
	echo "Do you want to review your git configuration (y/n)?"
	read answer
	if [ "$answer" == "${answer#[Nn]}" ]
	then
		git config --list
	fi

	# Configuring git lfs
	git lfs install
fi


echo "New Linux installation setup completed, rebooting is recommended"
echo "Reboot the system (y/n)?"
read answer
if [ "$answer" == "${answer#[Yy]}" ]
then
	echo "Skipping reboot"
else

	sudo reboot now

fi 

# ALSO PART OF THE CONFIGURATION:
#	- folder onBoot with script fixKDE e TLP
#	- binaries autostarted in KDE autolaunch
#	- cronjobs
#	- KDE: theme, settings