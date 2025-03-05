#!/bin/bash

# Assume we are running this script after the `update_config()`
# bash function has pulled the latest changes from the git remote.

function printcolor() {
    local color=$1
    local text=$2

    case "$color" in
        black)   color_code=30 ;;
        red)     color_code=31 ;;
        green)   color_code=32 ;;
        yellow)  color_code=33 ;;
        blue)    color_code=34 ;;
        magenta) color_code=35 ;;
        cyan)    color_code=36 ;;
        white)   color_code=37 ;;
        *)       color_code=37 ;;
    esac
    echo -e "\033[0;${color_code}m${text}\033[0m"
}

set -ex

# Update .zshrc_custom and .zshrc_custom_aliases files
echo "Showing diff between local and remote .zshrc_custom files:"
git --no-pager diff --no-index --color=always ~/.zshrc_custom .zshrc_custom
printcolor yellow "Do you want to update .zshrc_custom (y/n)?"
read -r answer
if [ "$answer" == "${answer#[Yy]}" ]; then
    printcolor red "Not updating .zshrc_custom"
else
    mv -i .zshrc_custom ~/.zshrc_custom
fi

set +ex

echo "Config was updated!!!!!"
