#!/bin/bash

# Script to setup Exherbo once chrooted in the configured stage3

HOSTNAME="exherbovm"
LINUX_VERSION="6.6.1"
LANG=fr_FR.UTF-8
CPU_CORES=$(nproc)
PALUDIS_CONF="/etc/paludis/options.conf"

# Set the timezone and locale
ln -sf /usr/share/zoneinfo/Europe/Paris /etc/localtime
localedef --inputfile fr_FR --charmap UTF-8 fr_FR.UTF-8
echo "LANG=\"${LANG}\"" > /etc/env.d/02locale

# Sync hardware clock with the current system time
hwclock --systohc --utc

# Set the PS1 variable to distinguish the chrooted environment
source /etc/profile
PS1="(Exherbo) $PS1"

# Set the hostname
echo "HOSTNAME=\"$HOSTNAME\"" > /etc/conf.d/hostname
echo "127.0.0.1 localhost $HOSTNAME $HOSTNAME.local" > /etc/hosts
echo "::1 localhost $HOSTNAME $HOSTNAME.local" >> /etc/hosts

# Set the root password
passwd

echo 'sys-apps/systemd efi' >> $PALUDIS_CONF
echo "sys-apps/coreutils xattr" >> $PALUDIS_CONF
sed -i "s/jobs=2/jobs=$CPU_CORES/g" $PALUDIS_CONF

# Sync the repositories add some tools
cave sync
cave resolve -x --skip-phase test repository/perl
cave resolve -x --skip-phase test -1 sys-apps/systemd
cave resolve -x --skip-phase test repository/hardware
cave resolve -x --skip-phase test dracut efibootmgr linux-firmware nano

# Configure Dracut and install systemd-boot
echo "force=\"yes\"" > /etc/dracut.conf.d/force.conf
echo "hostonly=\"yes\"" > /etc/dracut.conf.d/hostonly.conf
echo "hostonly_mode=\"strict\"" >> /etc/dracut.conf.d/hostonly.conf
echo "dracutmodules=\"base bash dracut-systemd fs-lib i18n kernel-modules rootfs-block systemd systemd-initrd terminfo udev-rules usrmount\"" > /etc/dracut.conf.d/modules.conf

mount -t efivarfs efivarfs /sys/firmware/efi/efivars
bootctl --make-machine-id-directory=yes --esp-path=/boot install

# Download the targeted kernel version sources and compile it
cd /usr/src && mkdir linux && cd linux
curl -O https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-${LINUX_VERSION}.tar.xz
tar xJvf linux-${LINUX_VERSION}.tar.xz
rm linux-${LINUX_VERSION}.tar.xz
cd linux-${LINUX_VERSION}

# Download the kernel configuration from the Arch Linux repository
# curl -O .config https://gitlab.archlinux.org/archlinux/packaging/packages/linux/-/blob/main/config
eclectic installkernel set -2
make defconfig # Alternatively, nconfig
make -j$(nproc) && make modules_install && make install

####################
# Old grub2 method #
####################

# Add grub2 with efi support, change CPU cores used by paludis
#echo 'sys-boot/grub efi' >> $PALUDIS_CONF
#cave resolve 'sys-boot/grub::arbor' -zx1 --skip-phase test

# Configure grub2 and generate the config file
#cd/
#grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=exherbo
#grub-mkconfig -o /boot/grub/grub.cfg

# Show reboot instructions
echo "You can now reboot your system. Do not forget to umount the partitions and remove the installation media."
echo "cd / && umount -R /mnt/exherbo"
echo "umount -l /mnt/exherbo"
echo "reboot"

# Exit the chrooted environment
# It's the end my friend
exit