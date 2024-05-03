#!/bin/bash

# Script to setup Exherbo once chrooted in the configured stage3 tarball

CPU_CORES=$(nproc)
DNS_SERVER_1="1.1.1.1"
DNS_SERVER_2="9.9.9.9"
GRUB_TIMEOUT=5
KERNEL_BASE_URL="https://cdn.kernel.org/pub/linux/kernel/v"
KERNEL_DEFAULT_VERSION="6.6.30"
PALUDIS_CONF="/etc/paludis/options.conf"
PALUDIS_WORLD="/var/db/paludis/repositories/installed/world"

SYSTEM_TYPE=$1
DISK=$2

# Configure the DNS resolvers
{
  echo "nameserver ${DNS_SERVER_1}"
  echo "nameserver ${DNS_SERVER_2}"
} > /etc/resolv.conf

ask_config() {
    read -rp $'Enter the Linux kernel version to use (default: '${KERNEL_DEFAULT_VERSION}'): ' KERNEL_VERSION_INPUT
    KERNEL_VERSION="${KERNEL_VERSION_INPUT:-${KERNEL_DEFAULT_VERSION}}"
    get_kernel_url

    echo
    if [ "${SYSTEM_TYPE}" == "UEFI" ]; then
        read -rp $'Enter the boot loader to use (default: systemd-boot):\n(g) grub\n(s) systemd-boot\nWhat is your choice? ' bootloader_choice
        case "${bootloader_choice}" in
            g) LOADER="grub" ;;
            *) LOADER="systemd-boot" ;;
        esac
    else
        LOADER="grub"
    fi

    echo
    read -rp $'Enter the hostname (default: exherbo): ' HOSTNAME_INPUT
    HOSTNAME="${HOSTNAME_INPUT:-exherbo}"

    read -rp 'Enter Country code (e.g.: fr-bepo, default: us): ' COUNTRY_CODE
    case "${COUNTRY_CODE}" in
        "fr-bepo")
            KEYMAP="fr-bepo"
            LANG="fr_FR.UTF-8"
            ;;
        [a-zA-Z][a-zA-Z])
            country_lower="${COUNTRY_CODE,,}"
            KEYMAP="$country_lower"
            LANG="${country_lower}_${country_lower^^}.UTF-8"
            ;;
        *)
            KEYMAP="us"
            LANG="en_US.UTF-8"
            echo "Using en_US.UTF-8 and us keymap by default."
            ;;
    esac

    read -rp $'Enter timezone (e.g.: Europe/Paris, default: UTC): ' TIMEZONE_INPUT
    TIMEZONE="${TIMEZONE_INPUT:-UTC}"

    read -rp $'Enter the username (default: davlgd): ' USER_INPUT
    USER="${USER_INPUT:-davlgd}"
}

configure_os() {
    # Set the timezone and locale
    ln -sf /usr/share/zoneinfo/"${TIMEZONE}" /etc/localtime
    localedef --inputfile "${country_lower}_${country_lower^^}" --charmap UTF-8 "${KEYMAP}"
    echo LANG="${LANG}" > /etc/env.d/99locale
    echo KEYMAP="${KEYMAP}" > /etc/vconsole.conf

    # Sync hardware clock with the current system time
    hwclock --systohc --utc

    # Set the PS1 variable to distinguish the chrooted environment
    source /etc/profile
    PS1="(Exherbo) $PS1"

    # Set the hostname
    echo "${HOSTNAME}" > /etc/hostname
    echo "127.0.0.1 ${HOSTNAME}.local ${HOSTNAME} localhost" > /etc/hosts
    echo "::1 ${HOSTNAME}.local ${HOSTNAME} localhost" >> /etc/hosts

    # Defines a new sudo user and set its password
    useradd -m -G adm,audio,cdrom,disk,usb,users,video,wheel -s /bin/bash "${USER}" > /dev/null 2>&1
    echo "${USER} ALL=(ALL) ALL" > /etc/sudoers.d/"${USER}"
    chmod 440 /etc/sudoers.d/"${USER}"
    echo
    echo "Account created for ${USER}, define its password:"
    passwd "${USER}"

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
    sed -i "s/jobs=2/jobs=${CPU_CORES}/g" ${PALUDIS_CONF}
    cave sync

    # Add some repositories
    cave resolve -x \
        repository/hardware \
        repository/marv \
        repository/tombriden

    # Set packages to install
    echo 'app-editors/nano
app-misc/fastfetch
firmware/linux-firmware' >> ${PALUDIS_WORLD}

    # Add options and packages depending on system and bootloader
    if [ "${LOADER}" == "systemd-boot" ]; then
        echo '*/* systemd
sys-apps/systemd efi
net-libs/nghttp2 utils
sys-apps/coreutils xattr' >> ${PALUDIS_CONF}
        echo 'sys-boot/dracut' >> ${PALUDIS_WORLD}
    fi

    if [ "${SYSTEM_TYPE}" == "UEFI" ]; then
        mount -t efivarfs efivarfs /sys/firmware/efi/efivars
        echo "sys-boot/efibootmgr" >> ${PALUDIS_WORLD}

        if [ "${LOADER}" == "grub" ]; then
            echo "sys-boot/grub efi" >> ${PALUDIS_CONF}
        fi
    fi
}

update_system() {
    # Update the system and install desired packages
    cave sync
    cave resolve world -zx --skip-phase test

    # Install bootloader package with EFI support (activated through options)
    if [ "${SYSTEM_TYPE}" == "UEFI" ]; then
        if  [ "${LOADER}" == "systemd-boot" ]; then
            cave resolve sys-apps/systemd -zx1 --skip-phase test
        else # grub
            cave resolve sys-boot/grub -zx1 --skip-phase test
        fi
    fi
}

