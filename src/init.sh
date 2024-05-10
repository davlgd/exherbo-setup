#!/bin/bash

# Script to init the disk, download and extract the stage3 tarball, starts configuring the system

STAGE_URL="https://stages.exherbolinux.org/x86_64-pc-linux-gnu"
STAGE_FILE="exherbo-x86_64-pc-linux-gnu-gcc-current.tar.xz"
SCRIPT_DIR=$PWD

echo

if [ -f "params" ]; then
    source params
    echo "The 'params' file has been found and loaded"
else

    echo "There is no 'params' file, default parameters will be used"

fi

echo
# Set the target device, show usage if more than one argument or --help is given
if [ -z "${DISK}" ]; then
    DISK="/dev/sda"
fi

if [ $# -gt 1 ] || [[ $1 == "--help" ]]; then
echo "Exherbo Setup - Exherbo Linux Installation Script"
echo "Usage:"
echo "  ./init.sh <device>    - Installs Exherbo Linux on the specified device"
echo "  ./init.sh             - Installs Exherbo Linux on /dev/sda by default"
echo ""
echo "Options:"
echo "  <device>    - The target device for Exherbo Linux installation"
echo "                Example: ./init.sh /dev/nvme0n1"
echo ""
echo "Description:"
echo "  Exherbo Setup is a simple script to automate the installation of Exherbo Linux."
echo "  It can be run with a specific target device or without any arguments,"
echo "  in which case it will use /dev/sda as the default installation target."
echo "  The script will automaticaly detect if you're using a BIOS or EFI based system."
echo ""
echo "  You can set some parameters through the 'params' file."
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

if [ ! -b "${DISK}" ]; then
    echo "Invalid device: ${DISK}"
    exit 1
fi

bios_or_uefi() {
    if [ -d /sys/firmware/efi ]; then
        SYSTEM_TYPE="UEFI"
        echo "UEFI system detected"
    else
        SYSTEM_TYPE="BIOS"
        echo "BIOS system detected"
    fi
}

wipe_disk() {
    read -rp $"You're about to wipe ${DISK}. Do you want to continue? [y/n] "
    if [[ ! "${REPLY}" =~ ^[Yy]$ ]]; then
        echo
        exit 1
    fi

    wipefs -a "${DISK}"
}

ask_swap() {
    if [ -z "${SWAP_SIZE}" ]; then
        read -rp $"Do you want to create a swap partition? [y/n] "
        if [[ "${REPLY}" =~ ^[Yy]$ ]]; then
            echo -n "Enter the size of the swap partition (in GB): "
            read -r SWAP_SIZE
        fi
    fi

    if [ -n "${SWAP_SIZE}" ]; then
        if ! [[ "${SWAP_SIZE}" =~ ^[0-9]+$ ]] || [ "${SWAP_SIZE}" -lt 1 ] || [ "${SWAP_SIZE}" -gt 32 ]
        then
            echo "Invalid swap size: ${SWAP_SIZE}"
            exit 1
        fi
    fi
}

format_disk() {
    echo
    echo -e " - Disk wiped: \e[92m\u2713\e[0m"
    echo

    echo "Exherbo Linux will be installed on ${DISK}"
    echo
    echo "You need to create at least 2 partitions:"
    echo " - /     : Linux Filesystem"
    echo " - /boot : Linux Extended Boot"
    echo " - /efi  : EFI System (only for UEFI)"
    echo
    case ${SYSTEM_TYPE} in
    "UEFI")
        echo "cfdsik will be launched to allow configuration of disk partitions..."
        echo -n "IMPORTANT: SELECT 'Linux Extended Boot' TYPE FOR BOOT PARTITION AND WRITE!"
        echo
        echo && read -n 1 -s -r -p "Press any key to continue..."

        echo "label: gpt"   | sfdisk -W always ${DISK} > /dev/null 2>&1
        echo ", 512M, U"    | sfdisk -W always -a ${DISK} > /dev/null 2>&1
        echo ", 512M, L"    | sfdisk -W always -a ${DISK} > /dev/null 2>&1
        if [ "${SWAP_SIZE}" ]; then
            echo ", ${SWAP_SIZE}G, L" | sfdisk -W always -a ${DISK} > /dev/null 2>&1
        fi
        echo ","            | sfdisk -W always -a ${DISK} > /dev/null 2>&1
        cfdisk ${DISK}
        ;;
    "BIOS")
        echo ", 512M, U"    | sfdisk -W always ${DISK} > /dev/null 2>&1
        if [ "${SWAP_SIZE}" ]; then
            echo ", ${SWAP_SIZE}G, L" | sfdisk -W always -a ${DISK} > /dev/null 2>&1
        fi
        echo ","            | sfdisk -W always -a ${DISK} > /dev/null 2>&1
        ;;
    esac

}

