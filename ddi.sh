#!/bin/bash

echo -n "Enter the username for which you'd like to make the setup: "
read USERNAME

if [ -z $USERNAME ]; then
    echo "Username is empty. Aborting..."
    exit;
fi

USER_EXISTS=$(grep -i $USERNAME /etc/shadow)
if [ -z $USER_EXISTS ]; then
    echo "User $USERNAME does not exist. Aborting..."
    exit;
fi

function install_program() {
    echo -ne "Installing '$1'"
    OUTPUT=`apt install -y $1 2>&1`

    if [[ $? != 0 ]]; then
        echo "$OUTPUT"
        echo "Exiting..."
        exit;
    fi
    echo " - complete"
}

function add_user_to_sudoers() {
    USER_EXISTS_IN_SUDOERS=$(grep -i $USERNAME /etc/sudoers)
    if [[ -z "$USER_EXISTS_IN_SUDOERS" ]]; then
        echo "Adding '$USERNAME' to sudoers"
        echo "$USERNAME ALL=(ALL:ALL) NOPASSWD:ALL" >> /etc/sudoers
        return 0
    fi
    echo "User '$USERNAME' already exists in sudoers"
}

function add_contrib_and_non_free() {
    HAS_CONTRIB_AND_NON_FREE=$(grep -i "contrib non-free" /etc/apt/sources.list)
    if [[ -z "$HAS_CONTRIB_AND_NON_FREE" ]]; then
        echo -ne "Adding contrib and non-free to sources list and updating..."
        sed -i 's/deb.*/& contrib non-free/g' /etc/apt/sources.list
        apt update
    fi
}

function enable_firewall() {
    echo "Enabling the firewall"
    su - $USERNAME -c "sudo ufw enable"
    su - $USERNAME -c "sudo ufw status verbose"
}

function install_microcode() {
    IS_INTEL=$(cat /proc/cpuinfo | grep -i 'model name' | uniq | grep -i intel)
    if [[ -z "$IS_INTEL" ]]; then
        install_program amd64-microcode
    else
        install_program intel-microcode
    fi
}

function install_docker() {
    HAS_DOCKER=$(which docker)
    if [[ -z "$HAS_DOCKER" ]]; then
        echo "Installing docker"
        apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release;
        curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg;
        echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null;
        apt update;
        apt install -y docker-ce docker-ce-cli containerd.io;
        /usr/sbin/usermod -aG docker $USERNAME;
    fi
}

function cleanup() {
    echo "Cleanup..."
    apt purge -y bluetooth bluez vim-tiny vim-common;
    apt clean && apt autoclean && apt autoremove
}

function install_spotify() {
    SPOTIFY_PATH=$(which spotify)
    if [[ -z "$SPOTIFY_PATH" ]]; then
        echo "Installing spotify"
        curl -sS https://download.spotify.com/debian/pubkey_0D811D58.gpg | apt-key add - ;
        echo "deb http://repository.spotify.com stable non-free" | tee /etc/apt/sources.list.d/spotify.list;
        apt-get update && apt-get install -y spotify-client
    fi
}

function install_neovim() {
    NVIM_PATH=$(which nvim)
    if [[ -z "$NVIM_PATH" ]]; then
        wget https://github.com/neovim/neovim/releases/download/v0.5.0/nvim.appimage;
        mv nvim.appimage nvim;
        chmod +x nvim;
        mkdir -p /home/$USERNAME/.local/bin;
        mv nvim /home/$USERNAME/.local/bin/;
        chown -R $USERNAME:$USERNAME /home/$USERNAME/.local;
        python3 -m pip install --user --upgrade pynvim;
    fi
}

function detect_sensors() {
    yes "" | sensors-detect
}

function add_xinitrc() {
    echo "Adding .xinitrc";
    echo "exec dwm" >> /home/$USERNAME/.xinitrc;
    chown -R $USERNAME:$USERNAME /home/$USERNAME/.xinitrc;
}

function add_user_dirs() {
    USER_DIRS=('Documents' 'Downloads' 'Projects' 'Pictures' '.config')
    for i in "${USER_DIRS[@]}"; do
        if [ ! -d "/home/$USERNAME/$i" ]; then
            mkdir "/home/$USERNAME/$i";
            chown -R $USERNAME:$USERNAME /home/$USERNAME/$i;
        fi
    done
}

function add_config_files() {
    cd /home/$USERNAME/Projects;
    git clone https://github.com/haralambov/dotfiles.git;
    chown -R $USERNAME:$USERNAME /home/$USERNAME/Projects/dotfiles;
    cd /home/$USERNAME/Projects/dotfiles;
    su - $USERNAME -c "cd /home/$USERNAME/Projects/dotfiles && bash /home/$USERNAME/Projects/dotfiles/dotfile_mapper.sh"
}

function build_suckless_tools() {
    REPO_NAMES=("dwm" "dmenu" "st" "slock" "dwmblocks")
    for REPO in "${REPO_NAMES[@]}"; do
        build $REPO
    done
}

function build() {
    cd /home/$USERNAME/Projects;
    git clone https://github.com/haralambov/"$1".git;
    cd $1;
    make clean install;
    sleep 10;
}

function install_programs() {
    PROGRAMS=(
        "sudo" "xorg" "gcc" "make" "libx11-dev" "libxinerama-dev" 
        "libxft-dev" "libxrandr-dev" "git" "feh" "ripgrep"
        "screenfetch" "htop" "curl" "tlp" "ufw" "lm-sensors"
        "redshift" "unzip" "arandr" "mlocate" "firefox-esr"
        "keepassxc" "tree" "mpv" "xautolock" "nodejs" "npm"
        "python3-pip" "libreoffice" "python3-pip" "fuse"
        "psmisc"
    )

    for PROGRAM in "${PROGRAMS[@]}"; do
        install_program $PROGRAM
    done
}

install_programs

add_user_to_sudoers
detect_sensors
add_contrib_and_non_free
enable_firewall

install_microcode
install_program firmware-iwlwifi

install_docker
install_program qbittorrent

install_spotify
install_neovim

add_xinitrc
add_user_dirs

add_config_files

build_suckless_tools

cleanup
