#!/bin/bash

# Script to setup Exherbo once chrooted in the configured stage3

KEYMAP=fr
GRUB_TIMEOUT=0
LANG=fr_FR.UTF-8
CPU_CORES=$(nproc)
HOSTNAME="exherbovm"
LINUX_VERSION="6.6.1"
PALUDIS_CONF="/etc/paludis/options.conf"

# Set the timezone and locale
ln -sf /usr/share/zoneinfo/Europe/Paris /etc/localtime
localedef --inputfile fr_FR --charmap UTF-8 fr_FR.UTF-8
echo "LANG=\"${LANG}\"" > /etc/env.d/99locale
echo KEYMAP=${KEYMAP} > /etc/vconsole.conf

# Sync hardware clock with the current system time
hwclock --systohc --utc

# Set the PS1 variable to distinguish the chrooted environment
source /etc/profile
PS1="(Exherbo) $PS1"

# Set the hostname
echo $HOSTNAME > /etc/hostname
echo "127.0.0.1 $HOSTNAME.local $HOSTNAME localhost" > /etc/hosts
echo "::1 $HOSTNAME.local $HOSTNAME localhost" >> /etc/hosts

# Set the root password
passwd

# Set the paludis options
sed -i "s/jobs=2/jobs=$CPU_CORES/g" $PALUDIS_CONF

# Sync the repositories add some tools
cave sync
cave resolve -x --skip-phase test repository/perl
cave resolve -x --skip-phase test repository/marv
cave resolve -x --skip-phase test -1 sys-apps/systemd
cave resolve -x --skip-phase test repository/hardware
cave resolve -x --skip-phase test linux-firmware nano neofetch

# Download the targeted kernel version sources and compile it
cd /usr/src && mkdir linux && cd linux
curl -O https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-${LINUX_VERSION}.tar.xz
tar xJvf linux-${LINUX_VERSION}.tar.xz
rm linux-${LINUX_VERSION}.tar.xz
cd linux-${LINUX_VERSION}

make defconfig
make -j$(nproc) && make modules_install && make install

# Configue GRUB with the desired timeout
echo "set timeout=${GRUB_TIMEOUT}" >> /etc/grub.d/40_custom 
grub-install /dev/sda
grub-mkconfig -o /boot/grub/grub.cfg

# Enable network services at boot
systemctl enable sshd
systemctl enable dhcpcd

# Enable TTY login at boot
systemctl enable getty@ 

exit