get_disk_partitions() {
    case ${SYSTEM_TYPE} in
    "UEFI")
        if [[ "${DISK}" == /dev/sd* ]]; then
            PART_EFI="${DISK}1"
            PART_BOOT="${DISK}2"
            if [ "${SWAP_SIZE}" ]; then
                PART_SWAP="${DISK}3"
                PART_ROOT="${DISK}4"
            else
                PART_ROOT="${DISK}3"
            fi
        elif [[ "${DISK}" == /dev/nvme* ]]; then
            PART_EFI="${DISK}p1"
            PART_BOOT="${DISK}p2"
            if [ "${SWAP_SIZE}" ]; then
                PART_SWAP="${DISK}p3"
                PART_ROOT="${DISK}p4"
            else
                PART_ROOT="${DISK}p3"
            fi
        else
            echo "Storage device not recognized"
            exit 1
        fi
        ;;
    "BIOS")
        if [[ "${DISK}" == /dev/sd* ]]; then
            PART_BOOT="${DISK}1"
            if [ "${SWAP_SIZE}" ]; then
                PART_SWAP="${DISK}2"
                PART_ROOT="${DISK}3"
            else
                PART_ROOT="${DISK}2"
            fi
        elif [[ "${DISK}" == /dev/nvme* ]]; then
            PART_BOOT="${DISK}p1"
            if [ "${SWAP_SIZE}" ]; then
                PART_SWAP="${DISK}p2"
                PART_ROOT="${DISK}p3"
            else
                PART_ROOT="${DISK}p2"
            fi
        else
            echo "Storage device not recognized"
            exit 1
        fi
        ;;
    esac
}

create_partitions() {
    # Create the filesystems
    # - FAT32 for the Boot & EFI partition
    # - ext4 for the root partition
    # - Label the partitions
    case ${SYSTEM_TYPE} in
        "UEFI")
            mkfs.fat -F 32 "${PART_EFI}" -n EFI
            fatlabel "${PART_EFI}" EFI
            mkfs.fat -F 32 "${PART_BOOT}" -n BOOT
            e2label "${PART_BOOT}" BOOT
            ;;
        "BIOS")
            mkfs.ext2 "${PART_BOOT}" -L BIOS
            e2label "${PART_BOOT}" BIOS
            ;;
    esac

    mkfs.ext4 "${PART_ROOT}" -L EXHERBO
    e2label "${PART_ROOT}" EXHERBO

    if [ "${SWAP_SIZE}" ]; then
        mkswap "${PART_SWAP}" -L SWAP
    fi
}

mount_stage() {
    # Create the mountpoint and mount the root partition
    mkdir -p /mnt/exherbo/
    mount "${PART_ROOT}" /mnt/exherbo
    cd /mnt/exherbo

    # Download and extract the stage3 tarball
    curl -Os "${STAGE_URL}/${STAGE_FILE}"

    # Download and verify the checksum
    # For now it leads to an error: the filename is not good in the checksum file
    curl -Os "${STAGE_URL}/${STAGE_FILE}.sha256sum"
    diff -q "${STAGE_FILE}.sha256sum" <(sha256sum ${STAGE_FILE}) > /dev/null && echo "The file and the sha256 sum match" || echo "The file and the sha256 sum do not match"

    # Extract the tarball and remove it
    tar xJpf "${STAGE_FILE}"
    rm "${STAGE_FILE}*"
}

prepare_chroot() {
    # Define the partition to be mounted at boot
    case ${SYSTEM_TYPE} in
        "UEFI")
            cat <<EOF > /mnt/exherbo/etc/fstab
# <fs>          <mountpoint>    <type> <opts>           <dump/pass>
${PART_ROOT}    /               ext4   defaults,noatime 0 1
${PART_BOOT}    /boot           vfat   defaults         0 0
${PART_EFI}     /efi            vfat   umask=0077       0 0
EOF
            ;;
        "BIOS")
            cat <<EOF > /mnt/exherbo/etc/fstab
# <fs>          <mountpoint>    <type> <opts>           <dump/pass>
${PART_ROOT}    /               ext4   defaults,noatime 0 1
${PART_BOOT}    /boot           ext2   defaults         0 0
EOF
            ;;
    esac

    if [ "${SWAP_SIZE}" ]; then
        echo "${PART_SWAP}    none            swap    sw              0 0" >> /mnt/exherbo/etc/fstab
    fi

    # Mount the system directories
    mount -o rbind /dev /mnt/exherbo/dev
    mount -o bind /sys /mnt/exherbo/sys
    mount -t proc none /mnt/exherbo/proc

    # Mount the boot/efi partition
    mkdir -p /mnt/exherbo/boot
    mount "${PART_BOOT}" /mnt/exherbo/boot

    if [ ${SYSTEM_TYPE} == "UEFI" ]; then
        mount -o x-mount.mkdir "${PART_EFI}" /mnt/exherbo/efi
    fi
}

clear
bios_or_uefi
ask_swap
wipe_disk > /dev/null
format_disk
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

echo -n "Partitions creation & formating..."
create_partitions > /dev/null  2>&1
echo -ne "\r\033[K"
echo -e " - Disk wiped & new partition created: \e[92m\u2713\e[0m"

echo -n "Downloading Exherbo Linux stage3 tarball..."
mount_stage > /dev/null 2>&1
echo -ne "\r\033[K"
echo -e " - Exherbo Linux downloaded & setup: \e[92m\u2713\e[0m"

echo -n "Preparing chroot..."
prepare_chroot > /dev/null 2>&1
echo -ne "\r\033[K"
echo -e " - Chroot prepared: \e[92m\u2713\e[0m"
echo

# Let's chroot!
cp "${SCRIPT_DIR}"/chrooted.sh /mnt/exherbo
if [ -f "${SCRIPT_DIR}"/params ]; then
    cp "${SCRIPT_DIR}"/params /mnt/exherbo
fi
env -i TERM="${TERM}" SHELL=/bin/bash HOME="${HOME}" "$(which chroot)" /mnt/exherbo /bin/bash chrooted.sh "${SYSTEM_TYPE}" "${DISK}"

# It's the end my friend
rm /mnt/exherbo/chrooted.sh
rm -f /mnt/exherbo/params
cd / && umount -R /mnt/exherbo
umount -l /mnt/exherbo
reboot
