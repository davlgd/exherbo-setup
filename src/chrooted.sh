#!/bin/bash

# Script to setup Exherbo once chrooted in the configured stage3 tarball

CPU_CORES=$(nproc)
PALUDIS_CONF="/etc/paludis/options.conf"
KERNEL_BASE_URL="https://cdn.kernel.org/pub/linux/kernel/v"
SYSTEM_TYPE=$1
DISK=$2

# Configure the DNS resolvers
echo 'nameserver 1.1.1.1
nameserver 9.9.9.9' > /etc/resolv.conf

ask_config() {
    read -rp $'Enter the GNU/Linux kernel version (default: 6.6.30): ' KERNEL_VERSION_INPUT
    KERNEL_VERSION=${KERNEL_VERSION_INPUT:-6.6.30}
    get_kernel_url

    if [ $SYSTEM_TYPE == "UEFI" ]; then
        read -p $'What boot loader do you want to use?\n(g) grub\n(s) systemd-boot\nEnter your choice: ' bootloader_choice
        case "$bootloader_choice" in
            g) LOADER="grub" ;;
            s) LOADER="systemd-boot" ;;
            *) LOADER="systemd-boot" ;;
        esac
    else
        LOADER="grub"
    fi

    read -p $'Enter the hostname (default: exherbo): ' HOSTNAME_INPUT
    HOSTNAME=${HOSTNAME_INPUT:-exherbo}

    read -p 'Enter your country code (e.g., fr for France): ' COUNTRY_CODE

    case $COUNTRY_CODE in
        "fr-bepo")
            LANG="fr_FR.UTF-8"
            KEYMAP="fr-bepo"
            ;;
        [a-zA-Z][a-zA-Z])
            country_lower=${COUNTRY_CODE,,}
            LANG="${country_lower}_${country_lower^^}.UTF-8"
            KEYMAP="$country_lower"
            ;;
        *)
            LANG="en_US.UTF-8"
            KEYMAP="us"
            echo "Using en_US.UTF-8 and us keymap by default."
            ;;
    esac

    read -p $'Enter the username (default: davlgd): ' USER_INPUT
    USER=${USER_INPUT:-davlgd}
}

