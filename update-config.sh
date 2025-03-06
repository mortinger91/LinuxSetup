#!/bin/bash

# Assume we are running this script after the `update_config()`
# bash function has pulled the latest changes from the git remote.

function print_color() {
  local color=$1
  local text=$2

  case "$color" in
    red)     color_code="1;31" ;;
    green)   color_code="0;32" ;;
    yellow)  color_code="1;33" ;;
    blue)    color_code="0;34" ;;
    purple)  color_code="0;35" ;;
    cyan)    color_code="0;36" ;;
    white)   color_code="1;37" ;;
    *)       color_code="0;37" ;;
  esac
  echo -e "\033[${color_code}m${text}\033[0m"
}

# Update a file
function file_update() {
  local file=$1

  git diff /$file $file >/dev/null 2>&1
  diff_found=$?

  if [ $diff_found -ne 0 ]; then
    echo "Showing diff between local and remote $file file:"
    if command -v code >/dev/null 2>&1; then
      code --diff ~/$file $file
    else
      git --no-pager diff --no-index --color=always ~/$file $file
    fi
    print_color yellow "Do you want to update $file (y/n)?"
    read -r answer
    if [ "$answer" == "${answer#[Yy]}" ]; then
      print_color red "Not updating $file"
    else
      sudo cp -i -p $file ~/$file
    fi
  fi
}

# All the files that I want to update
config_files=(
  "home/my_user/.zshrc_custom"
  "home/my_user/.zshrc_custom_aliases"
  "etc/bluetooth/main.conf"
  "home/my_user/.config/bat/config"
)

for config_file in "${config_files[@]}"; do
  # Substitute the string "my_user" with the actual user
  file="${file//my_user/$(whoami)}"
  file_update "$config_file"
done

print_color white "Config was updated!"
