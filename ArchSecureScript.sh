#!/usr/bin/env bash
# ArchSecure. Copyright (c) 2014, by Nicolas Briand & Anthony Thuilliez        #
################################################################################

# set -o xtrace #Enable it to trace what gets executed. Useful for developpement

echo "╔═╗┬─┐┌─┐┬ ┬╔═╗┌─┐┌─┐┬ ┬┬─┐┌─┐"
echo "╠═╣├┬┘│  ├─┤╚═╗├┤ │  │ │├┬┘├┤ "
echo "╩ ╩┴└─└─┘┴ ┴╚═╝└─┘└─┘└─┘┴└─└─┘"

__editor="Nicolas Briand & Anthony Thuilliez"
__version="1.0.0"

# Set magic variables for current file & dir
__dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
__root="$(cd "$(dirname "${__dir}")" && pwd)"
__file="${__dir}/$(basename "${BASH_SOURCE[0]}")"
__base="$(basename ${__file} .sh)"

echo "ArchSecureScript (ASS) installer. by ${__editor} version ${__version}."
echo ""

# ### Debugging stuff begin here ### #
set -o errexit #script exit if failure occure #We call allow failure by adding || true after commands
function _fmt (){
  #Initialize color variables
  local color_ok="\x1b[32m"
  local color_bad="\x1b[31m"
  local color_reset="\x1b[0m"

  #color_bad (red) is the default color.
  local color="${color_bad}"
  #Debug, info and notice will be in green
  if [ "${1}" = "debug" ] || [ "${1}" = "info" ] || [ "${1}" = "notice" ]; then
    color="${color_ok}"
  fi

  echo -e "${color}$(printf "[%9s]" ${1})${color_reset}";
}

#Exemple : emergency is a function. This function call the logger command.
#This command will have __base (__base return the script's name) as prefix.
#The option -s will output the message to STDERR and the syslog
#Then, the function will echo "emergency" in red color define in _fmt function
#Followed by each arguments you type.
#So, emergency "foobar" will return :
#[time information] [ emergency] foobar <-- each words you type
#       ^               ^
#       |               |
#  logger function   _fmt function
#Then we redirectect stdout(1) to stderr(2)
#Or if the function file, we return true ( || true)
#For the emergency case, we exit the script with error code 1
function emergency () { logger -s -t ${__base} $(echo "$(_fmt emergency) ${@}") 1>&2 || true; exit 1; }
function alert ()     { logger -s -t ${__base} $(echo "$(_fmt alert) ${@}") >&2 || true; }
function critical ()  { logger -s -t ${__base} $(echo "$(_fmt critical) ${@}") 1>&2 || true; }
function error ()     { logger -s -t ${__base} $(echo "$(_fmt error) ${@}") 1>&2 || true; }
function warning ()   { logger -s -t ${__base} $(echo "$(_fmt warning) ${@}") 1>&2 || true; }
function notice ()    { logger -s -t ${__base} $(echo "$(_fmt notice) ${@}") 1>&2 || true; }
function info ()      { logger -s -t ${__base} $(echo "$(_fmt info) ${@}") || true; }
function debug ()     { logger -s -t ${__base} $(echo "$(_fmt debug) ${@}") 1>&2 || true; }

# ### End of debugging stuff ### #

