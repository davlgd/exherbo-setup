#!/bin/bash

# Script to init the disk, download and extract the stage3 tarball, starts configuring the system

STAGE_URL="https://stages.exherbolinux.org/x86_64-pc-linux-gnu"
STAGE_FILE="exherbo-x86_64-pc-linux-gnu-gcc-current.tar.xz"
SCRIPT_DIR=$PWD

# Set the target device, show usage if more than one argument or --help is given
DISK="/dev/sda"

if [ $# -gt 1 ] || [[ $1 == "--help" ]]; then
echo "Exherbo Setup - Exherbo Linux Installation Script"
echo "Usage:"
echo "  ./init.sh <device>    - Installs Exherbo Linux on the specified device."
echo "  ./init.sh             - Installs Exherbo Linux on /dev/sda by default."
echo ""
echo "Options:"
echo "  <device>    - The target device for Exherbo Linux installation."
echo "                Example: ./init.sh /dev/nvme0n1"
echo ""
echo "Description:"
echo "  Exherbo Setup is a simple script to automate the installation of Exherbo Linux."
echo "  It can be run with a specific target device or without any arguments,"
echo "  in which case it will use /dev/sda as the default installation target."
echo ""
echo "  WARNING: This script will format the target device and install Exherbo Linux."
echo "           Make sure to back up any important data on the device before proceeding."
echo ""
echo "For more information on Exherbo Linux installation, visit:"
echo "https://github.com/davlgd/exherbo-setup"
exit
elif [ $# -eq 1 ] && [ -b "$1" ]; then
    DISK=$1
fi

get_disk_partitions() {
    if [[ ${DISK} == /dev/sd* ]]; then
        PART_EFI=${DISK}1
        PART_BOOT=${DISK}2
        PART_ROOT=${DISK}3
    elif [[ ${DISK} == /dev/nvme* ]]; then
        PART_EFI=${DISK}p1
        PART_BOOT=${DISK}p2
        PART_ROOT=${DISK}p3
    else
        echo "Storage device not recognized"
        exit 1
    fi
}

wipe_disk() {
    read -p $"You're about to wipe ${DISK}. Do you want to continue? [y/N] " -n 1 -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]
    then
        echo
        exit 1
    fi

    wipefs -a ${DISK}
}

create_partitions() {
    # Create the filesystems
    # - FAT32 for the Boot &EFI partition
    # - ext4 for the root partition
    # - Label the partitions
    mkfs.fat -F 32 ${PART_EFI} -n EFI
    fatlabel ${PART_EFI} EFI
    mkfs.fat -F 32 ${PART_BOOT} -n BOOT
    e2label ${PART_BOOT} BOOT
    mkfs.ext4 ${PART_ROOT} -L EXHERBO
    e2label ${PART_ROOT} EXHERBO
}

mount_stage() {
    # Create the mountpoint and mount the root partition
    mkdir -p /mnt/exherbo/
    mount ${PART_ROOT} /mnt/exherbo
    cd /mnt/exherbo

    # Download and extract the stage3 tarball
    curl -Os ${STAGE_URL}/${STAGE_FILE}

    # Download and verify the checksum
    # For now it leads to an error: the filename is not good in the checksum file
    curl -Os ${STAGE_URL}/${STAGE_FILE}.sha256sum
    diff -q ${STAGE_FILE}.sha256sum <(sha256sum ${STAGE_FILE}) > /dev/null && echo "The file and the sha256 sum match" || echo "The file and the sha256 sum do not match"

    # Extract the tarball and remove it
    tar xJpf ${STAGE_FILE}
    rm ${STAGE_FILE}*
}

prepare_chroot() {
    echo '
    # <fs>                      <mountpoint>    <type> <opts>   <dump/pass>
    /dev/disk/by-label/EFI      /efi            vfat   defaults 0 0
    /dev/disk/by-label/BOOT     /boot           vfat   defaults 0 0
    /dev/disk/by-label/EXHERBO  /               ext4   defaults 0 0' > /mnt/exherbo/etc/fstab

    mount -o rbind /dev /mnt/exherbo/dev
    mount -o bind /sys /mnt/exherbo/sys
    mount -t proc none /mnt/exherbo/proc
    mount -o x-mount.mkdir /dev/sda1 /mnt/exherbo/efi
    mount /dev/sda2 /mnt/exherbo/boot
}

echo "Exherbo Linux will be installed on ${DISK}"
echo
echo "You need to create at least 3 partitions:" 
echo " - /     : Linux Filesystem"
echo " - /boot : Linux Extended Boot"
echo " - /efi  : EFI System"
echo

wipe_disk > /dev/null
echo
echo -n "cfdsik will be launched to allow partition creation..." 
echo && read -n 1 -s -r -p "Press any key to continue..."

echo "label: gpt"   | sfdisk -W always ${DISK} > /dev/null 2>&1
echo ", 512M, U"    | sfdisk -W always -a ${DISK} > /dev/null 2>&1
echo ", 512M, L"    | sfdisk -W always -a ${DISK} > /dev/null 2>&1
echo ","            | sfdisk -W always -a ${DISK} > /dev/null 2>&1
cfdisk ${DISK} 
get_disk_partitions

clear
echo '

    ███████╗██╗  ██╗██╗  ██╗███████╗██████╗ ██████╗  ██████╗ 
    ██╔════╝╚██╗██╔╝██║  ██║██╔════╝██╔══██╗██╔══██╗██╔═══██╗
    █████╗   ╚███╔╝ ███████║█████╗  ██████╔╝██████╔╝██║   ██║
    ██╔══╝   ██╔██╗ ██╔══██║██╔══╝  ██╔══██╗██╔══██╗██║   ██║
    ███████╗██╔╝ ██╗██║  ██║███████╗██║  ██║██████╔╝╚██████╔╝
    ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚═════╝  ╚═════╝ 
                                                            
'

echo -n "Partitions creation..."
create_partitions > /dev/null  2>&1
echo -ne "\r\033[K"
echo -e " - Disk wiped & new partition created: \e[92m\u2713\e[0m" 

echo -n "Download Exherbo Linux stage3 tarball and mount in '/'..."
mount_stage > /dev/null 2>&1
echo -ne "\r\033[K"
echo -e " - Exherbo Linux downloaded & setup: \e[92m\u2713\e[0m" 

echo -n "Prepare chroot..."
prepare_chroot > /dev/null 2>&1
echo -ne "\r\033[K"
echo -e " - Chroot prepared: \e[92m\u2713\e[0m" 
echo 

# Let's chroot!
cp ${SCRIPT_DIR}/chrooted.sh /mnt/exherbo
env -i TERM=$TERM SHELL=/bin/bash HOME=$HOME $(which chroot) /mnt/exherbo /bin/bash chrooted.sh

# It's the end my friend
rm /mnt/exherbo/chrooted.sh
cd / && umount -R /mnt/exherbo
umount -l /mnt/exherbo
reboot