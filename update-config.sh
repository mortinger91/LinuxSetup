#!/bin/bash

# Assume we are running this script after the `update_config()`
# bash function has pulled the latest changes from the git remote.

function print_color() {
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

# Update a file
function file_update() {
    local file=$1

    git diff ~/$file $file >/dev/null 2>&1
    diff_found=$?

    set -e

    if [ $diff_found -ne 0 ]; then
        echo "Showing diff between local and remote $file file:"
        git --no-pager diff --no-index --color=always ~/$file $file
        print_color yellow "Do you want to update $file (y/n)?"
        read -r answer
        if [ "$answer" == "${answer#[Yy]}" ]; then
            print_color red "Not updating $file"
        else
            mv -i $file ~/$file
        fi
    fi

    set +e
}

file_update .zshrc_custom
file_update .zshrc_custom_aliases

print_color white "Config was updated!"
