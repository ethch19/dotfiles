#!/bin/bash

set -o pipefail

CLEAN_INSTALL=0
# Keep Vim and Powerline on the system Python, even from an activated venv.
PYTHON_BIN="${PYTHON_BIN:-/usr/bin/python3}"

case "${1:-}" in
    --clean)
        CLEAN_INSTALL=1
        ;;
    "")
        ;;
    *)
        printf 'Usage: %s [--clean]\n' "$0" >&2
        exit 2
        ;;
esac

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

die() {
    bold_red "$*"
    exit 1
}

append_once() {
    local line="$1"
    local file="$2"

    touch "$file" \
        || die "Could not create or access: $file"

    if ! grep -Fqx -- "$line" "$file"; then
        printf '%s\n' "$line" >> "$file" \
            || die "Could not update: $file"
    fi

    chown "$SUDO_USER:$INSTALL_GROUP" "$file" \
        || die "Could not set ownership on: $file"
}

cleanup_backup_root=""
cleanup_system_backup_root=""


initialise_cleanup_backups() {
    local timestamp

    timestamp=$(date +%Y%m%d-%H%M%S)

    cleanup_backup_root="$INSTALL_HOME/.local/share/auto_install-backups/$timestamp"
    cleanup_system_backup_root="/root/auto_install-backups/$timestamp"

    install -d -o "$SUDO_USER" -g "$INSTALL_GROUP" "$cleanup_backup_root" \
        || die "Could not create user backup directory."

    install -d -m 700 "$cleanup_system_backup_root" \
        || die "Could not create system backup directory."

    bold_yellow "Clean-install backups will be saved to:"
    default_echo "  User files:   $cleanup_backup_root"
    default_echo "  System files: $cleanup_system_backup_root"
}