function setup(){
  info "Installation launched !"

  parted -l #List partition to help user to choose
  notice "You can see your hard drives and partitions above"
  read -p "Select disk where install Archlinux : " -i "/dev/sd" -e DISK # -i "/dev/sd" allow autocompletion with tabulation
  read -p "Type a username for basic user : " -e USERNAME
  read -p "Type a hostname for computers name : " -e NEW_HOSTNAME
  read -p "Type a password for encryption : " -e PASSWORD
  read -p "Which environment do you want : [kde,gnome,lxde] " -e GRAPH_ENV

  while [[ -z ${YN} ]]; do
    read -p "Install on virtualbox ? [Y/N] " response
    case $response in
        [yY][eE][sS][oO]|[yY])
          local YN=true
          VIRTUALBOX=true
            ;;
        [nN])
          local YN=true
          VIRTUALBOX=false
          info "Okay right"
          ;;
        *)
          echo "Mmmmh... don't understand, only Y or N are authorized. And I'm sure you can do it."
            ;;
    esac
  done
  unset YN
  unset response


  #Print informations and ask for confirmation
  info "Disk: ${DISK}"
  info "Username: ${USERNAME}"
  info "Hostname: ${NEW_HOSTNAME}"
  info "Password: ${PASSWORD}"
  info "VIRTUALBOX: ${VIRTUALBOX}"
  info "Graphic environment: ${GRAPH_ENV}"
  if [[ -e ${DISK} ]]; then #Test if the choosen disk exist
    while [ -z ${YN} ]
    do
      read -p "$(warning Are you okay with this? It will erase EVERYTHING in this disk and you will not be able to change the password. [y/N]) " response
      case $response in
          [yY][eE][sS][oO]|[yY])
            local YN=true
            
            info "Disk is formatting..."
            format_disk
            info "Disk formatted sucessful"

            info "Creating partition"
            create_partitions
            info "Partition created sucessful"

            info "Preparing disk"
            prepare_disk
            info "Disk prepared sucessful"

            info "Preparing LVM"
            prepare_lvm
            info "LVM prepared"

            info "Mounting FileSystem"
            mount_fs
            info "FileSystem mounted sucessful"

            info "Preparing boot"
            prepare_boot
            info "Boot prepared sucessful"

            info "Installing base"
            install_base
            info "Base installed sucessful"

            info "Generate fstab"
            generate_fstab
            info "fstab generated sucessful"

            info 'Chrooting into installed system to continue setup...'
            prepare_chroot
              ;;
          [nN])
            local YN=true
            info "Okay... Good Bye motherfucker !"
            exit 0
            ;;
          *)
            echo "Mmmmh... don't understand, only Y or N are authorized. And I'm sure you can do it. "
              ;;
      esac
    done
  else
    echo "Selected disk does not exist"
  fi
}

#Partitions creating functions
function format_disk(){
  #This function format the disk with best practices
  #It takes a long time, so you can disable it for time saving
  echo "Format disk desactivate, not good !"

  #Uncomment line below to enable formatting
  # cryptsetup open --type plain ${DISK} container --key-file /dev/random
  # dd if=/dev/zero of=/dev/mapper/container status=progress
}
function create_partitions(){
  #It makes 3 partitions :
  #bios_grub of 1024Kb for grub on GPT table (Without this partitions, the bootloader will not work)
  #boot of 400Mb for /boot
  #home of 100% free for /home
  # +-----------------------------------------------------------------------+ +----------------+
  # | Logical volume1       | Logical volume2       | Logical volume3       | |                |
  # |/dev/storage/swapvol   |/dev/storage/rootvol   |/dev/storage/homevol   | | Boot partition |
  # |_ _ _ _ _ _ _ _ _ _ _ _|_ _ _ _ _ _ _ _ _ _ _ _|_ _ _ _ _ _ _ _ _ _ _ _| | (may be on     |
  # |                                                                       | | other device)  |
  # |                        LUKS encrypted partition                       | |                |
  # |                          /dev/sdaX                                    | | /dev/sdbY      |
  # +-----------------------------------------------------------------------+ +----------------+
  parted -s ${DISK}\
  mklabel gpt \
  mkpart primary ext4 1MB 2MB \
  mkpart primary ext4 2MB 402MB \
  mkpart primary ext4 402MB 100% \
  set 1 bios_grub on \
  set 3 lvm on \
  name 1 bios_grub \
  name 2 boot \
  name 3 root_lvm || emergency "Something went wrong with partitioning. You can investigate. Exit 1. "
}

