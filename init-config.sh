#!/bin/bash

echo "First setup completed!"

# set CONFIG_DIR and INTERFACE export vars
dirname ${BASH_SOURCE[0]} # save this to CONFIG_DIR

# We only need to define there CONFIG_DIR and INTERFACE
# since both are system specific and does not need to be modified after 1st setup

# Commented out since it's launched in zshrc_custom
# source $ZSH/oh-my-zsh.sh
#
# comment this from zshrc using sed, add comment that explains that it's moved to zshrc_custom
