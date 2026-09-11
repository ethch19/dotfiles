#!/bin/bash

bold_red() {
    echo -e "\033[31m$1\033[0m"
}

bold_green() {
    echo -e "\033[32m$1\033[0m"
}

bold_yellow() {
    echo -e "\033[33m$1\033[0m"
}

default_echo() {
    echo -e "\033[37m$1\033[0m"
}

confirm() {
    local prompt="$1"
    local answer

    read -r -n 1 -p "$(default_echo "$prompt (y/N), default: yes: ")" answer
    echo

    case $answer in
        [yY] | "") return 0;;
        *) return 1;;
    esac
}

cmd_exist() {
    if sudo -u "$SUDO_USER" -i command -v "$1" &> /dev/null; then
        bold_green "✅ $1 is already installed."
        return 0
    else
        return 1
    fi
}

if [[ -z $SUDO_USER ]]; then
    bold_red "Run this script with sudo: sudo ./auto_install.sh"
    exit 1
fi

INSTALL_HOME=$(getent passwd $SUDO_USER | cut -d: -f6)
cur_dir=$(pwd)
no_files="$(ls -1q -log | wc -l)"

if [[ $cur_dir != *"dotfiles"* ]]; then
    bold_red "Not in dotfiles directory"
    exit 1
fi
default_echo "Number of dotfiles: $no_files"

# base config 
home=(".tmux.conf" ".vimrc" "ethch.omp.toml")
dotconfig=("powerline")
etc=()
greetd_config=()

directory=("$INSTALL_HOME" "$INSTALL_HOME/.config")
objects=("home[@]" "dotconfig[@]")

laptop=0
if confirm "Install laptop configuration and apps (TLP, Throttled, Wayland)?"; then
    laptop=1
    dotconfig+=("sway" "waybar" "fuzzel")
    etc+=("tlp.conf" "throttled.conf")
    greetd_config+=("greetd/config.toml")

    directory+=("/etc" "/etc/greetd")
    objects+=("etc[@]" "greetd_config[@]")
fi

for index in ${!directory[@]}; do
    dir="${directory[$index]}"
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir"
        if [[ "$dir" == "$INSTALL_HOME"* ]]; then
            chown "$SUDO_USER:$SUDO_USER" "$dir"
        fi
    fi
    for obj in ${!objects[$index]}; do 
        source_path="$cur_dir/$obj"
        target_path="$dir/$(basename "$obj")"
        if [[ -f "$obj" ]]; then
            if [[ ! -f "$target_path" ]]; then
                # default_echo "No current $obj file in $dir"
                sudo ln -s "$source_path" "$target_path"
                bold_green "🔗 $target_path symlink created"
            else bold_yellow "$obj symlink in $dir already exists"
            fi
        elif [[ -d "$obj" ]]; then
            if [[ ! -d "$target_path" ]]; then
                if [[ -L "$target_path" ]]; then
                    bold_yellow "$obj symlink in $dir already exists"
                elif [[ -d "$target_path" ]]; then
                    bold_yellow "CONFLICT: Existing directory $obj already exists in $dir"
                else
                    sudo ln -s "$source_path" "$target_path"
                    if [ $? -eq 0 ]; then
                        bold_green "🔗 $target_path symlink created"
                    else
                        bold_red "Failed to create symlink for $obj"
                    fi
                fi
            else bold_yellow "$obj directory in $dir already exists"
            fi
        else bold_red "Invalid file/directory: $obj"
        fi
    done
done

# motd

bold_yellow "Configuring MOTD banner..."

chmod +x "$cur_dir/motd/01-custom-banner"

IS_DEBIAN_LIKE=0
if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [[ "\(ID" =~ ^(ubuntu|debian)\) || "$ID_LIKE" =~ (ubuntu|debian) ]]; then
        IS_DEBIAN_LIKE=1
    fi
fi

if (( IS_DEBIAN_LIKE )); then
    TARGET="/etc/update-motd.d/01-custom-banner"
    OBSOLETE="/etc/profile.d/01-custom-banner.sh"