configure_os() {
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

    # Defines a new sudo user and set its password
    useradd -m -G wheel -s /bin/bash ${USER} > /dev/null 2>&1
    echo "${USER} ALL=(ALL) ALL" > /etc/sudoers.d/${USER}
    chmod 440 /etc/sudoers.d/${USER}
    echo
    echo "Account created for ${USER}, please define its password:"
    passwd ${USER}

    # Set the login message
    echo '
    ███████╗██╗  ██╗██╗  ██╗███████╗██████╗ ██████╗  ██████╗
    ██╔════╝╚██╗██╔╝██║  ██║██╔════╝██╔══██╗██╔══██╗██╔═══██╗
    █████╗   ╚███╔╝ ███████║█████╗  ██████╔╝██████╔╝██║   ██║
    ██╔══╝   ██╔██╗ ██╔══██║██╔══╝  ██╔══██╗██╔══██╗██║   ██║
    ███████╗██╔╝ ██╗██║  ██║███████╗██║  ██║██████╔╝╚██████╔╝
    ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚═════╝  ╚═════╝


    \S{ANSI_COLOR}\S{PRETTY_NAME}\e[0m - \n.\O, \s \r, \m
    Logged Users: \U
    \d, \t
    ' > /etc/issue
}

configure_packages_manager() {
    sed -i "s/jobs=2/jobs=$CPU_CORES/g" $PALUDIS_CONF

    cave sync
    cave resolve -x repository/marv
    cave resolve -x repository/hardware
    cave resolve -x --skip-phase linux-firmware nano neofetch
}

setup_bootloader() {
    if [ $SYSTEM_TYPE == "UEFI" ]; then
        echo "sys-boot/efibootmgr" >> $PALUDIS_CONF
        cave resolve -x --skip-phase test sys-boot/efibootmgr
        mount -t efivarfs efivarfs /sys/firmware/efi/efivars
    fi

    if [ $LOADER == "systemd-boot" ]; then
        echo "sys-apps/systemd cryptsetup efi" >> /etc/paludis/options.conf
        echo "sys-apps/coreutils xattr " >> /etc/paludis/options.conf
        cave resolve -x --skip-phase test sys-apps/systemd
        cave resolve -x --skip-phase test dracut

        echo "compress=\"xz\"" > /etc/dracut.conf.d/compress.conf
        echo "force=\"yes\"" > /etc/dracut.conf.d/force.conf
        echo "hostonly=\"yes\"" > /etc/dracut.conf.d/hostonly.conf
        echo "hostonly_mode=\"strict\"" >> /etc/dracut.conf.d/hostonly.conf
        echo "dracutmodules=\"base bash dracut-systemd fs-lib i18n kernel-modules rootfs-block systemd systemd-initrd terminfo udev-rules usrmount\"" > /etc/dracut.conf.d/modules.conf

        bootctl --make-machine-id-directory=yes --esp-path=/efi --boot-path=/boot install
        eclectic installkernel set -2
    else
        GRUB_TIMEOUT=0

        if [ $SYSTEM_TYPE == "UEFI" ]; then
            echo 'sys-boot/grub efi' >> $PALUDIS_CONF
            cave resolve 'sys-boot/grub::arbor' -zx1 --skip-phase test

            echo "set timeout=${GRUB_TIMEOUT}" >> /etc/grub.d/40_custom
            grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=exherbo
        fi

    fi
}

get_kernel_url(){
    if [[ "$KERNEL_VERSION" =~ ^[0-5]\..* ]]; then
        echo "Kernel version ${KERNEL_VERSION} is too old. Using default value."
        KERNEL_VERSION=6.6.30
    fi

    KERNEL_MAJOR_VERSION=${KERNEL_VERSION:0:1}
    KERNEL_URL="${KERNEL_BASE_URL}${KERNEL_MAJOR_VERSION}.x/linux-${KERNEL_VERSION}.tar.xz"

    if curl --output /dev/null --silent --head --fail "$KERNEL_URL"; then
        echo "Kernel version ${KERNEL_VERSION} found."
    else
        echo "Kernel version ${KERNEL_VERSION} not found. Using default value."
        KERNEL_VERSION=6.6.30
        KERNEL_MAJOR_VERSION=${KERNEL_VERSION:0:1}
        KERNEL_URL="${KERNEL_BASE_URL}${KERNEL_MAJOR_VERSION}.x/linux-${KERNEL_VERSION}.tar.xz"
    fi

    KERNEL_URL="${KERNEL_BASE_URL}${KERNEL_MAJOR_VERSION}.x/linux-${KERNEL_VERSION}.tar.xz"
}

get_kernel() {
    cd /usr/src && mkdir linux && cd linux
    curl -O $KERNEL_URL
    tar xJvf linux-${KERNEL_VERSION}.tar.xz
    rm linux-${KERNEL_VERSION}.tar.xz
    cd linux-${KERNEL_VERSION}
}

compile_kernel() {

    make defconfig
    scripts/config --enable CONFIG_FB_SIMPLE
    scripts/config --enable CONFIG_X86_SYSFB

    make -j$(nproc) && make modules_install && make install
    if [ $LOADER == "grub" ]; then
        grub-install ${DISK}
        grub-mkconfig -o /boot/grub/grub.cfg
    fi
}

enable_services() {
    systemctl enable sshd
    systemctl enable dhcpcd
    systemctl enable getty@ # Enable TTY login at boot
}

ask_config
configure_os

echo
echo -n "Configuring the package manager and compiling some tools, it will take a while..."
configure_packages_manager > /dev/null 2>&1
echo -ne "\r\033[K"
echo -e " - Configuring the package manager and compiling some tools: \e[92m\u2713\e[0m"

echo -n "Compiling and setting up the bootloader..."
setup_bootloader > /dev/null 2>&1
get_kernel > /dev/null 2>&1
echo -ne "\r\033[K"
echo -e " - Compiling and setting up the bootloader: \e[92m\u2713\e[0m"

echo -n "Compiling the kernel..."
compile_kernel
echo -ne "\r\033[K"
echo -e " - Compiling the kernel: \e[92m\u2713\e[0m"

echo
echo "Enabling services:"
enable_services

echo
echo "Rebooting in 5 secondes..."
sleep 5

exit