function prepare_disk(){
  echo "${PASSWORD}" | cryptsetup -v --cipher aes-xts-plain64 luksFormat ${DISK}3 #It encrypt the LVM using LUKS format with cipher aes-xts-plain64
  echo "${PASSWORD}" | cryptsetup open --type luks ${DISK}3 lvm #It open the lvm, the decrypted container is now available at /dev/mapper/lvm.
}

function prepare_lvm(){
  pvcreate /dev/mapper/lvm #Create a physical volume on top of the opened LUKS container
  vgcreate storage /dev/mapper/lvm #Create the volume group named MyStorage, adding the previously created physical volume to it

  #Create all logical volumes on the volume group
  lvcreate -l 20%VG storage -n swapvol
  lvcreate -l 40%VG storage -n rootvol
  lvcreate -l +100%FREE storage -n homevol

  #Format filesystems on each logical volume
  mkfs.ext4 /dev/mapper/storage-rootvol
  mkfs.ext4 /dev/mapper/storage-homevol
  mkswap /dev/mapper/storage-swapvol
}

function mount_fs(){
  #Mount each filesystems
  mount /dev/storage/rootvol /mnt
  mkdir /mnt/home
  mount /dev/storage/homevol /mnt/home
  swapon /dev/storage/swapvol
}

function prepare_boot(){
  #Convert /boot to ext2 format which is the standard for boot partition
  mkfs.ext2 ${DISK}2
  mkdir /mnt/boot
  mount ${DISK}2 /mnt/boot
}

function install_base(){
  #Install the basic system (GNU)
  #You need to add base-devel for some stuff like Yaourt
  pacstrap /mnt base base-devel grub xdg-user-dirs git
}

function generate_fstab(){
  #It generate the fstab to be enable to boot
  genfstab -U -p /mnt >> /mnt/etc/fstab
}

function prepare_chroot(){
  #Chrooting in the new system
  info "Preparing chroot"
  cp $0 /mnt/ArchSecure.sh
  arch-chroot /mnt ./ArchSecure.sh --configure ${DISK} ${USERNAME} ${PASSWORD} ${NEW_HOSTNAME} ${VIRTUALBOX}
}

function configure(){
  #Here we are in chroot
  local DISK=$2
  local USERNAME=$3
  local PASSWORD=$4
  local NEW_HOSTNAME=$5
  local VIRTUALBOX=$6

  echo "Exporting timezone"
  LANG="fr_FR.UTF-8"
  export LANG=fr_FR.UTF-8
  KEYMAP=fr
  ln -s /usr/share/zoneinfo/Europe/Paris /etc/localtime

  echo "Prepare bootloader"
  local CRYPTDEVICE="$(blkid -s UUID -o value ${DISK}3)" #Get UUID of the encrypted device
  install_bootloader ${DISK} ${CRYPTDEVICE}

  echo "Create basic user"
  create_basic_user ${USERNAME} ${PASSWORD}

  echo "Change Hostname"
  change_hostname ${NEW_HOSTNAME}

  echo "Adding sudo to ${USERNAME}"
  install_sudo ${USERNAME} ${NEW_HOSTNAME}

  echo "Install network manager"
  install_network

  echo "Install yaourt"
  install_yaourt

  echo "Install xorg"
  install_xorg

  echo "Install Virtualbox graphics"
  install_graphic_drivers $VIRTUALBOX

  echo "Install lxde"
  install_lxde

  echo "Clean up installation"
  clean_desktop
}

function install_bootloader(){
  local DISK=$1
  local CRYPTDEVICE=$2

  #Enable lvm2-lvmetad which is a requierement to boot on encrypted lvm
  systemctl enable lvm2-lvmetad.service

  #Install grub on disk
  grub-install --target=i386-pc ${DISK}

  #Edit mkinitcpio configuration to add encrypt and lvm2 module to HOOKS
  sed -i 's|base udev|base udev encrypt lvm2|g' /etc/mkinitcpio.conf

  #Edit grub config to inform it where is the encrypted device and the root device
  sed -i "s|GRUB_CMDLINE_LINUX\=\"|GRUB_CMDLINE_LINUX\=\"cryptdevice=UUID=${CRYPTDEVICE}:storage root=/dev/mapper/storage-rootvol|g" /etc/default/grub

  #mkinitcpio will generate initramfs-linux.img and initramfs-linux-fallback.img to be able to boot
  mkinitcpio -p linux

  #Make the grub configuration
  grub-mkconfig -o /boot/grub/grub.cfg
}

