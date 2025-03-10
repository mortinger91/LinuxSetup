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

function file_update() {
  local fileSource="$1"
  local fileDest="/$1"
  # Substitute the string "my_user" with the actual user
  fileDest="${fileDest//my_user/$(whoami)}"

  git diff $fileDest $fileSource >/dev/null 2>&1
  diff_found=$?

  if [ $diff_found -ne 0 ]; then
    echo "Showing diff between local and remote $(basename "$fileDest") file:"
    if command -v code >/dev/null 2>&1; then
      code --diff $fileDest $fileSource
    else
      git --no-pager diff --no-index --color=always $fileDest $fileSource
    fi
    print_color yellow "Do you want to update $fileDest (y/n)?"
    read -r answer
    if [ "$answer" == "${answer#[Yy]}" ]; then
      print_color red "Not updating $(basename "$fileDest")"
    else
      # Save the original owner of the file
      local owner=$(stat -c "%U:%G" $fileDest)
      sudo cp -i -p $fileSource $fileDest
      # Restore the original owner of the file.
      # Git does not maintain the original owner when you commit a file
      sudo chown $owner $fileDest
    fi
  fi
}

# List of the files that are going to be updated
# Could an be improved by moving all the files that needs to be synced
# to a sync folder, then use `find` to get all the files.
files=(
  "home/my_user/.zshrc_custom"
  "home/my_user/.zshrc_custom_aliases"
  "etc/bluetooth/main.conf"
  "home/my_user/.config/bat/config"
)

# Update all the files
for file in "${files[@]}"; do
  file_update "$file"
done

print_color white "Config was updated!"

# Check and update (if necessary) all the dependencies
# ./install-deps.sh update
# print_color white "Deps were updated!"
