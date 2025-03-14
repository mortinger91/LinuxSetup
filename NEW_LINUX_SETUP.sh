#!/bin/bash

# General notes:
## /boot partition:
#  To be on the safe side, allocate 2GB of space for the /boot partition.
#  Debian 13 seems to throw a rather annoying warning everytime you update
#  saying it needs 255MB of free space in the /boot partition.
#  Also, 500MB is not enough if you want to install more than 2/3 kernels anyway.
















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
