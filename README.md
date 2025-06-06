# LinuxSetup

Setup of a freshly installed Linux system, how I like it.  
After the first install, the config can be easily updated.  
This helps if you want to keep multiple machines in sync with the same config.  
Supports Debian-like systems.

## First time setup on a new machine:

1 - choose a folder: `~/dev`  
2 - `mkdir ~/dev`  
3 - `git clone https://github.com/mortinger91/LinuxSetup.git ~/dev/LinuxSetup`  
4 - `~/dev/LinuxSetup/init-config.sh`

Make sure to use the absolute path of the repo when running the `init-config.sh` script.

## How to pull latest changes to your local config:

1 - `update-config`

## How to add changes to the remote config:

1 - Modify or add any new file in the `scripts` private repo. Do not push new changes to this repo, they will be overridden
