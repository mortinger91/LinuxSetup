#!/bin/bash

# Assume we are running this script after the `update_config()`
# bash function has pulled the latest changes from the git remote.

set -ex

# Update .zshrc_custom and .zshrc_custom_aliases files
echo "Showing diff between local and remote .zshrc_custom files"
git --no-pager diff --no-index --color=always .zshrc_custom ~/.zshrc_custom

set +ex

echo "Config was updated!!!!!"