else
    TARGET="/etc/profile.d/01-custom-banner.sh"
    OBSOLETE="/etc/update-motd.d/01-custom-banner"
fi

if [[ -L "\(OBSOLETE" || -f "\)OBSOLETE" ]]; then
    rm -f "$OBSOLETE"
    bold_yellow "Removed obsolete duplicate from $OBSOLETE"
fi

mkdir -p "\((dirname "\)TARGET")"
if [[ -L "$TARGET" ]]; then
    if [[ "\((readlink -f "\)TARGET")" == "\((readlink -f "\)cur_dir/motd/01-custom-banner")" ]]; then
        bold_green "✅ MOTD symlink at $TARGET is already correct"
    else
        ln -sf "\(cur_dir/motd/01-custom-banner" "\)TARGET"
        bold_green "🔗 Updated existing symlink at $TARGET"
    fi
elif [[ -e "$TARGET" ]]; then
    bold_red "CONFLICT: Non-symlink file exists at $TARGET"
else
    ln -s "\(cur_dir/motd/01-custom-banner" "\)TARGET"
    bold_green "🔗 Symlinked MOTD to $TARGET"
fi

if [[ "$DISTRO_FAMILY" == "debian" && -d "/etc/update-motd.d" ]]; then
    chmod -x /etc/update-motd.d/00-header \
             /etc/update-motd.d/10-help-text \
             /etc/update-motd.d/50-motd-news \
             /etc/update-motd.d/50-landscape-sysinfo \
             /etc/update-motd.d/90-updates-available \
             /etc/update-motd.d/91-contract-ua-esm-status \
             /etc/update-motd.d/92-unattended-upgrades \
             /etc/update-motd.d/95-hwe-eol 2>/dev/null || true
fi

touch /var/log/cf-ddns.log 2>/dev/null || true
chown "$SUDO_USER:$SUDO_USER" /var/log/cf-ddns.log 2>/dev/null || true
chmod 644 /var/log/cf-ddns.log 2>/dev/null || true

bold_green "✅ MOTD installed and configured"

bold_green "🔗 All symlinks created"


if ! confirm "Install apps used in config?"; then
    exit 1
fi

detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case "$ID $ID_LIKE" in
            *debian*|*ubuntu*) echo "debian" ;;
            *arch*|*manjaro*|*endeavouros*) echo "arch" ;;
            *fedora*|*rhel*|*centos*) echo "fedora" ;;
            *) echo "unknown" ;;
        esac
    else
        echo "unknown"
    fi
}

pkg_update() {
    case "$DISTRO_FAMILY" in
        debian) apt-get update -qq && apt-get upgrade -qq ;;
        arch)   pacman -Syu --noconfirm -q ;;
        fedora) dnf upgrade -y -q ;;
    esac
}

pkg_install() {
    case "$DISTRO_FAMILY" in
        debian) apt-get install -y -qq "$@" ;;
        arch)   pacman -S --noconfirm --needed -q "$@" ;;
        fedora) dnf install -y -q "$@" ;;
    esac
}

vim_has_python_and_lua() {
	if sudo -u "$SUDO_USER" -i command -v vim &> /dev/null; then
		local v_out
		v_out=$(sudo -u "$SUDO_USER" -i vim --version 2>/dev/null)
		if echo "$v_out" | grep -q '\+python3' && echo "$v_out" | grep -q '\+lua'; then
			bold_green "✅ vim with +python3 and +lua is already installed."
			return 0
		else
			bold_yellow "⚠️  vim is missing +python3 or +lua support."
			return 1
		fi
	fi
	return 1
}

