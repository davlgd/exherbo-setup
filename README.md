# Exherbo VM Installer

This repository contains scripts for installing Exherbo Linux in a (x86_64) virtual machine environment with EFI support. It's based on the [official documentation](https://www.exherbolinux.org/docs/install-guide.html), [Alexherbo's](https://alexherbo2.github.io/wiki/exherbo/install-guide/) and [s0dyy's](https://gist.github.com/s0dyy/905be36b2c39fb8c14906e15c05c68a3) guides, some friends' scripts.

## Description

The project is composed of two main scripts:

1. `init.sh`: Initializes the disk, downloads, and extracts Exherbo's stage3 tarball. It sets up disk partitioning, configures DNS and chroot.
2. `chrooted.sh`: Once in the chroot environment, this script configures the Exherbo system, including setting the language, time zone, compiles the Linux kernel and setup to boot loader (sort of, for now)

## Prerequisites

- A virtual machine or an environment where you can execute bash scripts.
- An internet connection to download the necessary files.
- A Live Linux image with a SSH acces, for example [System Rescue](https://www.system-rescue.org/Download/) :
  - Start on the ISO with EFI (Secure boot disabled)
  - Select a `Boot System Rescue` entry
  - Edit (`e`) to add the `nofirewall` (QWERTY keyboard) directive at the end of the `Linux` line
  - Launch with `CTRL+X` or `F10`
  - When you're in the shell as `root`, load your keyboard preferences (e.g. `loadkeys fr`)
  - Change the root password (`passwd`)
  - Show network configuration of the VM (`ip a`)
  - Connect from another machine if needed

  If you prefer to setup exherbo from the VM, you don't need the `nofirewall` directive or to add a root password.

## Usage

1. **Preparation:**
   - Git clone to download the `init.sh` and `chrooted.sh` scripts to your working environment.
   - Ensure the scripts are executable (`chmod +x`).

2. **Executing the `init.sh` script:**
   - This script will prepare your virtual hard disk and download Exherbo stage3.
   - Modify the variables in the script as needed (e.g., disk configuration).

3. **Chroot and Setup:**
   - After running `init.sh`, it will chroot into the Exherbo environment.
   - `chrooted.sh` will configure the system, including kernel compilation.

## Configuration

- The `chrooted.sh` script includes configuration options like hostname, Linux kernel version, and locale.
- You can adjust these settings as needed before running the script.

## Support

For any questions or issues regarding these scripts, feel free to open an issue in this repository.
