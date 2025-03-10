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
  local fileDest="/${fileSource#sync/}"
  # Substitute the string "my_user" with the actual user
  fileDest="${fileDest//my_user/$USERNAME}"

  # Create the destination file and the path if they do not not exist
  if [ ! -f "$fileDest" ]; then
    print_color red "The file $fileDest does not exist"

    filePath="$(dirname "$fileDest")"

    # Get the owner of the closest existing folder to the file
    existingPath="$filePath"
    while [ ! -d "$existingPath" ] && [ "$existingPath" != "/" ]; do
      existingPath="$(dirname "$existingPath")"
      if [ -d "$existingPath" ]; then
        break
      fi
    done

    local folderOwnerAndGroup=$(stat -c "%U:%G" "$existingPath")
    local folderOwner=$(stat -c "%U" "$existingPath")

    if [ "$folderOwner" = "root" ]; then
      sudo mkdir -p "$filePath"
    else
      mkdir -p "$filePath"
    fi

    sudo touch "$fileDest"
    sudo chown $folderOwnerAndGroup "$fileDest"
    # Setting restricting permissions on new files
    sudo chmod 644 "$fileDest"

    print_color green "Created new file $fileDest with owner $folderOwner"
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
      local ownerPermissions=$(stat -c "%a" $fileDest)
      sudo cp -i -p $fileSource $fileDest
      # Restore the original owner of the file.
      # Git does not maintain the original owner when you commit a file
      sudo chown $owner $fileDest
      # Restore also original permission
      sudo chmod $ownerPermissions "$fileDest"
    fi
  fi
}

USERNAME=$(whoami)

# In order for this to work, the script needs to be called with
# the absolute path.
cd $(dirname "${BASH_SOURCE[0]}")

# Get all files in the sync folder
mapfile -t files < <(find sync -type f)

# Update all the files
for file in "${files[@]}"; do
  file_update "$file"
done

print_color white "Config was updated!"

# Check and update (if necessary) all the dependencies
# ./install-deps.sh update
# print_color white "Deps were updated!"
