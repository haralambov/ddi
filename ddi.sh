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

export PATH="$PATH:/usr/sbin"

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

function install_nodejs() {
    mkdir -p /home/$USERNAME/node
    cd /home/$USERNAME/node

    wget https://nodejs.org/dist/v16.14.0/node-v16.14.0-linux-x64.tar.xz

    tar -xf node-v16.14.0-linux-x64.tar.xz
    cd node-v16.14.0-linux-x64
    mkdir /usr/local/bin/nodejs
    mv lib/ share/ include/ bin/ /usr/local/bin/nodejs

    ln -s /usr/local/bin/nodejs/bin/node /usr/local/bin/node
    ln -s /usr/local/bin/nodejs/bin/npm /usr/local/bin/npm
    ln -s /usr/local/bin/nodejs/bin/npx /usr/local/bin/npx
    ln -s /usr/local/bin/nodejs/bin/corepack /usr/local/bin/corepack

    rm -rf /home/$USERNAME/node
}

function install_bluetooth() {
    echo "Installing bluetooth"
    install_program bluetooth
    install_program blueman-applet
    install_program pulseaudio-utils
    install_program pulseaudio-module-bluetooth
    # enables the switch on connect module,
    # which automatically changes the default output device
    echo "load-module module-switch-on-connect" >> /etc/pulse/default.pa
    su - $USERNAME -c "sudo systemctl enable bluetooth"
}

function cleanup() {
    echo "Cleanup..."
    apt purge -y bluetooth bluez vim-tiny vim-common notification-daemon;
    apt clean && apt autoclean && apt autoremove
}

function install_spotify() {
    SPOTIFY_PATH=$(which spotify)
    if [[ -z "$SPOTIFY_PATH" ]]; then
        echo "Installing spotify"
        curl -sS https://download.spotify.com/debian/pubkey_5E3C45D7B312C643.gpg | sudo apt-key add -;
        echo "deb http://repository.spotify.com stable non-free" | tee /etc/apt/sources.list.d/spotify.list;
        apt-get update && apt-get install -y spotify-client
    fi
}

function install_neovim() {
    NVIM_PATH=$(which nvim)
    if [[ -z "$NVIM_PATH" ]]; then
        wget https://github.com/neovim/neovim/releases/download/v0.6.0/nvim.appimage;
        mv nvim.appimage nvim;
        chmod +x nvim;
        mkdir -p /home/$USERNAME/.local/bin;
        mv nvim /home/$USERNAME/.local/bin/;
        chown -R $USERNAME:$USERNAME /home/$USERNAME/.local;
        su - $USERNAME -c "pip3 install pynvim neovim";
        su - $USERNAME -c "sh -c 'curl -fLo \"${XDG_DATA_HOME:-/home/$USERNAME/.local/share}\"/nvim/site/autoload/plug.vim --create-dirs \
           https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim'";
    fi
}

function install_nerd_fonts() {
    FONTS_DIR="/home/$USERNAME/.local/share/fonts"
    if [ ! -d $FONTS_DIR ]; then
        mkdir -p $FONTS_DIR
    fi
    cd /home/$USERNAME/Downloads;
    wget https://github.com/ryanoasis/nerd-fonts/releases/download/v2.1.0/UbuntuMono.zip;
    unzip UbuntuMono.zip;
    mv *.ttf $FONTS_DIR
    rm UbuntuMono.zip
    chown -R $USERNAME:$USERNAME $FONTS_DIR
    su - $USERNAME -c "fc-cache -f -v"
}

function detect_sensors() {
    yes "" | sensors-detect
}

function add_xinitrc() {
    echo "Adding .xinitrc";
    echo "setxkbmap -option;setxkbmap -option \"altwin:swap_alt_win,caps:swapescape\"" >> /home/$USERNAME/.xinitrc
    echo "feh --bg-scale /home/$USERNAME/Projects/dotfiles/debian_wallpaper.png" >> /home/$USERNAME/.xinitrc;
    echo "redshift -P -O 3500" >> /home/$USERNAME/.xinitrc;
    echo "exec dwm" >> /home/$USERNAME/.xinitrc;
    chown -R $USERNAME:$USERNAME /home/$USERNAME/.xinitrc;
}

function add_user_dirs() {
    USER_DIRS=('Documents/notes' 'Downloads' 'Projects' 'Pictures/Screenshots' '.config' '.cache/clipmenu')
    for i in "${USER_DIRS[@]}"; do
        if [ ! -d "/home/$USERNAME/$i" ]; then
            mkdir -p "/home/$USERNAME/$i";
            chown -R $USERNAME:$USERNAME /home/$USERNAME/$i;
        fi
    done
}

function change_folder_permissions() {
    chown -R $USERNAME:$USERNAME /home/$USERNAME
}

function add_config_files() {
    cd /home/$USERNAME/Projects;
    git clone https://github.com/haralambov/dotfiles.git;
    chown -R $USERNAME:$USERNAME /home/$USERNAME/Projects/dotfiles;
    cd /home/$USERNAME/Projects/dotfiles;
    su - $USERNAME -c "cd /home/$USERNAME/Projects/dotfiles && bash /home/$USERNAME/Projects/dotfiles/dotfile_mapper.sh"
}

function build_suckless_tools() {
    REPO_NAMES=("dwm" "dmenu" "st" "slock" "slstatus")
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
        "libxft-dev" "libxrandr-dev" "libimlib2-dev" "git" "feh" "ripgrep"
        "screenfetch" "htop" "curl" "tlp" "ufw" "lm-sensors"
        "redshift" "unzip" "zip" "unrar" "arandr" "mlocate" "firefox-esr"
        "tree" "mpv" "xautolock"
        "python3-pip" "fuse" "pulsemixer" "fonts-font-awesome"
        "psmisc" "compton" "pavucontrol" "cmus"
        "libnotify-bin" "dunst" "brightnessctl" "xclip" "zathura"
        "xsel" "libxfixes-dev" "pass" "pass-extension-otp" "nnn"
        "libx11-xcb-dev" "libxcb-res0-dev" "ncal"
        "newsboat"
    )

    for PROGRAM in "${PROGRAMS[@]}"; do
        install_program $PROGRAM
    done
}

function install_clipboard_manager() {
    cd /home/$USERNAME/Projects;
    git clone https://github.com/cdown/clipnotify.git;
    cd clipnotify;
    make clean install;
    cd ..;
    git clone https://github.com/cdown/clipmenu.git;
    cd clipmenu;
    make install;
    cd ..;
}

function install_solaar() {
    # first two are dependencies
    apt install solaar;
}

function install_rust() {
    su - $USERNAME -c "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
}

add_user_to_sudoers
detect_sensors
add_contrib_and_non_free
install_programs
enable_firewall

install_microcode
install_program firmware-iwlwifi

install_docker
install_nodejs
install_bluetooth
install_program docker-compose
install_program qbittorrent

install_spotify
install_neovim

add_xinitrc
add_user_dirs
install_nerd_fonts

add_config_files
change_folder_permissions

build_suckless_tools
install_clipboard_manager

install_solaar
install_rust

cleanup