backup_managed_path() {
    local target_path="$1"
    local backup_root
    local relative_path
    local backup_path

    # Nothing exists at this location, including no dangling symlink.
    if [[ ! -e "$target_path" && ! -L "$target_path" ]]; then
        return 0
    fi

    if [[ "$target_path" == "$INSTALL_HOME"/* ]]; then
        backup_root="$cleanup_backup_root"
        relative_path="${target_path#"$INSTALL_HOME"/}"
    else
        backup_root="$cleanup_system_backup_root"
        relative_path="${target_path#/}"
    fi

    backup_path="$backup_root/$relative_path"

    mkdir -p -- "$(dirname -- "$backup_path")" \
        || die "Could not create backup directory for: $target_path"

    mv -- "$target_path" "$backup_path" \
        || die "Could not back up existing path: $target_path"

    bold_yellow "Backed up existing path: $target_path"
}


clean_selected_symlink_targets() {
    local index
    local dir
    local array_ref
    local obj
    local target_path

    for index in "${!directory[@]}"; do
        dir="${directory[$index]}"
        array_ref="${objects[$index]}"
        declare -n items="$array_ref"

        for obj in "${items[@]}"; do
            target_path="$dir/$(basename -- "$obj")"
            backup_managed_path "$target_path"
        done
    done
}


clean_user_tooling() {
    backup_managed_path "$INSTALL_HOME/.local/share/powerline-venv"
    backup_managed_path "$INSTALL_HOME/.local/bin/powerline"
    backup_managed_path "$INSTALL_HOME/.local/bin/throttled"

    backup_managed_path "$INSTALL_HOME/.local/share/fonts/PowerlineSymbols.otf"
    backup_managed_path "$INSTALL_HOME/.config/fontconfig/conf.d/10-powerline-symbols.conf"

    backup_managed_path "$INSTALL_HOME/.vim/autoload/plug.vim"
    backup_managed_path "$INSTALL_HOME/.vim/plugged"
}

confirm() {
    local prompt="$1"
    local answer

    read -r -n 1 -p "$(default_echo "$prompt (y/N): ")" answer
    echo

    case "$answer" in
        [yY]) return 0 ;;
        *)    return 1 ;;
    esac
}


cmd_exists() {
    if command -v -- "$1" >/dev/null 2>&1; then
        bold_green "✅ $1 is already installed."
        return 0
    fi
    return 1
}

if (( EUID != 0 )); then
    die "Run this script with sudo: sudo ./auto_install.sh"
fi

if [[ -z "${SUDO_USER:-}" || "$SUDO_USER" == "root" ]]; then
    die "Run this from an unprivileged account via sudo, not from a root login."
fi

detect_distro() {
    local os_release

    if [ -r /etc/os-release ]; then
        os_release=/etc/os-release
    elif [ -r /usr/lib/os-release ]; then
        os_release=/usr/lib/os-release
    else
        echo "unknown"
        return 0
    fi

    # shellcheck disable=SC1090
    . "$os_release"

    case "${ID:-} ${ID_LIKE:-}" in
        *debian*|*ubuntu*)
            echo "debian"
            ;;
        *arch*|*manjaro*|*endeavouros*)
            echo "arch"
            ;;
        *fedora*|*rhel*|*centos*)
            echo "fedora"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

DISTRO_FAMILY=$(detect_distro)

INSTALL_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
INSTALL_GROUP=$(id -gn "$SUDO_USER") \
    || die "Could not determine the primary group for $SUDO_USER."

if [[ -z "$INSTALL_HOME" || ! -d "$INSTALL_HOME" ]]; then
    die "Could not determine a valid home directory for $SUDO_USER."
fi

install -d -o "$SUDO_USER" -g "$INSTALL_GROUP" \
    "$INSTALL_HOME/.config" \
    "$INSTALL_HOME/.local" \
    "$INSTALL_HOME/.local/bin" \
    "$INSTALL_HOME/.local/share" \
    || die "Could not create required user directories."

cur_dir=$(pwd -P)
no_files=$(find "$cur_dir" -mindepth 1 -maxdepth 1 -printf '.' | wc -c)

if [[ "$(basename -- "$cur_dir")" != "dotfiles" ]]; then
    die "Run this script from the dotfiles repository root."
fi
default_echo "Number of dotfiles: $no_files"

# base config 
# shellcheck disable=SC2034
# Accessed indirectly through objects[] and declare -n items.
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

if (( CLEAN_INSTALL )); then
    if confirm "Clean old managed configuration and back it up before installation?"; then
        initialise_cleanup_backups
        clean_selected_symlink_targets
        clean_user_tooling
        bold_green "✅ Previous managed user configuration backed up."
    else
        die "Clean install cancelled."
    fi
fi

for index in "${!directory[@]}"; do
    dir="${directory[$index]}"
    array_ref="${objects[$index]}"
    declare -n items="$array_ref"

    if [[ ! -d "$dir" ]]; then
        mkdir -p -- "$dir" || die "Could not create directory: $dir"

        if [[ "$dir" == "$INSTALL_HOME"* ]]; then
            chown "$SUDO_USER:$INSTALL_GROUP" "$dir" \
                || die "Could not set ownership on: $dir"
        fi
    fi

    for obj in "${items[@]}"; do
        source_path="$cur_dir/$obj"
        target_path="$dir/$(basename -- "$obj")"

        if [[ -f "$source_path" || -d "$source_path" ]]; then
            :
        else
            bold_red "Invalid file/directory: $source_path"
            exit 1
        fi

        if [[ -L "$target_path" ]]; then
            if [[ "$(readlink -f -- "$target_path")" == "$(readlink -f -- "$source_path")" ]]; then
                bold_green "✅ Symlink already correct: $target_path"
            else
                bold_red "CONFLICT: $target_path is a symlink to a different target"
                exit 1
            fi
        elif [[ -e "$target_path" ]]; then
            bold_red "CONFLICT: Existing non-symlink path: $target_path"
            exit 1
        else
            ln -s -- "$source_path" "$target_path" || {
                bold_red "Failed to create symlink: $target_path"
                exit 1
            }
            bold_green "🔗 Created: $target_path"
        fi
    done
done

# motd
if confirm "Install and configure the custom MOTD banner?"; then
    bold_yellow "Configuring MOTD banner..."

    MOTD_SOURCE="$cur_dir/motd/01-custom-banner"

    if [[ ! -f "$MOTD_SOURCE" ]]; then
        die "Missing MOTD source: $MOTD_SOURCE"
    fi

    chmod +x "$MOTD_SOURCE" \
        || die "Could not make MOTD source executable: $MOTD_SOURCE"

    # Use update-motd only when the distro actually provides that mechanism.
    if [[ "$DISTRO_FAMILY" == "debian" && -d /etc/update-motd.d ]]; then
        TARGET="/etc/update-motd.d/01-custom-banner"
        OBSOLETE="/etc/profile.d/01-custom-banner.sh"
    else
        TARGET="/etc/profile.d/01-custom-banner.sh"
        OBSOLETE="/etc/update-motd.d/01-custom-banner"
    fi

    if (( CLEAN_INSTALL )); then
        backup_managed_path "$TARGET"
        backup_managed_path "$OBSOLETE"
    fi

    # Remove an obsolete managed symlink, but never delete an ordinary file.
    if [[ -L "$OBSOLETE" ]]; then
        rm -f -- "$OBSOLETE" \
            || die "Could not remove obsolete MOTD symlink: $OBSOLETE"

        bold_yellow "Removed obsolete MOTD symlink from $OBSOLETE"
    elif [[ -e "$OBSOLETE" ]]; then
        die "CONFLICT: Existing non-symlink MOTD file at $OBSOLETE"
    fi

    mkdir -p -- "$(dirname -- "$TARGET")" \
        || die "Could not create MOTD target directory."

    if [[ -L "$TARGET" ]]; then
        if [[ "$(readlink -f -- "$TARGET")" == "$(readlink -f -- "$MOTD_SOURCE")" ]]; then
            bold_green "✅ MOTD symlink at $TARGET is already correct"
        else
            ln -sfn -- "$MOTD_SOURCE" "$TARGET" \
                || die "Could not update MOTD symlink at $TARGET."

            bold_green "🔗 Updated existing MOTD symlink at $TARGET"
        fi
    elif [[ -e "$TARGET" ]]; then
        die "CONFLICT: Non-symlink file exists at $TARGET"
    else
        ln -s -- "$MOTD_SOURCE" "$TARGET" \
            || die "Could not create MOTD symlink at $TARGET."

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
                 /etc/update-motd.d/95-hwe-eol \
                 2>/dev/null || true
    fi

    # CF-DDNS log file
    touch /var/log/cf-ddns.log 2>/dev/null || true
    chown "$SUDO_USER:$INSTALL_GROUP" /var/log/cf-ddns.log 2>/dev/null || true
    chmod 644 /var/log/cf-ddns.log 2>/dev/null || true

    bold_green "✅ MOTD installed and configured"
else
    bold_yellow "Skipping MOTD installation."
fi

bold_green "🔗 All symlinks created"


if ! confirm "Install apps used in config?"; then
    exit 1
fi

pkg_refresh() {
    case "$DISTRO_FAMILY" in
        debian)
            apt-get update -qq
            ;;
        arch)
            pacman -Sy --noconfirm -q
            ;;
        fedora)
            dnf makecache -q
            ;;
        *)
            return 1
            ;;
    esac
}

pkg_upgrade() {
    case "$DISTRO_FAMILY" in
        debian)
            apt-get upgrade -y -qq
            ;;
        arch)
            pacman -Syu --noconfirm -q
            ;;
        fedora)
            dnf upgrade -y -q
            ;;
        *)
            return 1
            ;;
    esac
}

pkg_install() {
    case "$DISTRO_FAMILY" in
        debian)
            apt-get install -y -qq "$@"
            ;;
        arch)
            pacman -S --noconfirm --needed -q "$@"
            ;;
        fedora)
            dnf install -y -q "$@"
            ;;
        *)
            die "Unsupported distribution family: $DISTRO_FAMILY"
            ;;
    esac || die "Package installation failed: $*"
}

vim_has_python_and_lua() {
    local v_out

    if ! command -v vim >/dev/null 2>&1; then
        return 1
    fi

    v_out=$(vim --version 2>/dev/null) || return 1

    if ! grep -q '+python3' <<<"$v_out" || ! grep -q '+lua' <<<"$v_out"; then
        bold_yellow "⚠️  vim is missing +python3 or +lua support."
        return 1
    fi

    if ! env -u PYTHONHOME -u PYTHONPATH -u LD_LIBRARY_PATH \
        EXPECTED_PYTHON_PREFIX="$PYTHON_PREFIX" \
        vim -Nu NONE -n -es \
        -c 'if !has("python3") || !has("lua") | cquit 1 | endif' \
        -c 'python3 import os, sys; assert sys.prefix == os.environ["EXPECTED_PYTHON_PREFIX"]; import ctypes' \
        -c 'qa!'; then
        bold_yellow "⚠️  vim advertises Python/Lua support, but it is not usable at runtime."
        return 1
    fi

    bold_green "✅ vim with usable +python3 and +lua is already installed."
    return 0
}

if [[ "$DISTRO_FAMILY" != "unknown" ]]; then
    cd "$INSTALL_HOME" || die "Could not enter $INSTALL_HOME."

    pkg_refresh || die "Package metadata refresh failed."

    if confirm "Perform a full system package upgrade before installing dependencies?"; then
        pkg_upgrade || die "Full system package upgrade failed."
    fi

    # PATH setup
    # shellcheck disable=SC2016
    # $PATH and $HOME must expand later when .bashrc is sourced.
    append_once \
        'export PATH="$HOME/.local/bin:$PATH"' \
        "$INSTALL_HOME/.bashrc"

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

    if [[ ! -x "$PYTHON_BIN" ]]; then
        die "Configured Python executable is not available: $PYTHON_BIN"
    fi

    PYTHON_PREFIX=$(env -u PYTHONHOME -u PYTHONPATH -u LD_LIBRARY_PATH \
        "$PYTHON_BIN" -c 'import sys; print(sys.prefix)') \
        || die "Could not determine the configured Python prefix."

    # vim
    if ! vim_has_python_and_lua; then
        bold_yellow "Building Vim from source with +python3 and +lua support..."
		rm -rf /tmp/vim-src
        git clone https://github.com/vim/vim.git /tmp/vim-src \
            || die "Failed to clone Vim source."
        cd /tmp/vim-src/src || die "Could not enter Vim source directory."
        env -u PYTHONHOME -u PYTHONPATH -u LD_LIBRARY_PATH \
        ./configure \
			--with-features=huge \
			--enable-fail-if-missing \
			--enable-multibyte \
			--enable-python3interp=yes \
            --with-python3-command="$PYTHON_BIN" \
			--enable-luainterp=yes \
			--with-luajit \
			--prefix=/usr/local \
            || die "Vim configure step failed."
		make -s -j"$(nproc)" || die "Vim build failed."
        make -s install || die "Vim installation failed."
		rm -rf /tmp/vim-src
		cd "$INSTALL_HOME" || exit 1

		# Point system alternatives and clear cache so /usr/local/bin/vim takes precedence
        if command -v update-alternatives >/dev/null 2>&1; then
            update-alternatives --install /usr/bin/vim vim /usr/local/bin/vim 100 \
                || die "Could not register the Vim alternative."

            update-alternatives --set vim /usr/local/bin/vim \
                || die "Could not select the new Vim alternative."
        fi
        hash -r 2>/dev/null

        if ! vim_has_python_and_lua; then
            die "The newly built Vim failed the Python/Lua runtime check."
        fi

		bold_green "✅ vim installed with +python3 and +lua"
    fi

    # tools
    cmd_exists curl || pkg_install curl
    cmd_exists "tmux" || pkg_install tmux
    cmd_exists "unzip" || pkg_install unzip
    cmd_exists node || pkg_install nodejs
    cmd_exists npm || pkg_install npm

    # vim-plug
    plug_file="$INSTALL_HOME/.vim/autoload/plug.vim"
    if [ ! -f "$plug_file" ]; then
        bold_yellow "Installing vim-plug..."
        sudo -u "$SUDO_USER" -H mkdir -p "$INSTALL_HOME/.vim/autoload" \
            || die "Could not create Vim autoload directory."

        sudo -u "$SUDO_USER" -H curl -fL --retry 3 \
            -o "$plug_file" \
            https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim \
            || die "Failed to download vim-plug."
        bold_green "✅ vim-plug installed"
    fi

    bold_yellow "Installing Vim plugins via vim-plug..."
    sudo -u "$SUDO_USER" -H env -u PYTHONHOME -u PYTHONPATH -u LD_LIBRARY_PATH vim -N -n \
        -es \
        -u "$INSTALL_HOME/.vimrc" \
        -i NONE \
        -c 'PlugInstall --sync' \
        -c 'qa!' \
        || die "Vim plugin installation failed."
    bold_green "✅ vim plugins installed"

    # powerline in dedicated virtualenv
    venvpath="$INSTALL_HOME/.local/share/powerline-venv"
    install -d -o "$SUDO_USER" -g "$INSTALL_GROUP" \
    "$INSTALL_HOME/.local/bin" \
    "$INSTALL_HOME/.local/share" \
    "$INSTALL_HOME/.local/share/fonts" \
    "$INSTALL_HOME/.config/fontconfig/conf.d" \
        || die "Could not create required Powerline directories."

    if [[ ! -x "$venvpath/bin/python" || ! -x "$venvpath/bin/pip" ]] \
        || ! env -u PYTHONHOME -u PYTHONPATH -u LD_LIBRARY_PATH "$venvpath/bin/python" -c \
            'import sys; raise SystemExit(sys.base_prefix != sys.argv[1])' \
            "$PYTHON_PREFIX"; then
        bold_yellow "Installing Powerline and dependencies..."

        rm -rf -- "$venvpath"

        case "$DISTRO_FAMILY" in
            debian) pkg_install python3-full python3-pip fontconfig ;;
            arch)   pkg_install python python-pip fontconfig ;;
            fedora) pkg_install python3-pip fontconfig ;;
        esac

        sudo -u "$SUDO_USER" -H env -u PYTHONHOME -u PYTHONPATH -u LD_LIBRARY_PATH \
            "$PYTHON_BIN" -m venv "$venvpath" \
            || die "Could not create the Powerline virtual environment."

        sudo -u "$SUDO_USER" -H env -u PYTHONHOME -u PYTHONPATH -u LD_LIBRARY_PATH \
            "$venvpath/bin/pip" install --upgrade pip -q \
            || die "Could not upgrade pip in the Powerline virtual environment."

        sudo -u "$SUDO_USER" -H env -u PYTHONHOME -u PYTHONPATH -u LD_LIBRARY_PATH \
            "$venvpath/bin/pip" install powerline-status -q \
            || die "Could not install powerline-status."

        ln -sfn "$venvpath/bin/powerline" "$INSTALL_HOME/.local/bin/powerline" \
            || die "Could not create Powerline executable symlink."

        chown -h "$SUDO_USER:$INSTALL_GROUP" "$INSTALL_HOME/.local/bin/powerline" \
            || die "Could not set ownership on Powerline executable symlink."

        sudo -u "$SUDO_USER" -H curl -fL --retry 3 \
            -o "$INSTALL_HOME/.local/share/fonts/PowerlineSymbols.otf" \
            https://github.com/powerline/powerline/raw/develop/font/PowerlineSymbols.otf \
            || die "Failed to download PowerlineSymbols.otf."

        sudo -u "$SUDO_USER" -H curl -fL --retry 3 \
            -o "$INSTALL_HOME/.config/fontconfig/conf.d/10-powerline-symbols.conf" \
            https://github.com/powerline/powerline/raw/develop/font/10-powerline-symbols.conf \
            || die "Failed to download Powerline fontconfig configuration."

        chmod 644 \
            "$INSTALL_HOME/.local/share/fonts/PowerlineSymbols.otf" \
            "$INSTALL_HOME/.config/fontconfig/conf.d/10-powerline-symbols.conf" \
            || die "Could not set Powerline file permissions."

        chown -R "$SUDO_USER:$INSTALL_GROUP" \
            "$INSTALL_HOME/.local/share/fonts" \
            "$INSTALL_HOME/.config/fontconfig" \
            || die "Could not set ownership on Powerline files."

        sudo -u "$SUDO_USER" -H fc-cache -f "$INSTALL_HOME/.local/share/fonts/" \
            >/dev/null \
            || die "Font cache refresh failed."

        bold_green "✅ Powerline installed in virtualenv"
    else
        bold_green "✅ Powerline virtualenv already exists"
    fi

    # omp
    if ! cmd_exists "oh-my-posh"; then
        curl -fsSL https://ohmyposh.dev/install.sh \
            | bash -s -- -d /usr/local/bin \
            || die "Oh My Posh installation failed."

        bold_green "✅ Oh My Posh installed"
    fi

    sudo -u "$SUDO_USER" -H oh-my-posh font install literationmono \
        || bold_yellow "⚠️  Could not install the Oh My Posh font automatically."

    # shellcheck disable=SC2016
    # $HOME and command substitution must be evaluated in the user's future shell.
    append_once \
        'eval "$(oh-my-posh init bash --config "$HOME/ethch.omp.toml")"' \
        "$INSTALL_HOME/.bashrc"

    if (( laptop )); then
        # TLP
        cmd_exists "tlp-stat" || pkg_install tlp

        # Wayland utilities
        cmd_exists "sway" || pkg_install sway
        cmd_exists "waybar" || pkg_install waybar
        cmd_exists "fuzzel" ||  pkg_install fuzzel
        
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
        elif [[ ! -d "$thrd_dir" ]]; then
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

            rm -rf /tmp/throttled-src
            git clone https://github.com/erpalma/throttled.git /tmp/throttled-src \
                || die "Failed to clone throttled source."
            cd /tmp/throttled-src || die "Could not enter throttled source directory."
            ./install.sh || die "Throttled installer failed."
            rm -rf /tmp/throttled-src
            cd "$INSTALL_HOME" || exit 1

            # Disable thermald service if present
            if systemctl list-unit-files | grep -q "thermald.service"; then
                systemctl stop thermald.service 2>/dev/null || true
                systemctl disable thermald.service 2>/dev/null || true
                systemctl mask thermald.service 2>/dev/null || true
            fi

            # Wrapper for CLI execution inside the venv
            if [[ ! -f "$thrd_wrap" ]]; then
                cat > "$thrd_wrap" << 'EOF'
#!/bin/bash
exec "/opt/throttled/venv/bin/python" "/opt/throttled/throttled.py" "$@"
EOF
                chmod +x "$thrd_wrap"
            fi

            if [[ -L "$thrd_sym" ]]; then
                if [[ "$(readlink -f -- "$thrd_sym")" == "$(readlink -f -- "$thrd_wrap")" ]]; then
                    bold_green "✅ throttled user symlink is already correct"
                else
                    die "CONFLICT: $thrd_sym is a symlink to a different target"
                fi
            elif [[ -e "$thrd_sym" ]]; then
                die "CONFLICT: Existing non-symlink path at $thrd_sym"
            else
                ln -s -- "$thrd_wrap" "$thrd_sym" \
                    || die "Could not create throttled user symlink."
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
cd "$INSTALL_HOME" || exit 1
bold_yellow "Apply the updated shell configuration with: source ~/.bashrc"
