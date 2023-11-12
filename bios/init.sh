#!/bin/bash

STAGE_FILE="exherbo-x86_64-pc-linux-gnu-gcc-current.tar.xz"
STAGE_URL="https://stages.exherbolinux.org/x86_64-pc-linux-gnu"
SCRIPT_DIR=$PWD
DISK="/dev/sda"

# Script to init the disk, download and extract the stage3 tarball, starts configuring the system

# Wipe the disk
# Define the partition layout
# - EFI partition of 512M, type Linux Filesystem
# - Root partition with the remaining space, type Linux filesystem
wipefs -a ${DISK}
echo ", 512M, U"    | sfdisk -W always ${DISK}
echo ","            | sfdisk -W always -a ${DISK}

# Create the filesystems
# - ext2 for the boot partition
# - ext4 for the root partition
# - Label the partitions
mkfs.ext2 ${DISK}1 -L Boot
e2label ${DISK}1 Boot
mkfs.ext4 ${DISK}2 -L Exherbo
e2label ${DISK}2 Exherbo

# Create the mountpoint and mount the root partition
mkdir -p /mnt/exherbo/
mount /dev/disk/by-label/Exherbo /mnt/exherbo
cd /mnt/exherbo && mkdir -p boot

# Download and extract the stage3 tarball
curl -O ${STAGE_URL}/${STAGE_FILE}

# Download and verify the checksum
# For now it leads to an error: the filename is not good in the checksum file
curl -O ${STAGE_URL}/${STAGE_FILE}.sha256sum
diff -q ${STAGE_FILE}.sha256sum <(sha256sum ${STAGE_FILE}) > /dev/null && echo "The file and the sha256 sum match" || echo "The file and the sha256 sum do not match"

# Extract the tarball and remove it
tar xJpf ${STAGE_FILE}
rm ${STAGE_FILE}*

# Define the partition to be mounted at boot
cat <<EOF > /mnt/exherbo/etc/fstab
# <fs>                      <mountpoint>    <type> <opts>   <dump/pass>
/dev/disk/by-label/Exherbo  /               ext4   defaults 0 0
/dev/disk/by-label/Boot     /boot           ext2   defaults 0 0
EOF

# chroot into the new system
mount -o rbind /dev /mnt/exherbo/dev
mount -o bind /sys /mnt/exherbo/sys
mount -t proc none /mnt/exherbo/proc
mount /dev/disk/by-label/Boot /mnt/exherbo/boot

# Configure the DNS resolvers
echo 'nameserver 1.1.1.1
nameserver 9.9.9.9' > /mnt/exherbo/etc/resolv.conf

# Let's chroot!
cp ${SCRIPT_DIR}/chrooted.sh /mnt/exherbo
env -i TERM=$TERM SHELL=/bin/bash HOME=$HOME $(which chroot) /mnt/exherbo /bin/bash chrooted.sh

# It's the end my friend
cd / && umount -R /mnt/exherbo
umount -l /mnt/exherbo
reboot