if [[ "$DISTRO_FAMILY" != "unknown" ]]; then
    cd "$INSTALL_HOME" || exit 1
    pkg_update

    # PATH setup
    if [[ ":$PATH:" != *":$INSTALL_HOME/.local/bin:"* ]]; then
        echo "export PATH=\$PATH:$INSTALL_HOME/.local/bin" >> "$INSTALL_HOME/.bashrc"
    fi

    # git + vim build tools
    bold_yellow "Ensuring build dependencies and headers are installed..."
    case "$DISTRO_FAMILY" in
        debian)
            pkg_install git make clang libtool-bin libncurses-dev \
                        libpython3-dev libluajit-5.1-dev luajit pkg-config
            ;;
        arch)
            pkg_install base-devel git clang ncurses python luajit pkgconf
            ;;
        fedora)
            pkg_install git make clang libtool ncurses-devel \
                        python3-devel luajit-devel pkgconf
            ;;
    esac
    bold_green "✅ Build tools and libraries verified"

    # vim
    if ! vim_has_python_and_lua; then
        bold_yellow "Building Vim from source with +python3 and +lua support..."
		git clone https://github.com/vim/vim.git /tmp/vim-src
		cd /tmp/vim-src/src || exit 1
		./configure \
			--with-features=huge \
			--enable-fail-if-missing \
			--enable-multibyte \
			--enable-python3interp=yes \
			--enable-luainterp=yes \
			--with-luajit \
			--prefix=/usr/local
		make -s
		make -s install
		rm -rf /tmp/vim-src
		cd "$INSTALL_HOME" || exit 1

		# Point system alternatives and clear cache so /usr/local/bin/vim takes precedence
        if command -v update-alternatives &>/dev/null; then
            update-alternatives --install /usr/bin/vim vim /usr/local/bin/vim 100
            update-alternatives --set vim /usr/local/bin/vim
        fi
        hash -r 2>/dev/null

		bold_green "✅ vim installed with +python3 and +lua"
    fi

    # curl
    ! cmd_exist "curl" && pkg_install curl
    ! cmd_exist "tmux" && pkg_install tmux
    ! cmd_exist "unzip" && pkg_install unzip

    # vim-plug
    plug_file="$INSTALL_HOME/.vim/autoload/plug.vim"
    if [ ! -f "$plug_file" ]; then
        bold_yellow "Installing vim-plug..."
        sudo -u "$SUDO_USER" curl -fLo "$plug_file" --create-dirs \
            https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
                    bold_green "✅ vim-plug installed"
    fi

    bold_yellow "Installing Vim plugins via vim-plug..."
    sudo -u "$SUDO_USER" vim -es -u "$INSTALL_HOME/.vimrc" -i NONE -c "PlugInstall --sync" -c "qa"
    bold_green "✅ vim plugins installed"

    # powerline in dedicated virtualenv
    venvpath="$INSTALL_HOME/.local/share/powerline-venv"

    if [ ! -d "$venvpath" ]; then
        bold_yellow "Installing Powerline and dependencies..."
        case "$DISTRO_FAMILY" in
            debian) pkg_install python3-full python3-pip fontconfig ;;
            arch)   pkg_install python python-pip fontconfig ;;
            fedora) pkg_install python3-pip fontconfig ;;
        esac

        sudo -u "$SUDO_USER" python3 -m venv "$venvpath"

        sudo -u "$SUDO_USER" "$venvpath/bin/pip" install --upgrade pip -q
        sudo -u "$SUDO_USER" "$venvpath/bin/pip" install powerline-status -q

        mkdir -p "$INSTALL_HOME/.local/bin"
        ln -sf "$venvpath/bin/powerline" "$INSTALL_HOME/.local/bin/powerline"
        chown -h "$SUDO_USER:$SUDO_USER" "$INSTALL_HOME/.local/bin/powerline"

        mkdir -p "$INSTALL_HOME/.local/share/fonts" "$INSTALL_HOME/.config/fontconfig/conf.d"
        wget -qO "$INSTALL_HOME/.local/share/fonts/PowerlineSymbols.otf" https://github.com/powerline/powerline/raw/develop/font/PowerlineSymbols.otf
        wget -qO "$INSTALL_HOME/.config/fontconfig/conf.d/10-powerline-symbols.conf" https://github.com/powerline/powerline/raw/develop/font/10-powerline-symbols.conf

        chmod 644 "$INSTALL_HOME/.local/share/fonts/PowerlineSymbols.otf"
        chmod 644 "$INSTALL_HOME/.config/fontconfig/conf.d/10-powerline-symbols.conf"
        chown -R "$SUDO_USER:$SUDO_USER" "$INSTALL_HOME/.local/share/fonts" "$INSTALL_HOME/.config/fontconfig"
        fc-cache -vf "$INSTALL_HOME/.local/share/fonts/" >/dev/null

        bold_green "✅ Powerline installed in virtualenv"
    else
        bold_green "✅ Powerline virtualenv already exists"
    fi

    # omp
    if ! cmd_exist "oh-my-posh"; then
        curl -s https://ohmyposh.dev/install.sh | bash -s -- -d /usr/local/bin
        oh-my-posh font install literationmono
        echo 'eval "$(oh-my-posh init bash --config ~/ethch.omp.toml)"' >> $INSTALL_HOME/.bashrc
        default_echo "Oh-my-posh bashrc added"
        bold_green "✅ oh-my-posh installed"
    fi

    if (( laptop )); then
        # TLP
        ! cmd_exist "tlp-stat" && pkg_install tlp
        bold_green "✅ tlp installed"

        # Wayland utilities
        ! cmd_exist "sway" && pkg_install sway
        bold_green "✅ sway installed"
        ! cmd_exist "waybar" && pkg_install waybar
        bold_green "✅ waybar installed"
        ! cmd_exist "fuzzel" && pkg_install fuzzel
        bold_green "✅ fuzzel installed"
        
        case "$DISTRO_FAMILY" in
            debian) pkg_install greetd tuigreet ;;
            arch)   pkg_install greetd greetd-tuigreet ;;
            fedora) pkg_install greetd tuigreet ;;
        esac
        bold_green "✅ tuigreet installed"
        bold_green "✅ greetd installed"
        bold_yellow "Remember to enable greetd daemon via systemctl"

        # throttled
        thrd_dir="/opt/throttled"
        thrd_wrap="/usr/local/bin/throttled"
        thrd_sym="$INSTALL_HOME/.local/bin/throttled"

        if ! grep -q "GenuineIntel" /proc/cpuinfo; then
            bold_yellow "⚠️  Skipping throttled: Not an Intel CPU"
        elif [[ ! -d $thrd_dir ]]; then
            bold_yellow "Installing throttled dependencies..."
            case "$DISTRO_FAMILY" in
                debian)
                    pkg_install git build-essential python3-dev libdbus-glib-1-dev \
                                libgirepository1.0-dev libcairo2-dev python3-cairo-dev \
                                python3-venv python3-wheel
                    ;;
                arch)
                    pkg_install git base-devel python dbus-glib \
                                gobject-introspection cairo python-cairo
                    ;;
                fedora)
                    pkg_install git gcc make python3-devel dbus-glib-devel \
                                gobject-introspection-devel cairo-devel python3-cairo-devel \
                                python3-wheel
                    ;;
            esac

            git clone https://github.com/erpalma/throttled.git /tmp/throttled-src
            cd /tmp/throttled-src || exit 1
            ./install.sh
            rm -rf /tmp/throttled-src
            cd "$INSTALL_HOME" || exit 1

            # Disable thermald service if present
            if systemctl list-unit-files | grep -q "thermald.service"; then
                systemctl stop thermald.service 2>/dev/null || true
                systemctl disable thermald.service 2>/dev/null || true
                systemctl mask thermald.service 2>/dev/null || true
            fi

            # Wrapper for CLI execution inside the venv
            if [[ ! -f $thrd_wrap ]]; then
                cat > "$thrd_wrap" << 'EOF'
#!/bin/bash
exec "/opt/throttled/venv/bin/python" "/opt/throttled/throttled.py" "$@"
EOF
                chmod +x "$thrd_wrap"
            fi

            if [[ ! -L $thrd_sym ]]; then
                ln -sf "$thrd_wrap" "$thrd_sym"
            fi

            bold_green "✅ throttled installed and service started"
        else
            bold_green "✅ throttled is already installed."
        fi
    fi
else 
    bold_red "OS distro cannot be found. No apps have been installed"
    exit 1
fi

# new shell (refresh) LAST AS ANYTHING AFTER WILL NOT RUN
cd $INSTALL_HOME || exit 1
bold_yellow "Refresh bash: exec bash or source ~/.bashrc"
