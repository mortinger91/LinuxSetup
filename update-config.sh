#!/bin/bash

function print_color() {
  local color=$1
  local text=$2

  case "$color" in
    red)     color_code="1;31" ;;
    green)   color_code="1;32" ;;
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

  # Create the destination file and the path if they do not not exist
  if [ ! -f "$fileDest" ]; then

    # Get the owner of the closest existing folder to the file
    filePath="$(dirname "$fileDest")"
    existingPath="$filePath"

    while [ ! -d "$existingPath" ] && [ "$existingPath" != "/" ]; do
      existingPath="$(dirname "$existingPath")"
      if [ -d "$existingPath" ]; then
        break
      fi
    done

    mkdir -p "$filePath"
    touch "$fileDest"
    local folderOwner=$(stat -c "%U:%G" "$existingPath")
    sudo chown $folderOwner "$fileDest"
    sudo chmod 644 "$fileDest"
    print_color green "Created new file at $fileDest with owner $folderOwner"
  fi

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

# In order for this to work, the script needs to be called with
# the absolute path.
cd $(dirname "${BASH_SOURCE[0]}")

# Update all the files
for file in "${files[@]}"; do
  file_update "$file"
done

print_color white "Config was updated!"

# Check and update (if necessary) all the dependencies
# ./install-deps.sh update
# print_color white "Deps were updated!"