get_kernel_url() {
    if [[ "${KERNEL_VERSION}" =~ ^[0-5]\..* ]]; then
        echo "Kernel ${KERNEL_VERSION} is too old, using default value (${KERNEL_DEFAULT_VERSION})."
        KERNEL_VERSION=${KERNEL_DEFAULT_VERSION}
    fi

    KERNEL_MAJOR_VERSION=${KERNEL_VERSION:0:1}
    KERNEL_URL="${KERNEL_BASE_URL}${KERNEL_MAJOR_VERSION}.x/linux-${KERNEL_VERSION}.tar.xz"

    if curl --output /dev/null --silent --head --fail "$KERNEL_URL"; then
        echo "Kernel ${KERNEL_VERSION} found"
    else
        echo "Kernel ${KERNEL_VERSION} not found, using default value (${KERNEL_DEFAULT_VERSION})."
        KERNEL_VERSION=${KERNEL_DEFAULT_VERSION}
        KERNEL_MAJOR_VERSION=${KERNEL_VERSION:0:1}
        KERNEL_URL="${KERNEL_BASE_URL}${KERNEL_MAJOR_VERSION}.x/linux-${KERNEL_VERSION}.tar.xz"
    fi

    KERNEL_URL="${KERNEL_BASE_URL}${KERNEL_MAJOR_VERSION}.x/linux-${KERNEL_VERSION}.tar.xz"
}

get_kernel() {
    cd /usr/src && mkdir linux && cd linux
    curl -O "${KERNEL_URL}"
    tar xJvf "linux-${KERNEL_VERSION}.tar.xz"
    rm "linux-${KERNEL_VERSION}.tar.xz"
    cd "linux-${KERNEL_VERSION}"
}

compile_kernel() {

    make defconfig

    scripts/config -e CONFIG_BOOT_VESA_SUPPORT
    scripts/config --set-val CONFIG_CONSOLE_LOGLEVEL_DEFAULT 3
    scripts/config -e CONFIG_DRM_FBDEV_EMULATION
    scripts/config --set-val CONFIG_DRM_FBDEV_OVERALLOC 100
    scripts/config -e CONFIG_DRM_SIMPLEDRM
    scripts/config -e CONFIG_FB
    scripts/config -e CONFIG_FB_CORE
    scripts/config -e CONFIG_FB_DEVICE
    scripts/config -e CONFIG_FRAMEBUFFER_CONSOLE
    scripts/config -e CONFIG_FRAMEBUFFER_CONSOLE_DETECT_PRIMARY
    scripts/config -e CONFIG_FRAMEBUFFER_CONSOLE_LEGACY_ACCELERATION
    scripts/config -d CONFIG_LOGO
    scripts/config -d CONFIG_FONTS

    if [ "${SYSTEM_TYPE}" == "UEFI" ]; then
        scripts/config -e CONFIG_EFI
        scripts/config -e CONFIG_EFI_STUB
        scripts/config -e CONFIG_EFI_PARTITION
        scripts/config -e CONFIG_FB_EFI
    fi

    echo
    read -rp $'Do you want to customize the kernel configuration? [y/n] '
    if [[ "${REPLY}" =~ ^[Yy]$ ]]; then
        make menuconfig
    fi

    make -j$(nproc)
    make modules_install
    make install
}

setup_bootloader() {
    if [ "${LOADER}" == "systemd-boot" ]; then
        echo 'compress="xz"' > /etc/dracut.conf.d/compress.conf
        echo 'force="yes"' > /etc/dracut.conf.d/force.conf
        echo 'hostonly="yes"' > /etc/dracut.conf.d/hostonly.conf
        echo 'hostonly_mode="strict"' >> /etc/dracut.conf.d/hostonly.conf
        echo 'dracutmodules="base bash dracut-systemd systemd systemd-initrd terminfo fs-lib i18n kernel-modules rootfs-block udev-rules usrmount"' > /etc/dracut.conf.d/modules.conf

        bootctl install
        kernel-install add "${KERNEL_VERSION}" /boot/vmlinuz-"${KERNEL_VERSION}"
    else # grub
        echo "set timeout=${GRUB_TIMEOUT}" >> /etc/grub.d/40_custom

        GRUB_INSTALL_PARAMS=()
        if [ "${SYSTEM_TYPE}" == "UEFI" ]; then
            GRUB_INSTALL_PARAMS=( --efi-directory=/efi --bootloader-id=exherbo )
        else # BIOS
            GRUB_INSTALL_PARAMS=( "${DISK}" )
        fi

        grub-install "${GRUB_INSTALL_PARAMS[@]}"
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
echo -n "Configuring Paludis and compiling some tools..."
configure_packages_manager > /dev/null 2>&1
echo -ne "\r\033[K"
echo -e " - Configure Paludis and compile some tools: \e[92m\u2713\e[0m"

echo "Updating system..."
update_system

echo "Downloading & compiling Kernel ${KERNEL_VERSION}..."
get_kernel > /dev/null 2>&1
compile_kernel

echo
echo -e " - Configure Paludis and compile some tools: \e[92m\u2713\e[0m"
echo -e " - Kernel ${KERNEL_VERSION} download and compilation: \e[92m\u2713\e[0m"
echo -n "Compiling and setting up bootloader..."
setup_bootloader > /dev/null 2>&1

echo -ne "\r\033[K"
echo -e " - Compilation and setup of ${LOADER}: \e[92m\u2713\e[0m"

echo
echo -n "Enabling services:"
enable_services

echo
echo "Rebooting in 5 seconds..."
sleep 5