function create_basic_user(){
  local USERNAME=$1
  local PASSWORD=$2
  useradd -g users -m -s /bin/bash ${USERNAME} #Add a basic user
  sleep 1
  echo -en "${PASSWORD}\n${PASSWORD}" | passwd "${USERNAME}" #Change the password of the user
  xdg-user-dirs-update #Create base folder like Document, Pictures, Desktop...etc
}

function change_hostname(){
  local NEW_HOSTNAME=$1;
  echo "${NEW_HOSTNAME}" > /etc/hostname #Set up the new hostname
  export HOSTNAME=${NEW_HOSTNAME} #Export the hostname for the current session.
}

function install_sudo(){
  local USERNAME=$1
  local NEW_HOSTNAME=$2
  pacman -S sudo --noconfirm

  #Add the current user to sudo. Now, the current user will be able to use sudo.
  # echo "${USERNAME}   ${NEW_HOSTNAME}=(ALL) ALL" >> /etc/sudoers
  echo "${USERNAME} ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
}

function install_network(){
  pacman -Syu networkmanager net-tools --noconfirm
  systemctl enable NetworkManager
}

function install_yaourt(){
  #Execute command below as user. Run makepkg as root is not allowed.
  su ${USERNAME} -c "git clone https://aur.archlinux.org/package-query.git /home/${USERNAME}/package-query"
  su ${USERNAME} -c "cd /home/${USERNAME}/package-query && makepkg -si --noconfirm"
  su ${USERNAME} -c "git clone https://aur.archlinux.org/yaourt.git /home/${USERNAME}/yaourt"
  su ${USERNAME} -c "cd /home/${USERNAME}/yaourt && makepkg -si --noconfirm"
}

function install_xorg(){
  pacman -Syu xorg-server xorg-xinit xorg-server-utils --noconfirm
}


function install_graphic_drivers(){
  if [[ ${VIRTUALBOX} == true ]]; then
    pacman -Syu virtualbox-guest-utils --noconfirm
  else
    pacman -Syu xf86-video-vesa --noconfirm
  fi
}

function install_lxde(){
  #Install the graphic environment
  pacman -S lxde lxdm --noconfirm
  systemctl enable lxdm
}

function clean_desktop(){
  echo "Deleting script"
  rm /$0
  echo "Archlinux installed sucessful, thanks to use this script ! :)"
}

function help(){
  echo "usage: $0 [COMMAND]"
  echo ""
  echo "Install a secure Archlinux."
  echo ""
  echo "Commands:"
  echo "-i / --install       Install a secure Archlinux"
  echo "-v /--version        Print version of ArchSecure"
  echo "-h /--help           Print this help"
  exit 0
}

#Arguments parsing
case "$1" in
    -i|--install) setup;;
    -v|--version) echo "ArchSecure version ${__version}" && exit 0;;
    -c|--configure) configure $1 $2 $3 $4 $5 $6;;
    -h|--help) help;;
     *) echo >&2 \
     "usage: $0 [--install]"
    exit 1;;
    *)  echo "usage: $0 [--install]";;	# terminate while loop
esac
shift

#Delete the script
function cleanup_before_exit () {
  umount -R /mnt || true
  info "Cleaning up. Done"
  # reboot
}
#It will be launch each time the script exit. For any reason.
#Now, we can handle what's appening when the script exiting
#For each EXIT status, it will launch the cleanup_before_exit function
trap cleanup_before_exit EXIT

exit 0
