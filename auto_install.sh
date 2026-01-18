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

# symlink creation
home=(".tmux.conf" ".vimrc" "ethch.omp.toml")
dotconfig=("powerline")
etc=("tlp.conf")
greetd_config=("greetd/config.toml")
directory=( "$INSTALL_HOME" "$INSTALL_HOME/.config" "/etc")
objects=( "home[@]" "dotconfig[@]" "etc[@]") 

if confirm "Install Wayland config?"; then
	directory+=("/etc/greetd")
	objects+=("greetd_config[@]")
	dotconfig+=("sway" "waybar" "fuzzel")
	waylandvar=1
fi

if confirm "Install t480 throttled config?"; then 
	etc+=("throttled.conf")
	throttledvar=1
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
bold_green "🔗 All symlinks created"

if ! confirm "Install apps used in config?"; then
	exit 1
fi

# check debian or not
if [ -f /etc/os-release ]; then
	. /etc/os-release
	OS=$NAME
	VER=$VERSION_ID
elif type lsb_release >/dev/null 2>&1; then
	OS=$(lsb_release -si)
	VER=$(lsb_release -sr)
elif [ -f /etc/lsb-release ]; then
	. /etc/lsb-release
	OS=$DISTRIB_ID
	VER=$DISTRIB_RELEASE
elif [ -f /etc/debian_version ]; then
	OS=Debian
	VER=$(cat /etc/debian_version)
else
	OS=$(uname -s)
	VER=$(uname -r)
fi

if [[ ${OS,,} == *"debian"* || ${OS,,} == *"ubuntu"* ]]; then
	cd $INSTALL_HOME
	# apt-get within userspace?
	apt-get update -qq && apt-get upgrade -qq

	# This is added prior to oh-my-posh line
	# Add ~/.local/bin into PATH
	# CHECK IN USER SPACE NOT ROOT
	if [[ ":$PATH:" != *":$INSTALL_HOME/.local/bin:"* ]]; then
		echo "export PATH=$PATH:$INSTALL_HOME/.local/bin" >> ~/.bashrc
	fi

	# git + vim build tools
	# CMD_EXIST NEEDS TO CHECK IN USER HOME
	if ! cmd_exist "git"; then
		apt-get install git make clang libtool-bin libpython3-dev libncurses-dev -qq
		bold_green "✅ git installed"
	fi

	# vim
	if ! cmd_exist "vim"; then
		git clone https://github.com/vim/vim.git
		cd vim/src
		./configure --with-features=huge --enable-python3interp
		make -s
		make -s install
		bold_green "✅ vim installed"
	fi

	# tmux
	if ! cmd_exist "tmux"; then
		apt-get install tmux -qq
		bold_green "✅ tmux installed"
	fi

	# powerline
	if ! cmd_exist "powerline"; then
		apt-get install python3-full python3-pip -qq 
		venvpath="$INSTALL_HOME/.local/share/powerline-venv"
		python3 -m venv --upgrade-deps $venvpath
		source $venvpath/bin/activate
		pip install powerline-status
		deactivate
		mkdir -p $INSTALL_HOME/.local/bin
		ln -s $venvpath/bin/powerline ~/.local/bin/powerline
		vimrtp=$(find "${venvpath}" -path "*powerline/bindings/vim")
		if [ -z "$vimrtp" ]; then
			bold_red "ERROR: Could not find the Powerline vim bindings path. Installation failed."
			exit 1 
		fi
		bold_yellow "As powerline is installed via venv as a library at $venvpath, check that .vimrc contains this line:\nset rtp+=$vimrtp"
		sudo apt-get install fontconfig -qq
		wget -q https://github.com/powerline/powerline/raw/develop/font/PowerlineSymbols.otf
		wget -q https://github.com/powerline/powerline/raw/develop/font/10-powerline-symbols.conf
		mkdir -p $INSTALL_HOME/.local/share/fonts
		mv PowerlineSymbols.otf $INSTALL_HOME/.local/share/fonts/
		chmod 644 $INSTALL_HOME/.local/share/fonts/PowerlineSymbols.otf
		sudo fc-cache -vf $INSTALL_HOME/.local/share/fonts/
		mkdir -p $INSTALL_HOME/.config/fontconfig/conf.d
		mv 10-powerline-symbols.conf $INSTALL_HOME/.config/fontconfig/conf.d/
		chmod 644 $INSTALL_HOME/.config/fontconfig/conf.d/10-powerline-symbols.conf
		bold_yellow "If using WSL on Windows Powershell, the font should be installed on Windows separately."
		bold_green "✅ powerline installed"
	fi

	# curl
	if ! cmd_exist "curl"; then
		apt-get install curl -qq
	fi

	# omp
	if ! cmd_exist "oh-my-posh"; then
		apt-get install unzip -qq
		curl -s https://ohmyposh.dev/install.sh | bash -s -- -d ~/usr/local/bin
		oh-my-posh font install literationmono
		echo 'eval "$(oh-my-posh init bash --config ~/ethch.omp.toml)"' >> $INSTALL_HOME/.bashrc
		default_echo "Oh-my-posh bashrc added"
		bold_green "✅ oh-my-posh installed"	
	fi

	# tlp
	if ! cmd_exist "tlp-stat"; then
		apt-get install tlp tlp-rdw -qq
		bold_green "✅ tlp installed"	
	fi

	# wayland
	if (( $waylandvar )); then
		bold_yellow "The following apps will be installed but targetted for Debian 13 (Trixie): sway,  waybar, fuzzel, greetd (+ tuigreet)"
		if ! cmd_exist "sway"; then
			apt-get install sway -qq
			bold_green "✅ sway installed"	
		fi
		if ! cmd_exist "waybar"; then
			apt-get install waybar -qq
			bold_green "✅ waybar installed"	
		fi
		if ! cmd_exist "fuzzel"; then
			apt-get install fuzzel -qq
			bold_green "✅ fuzzel installed"	
		fi
		if ! dpkg -l | grep -q "^ii  greetd "; then
			apt-get install greetd -qq
			bold_green "✅ greetd installed"	
			bold_yellow "Remember to enable greetd daemon via systemctl"
		fi
		if ! cmd_exist "tuigreet"; then
			apt-get install tuigreet -qq
			bold_green "✅ tuigreet installed"	
		fi
	fi

	# throttled
	if (( $throttledvar )); then
		thrd_dir="/opt/throttled"
		thrd_wrap="/usr/local/bin/throttled"
		thrd_sym="$INSTALL_HOME/.local/bin/throttled"
		if [[ ! -d $thrd_dir ]]; then
			if confirm "Install throttled?"; then # doesnt technically check whether it has already been installed
				apt-get install git build-essential python3-dev libdbus-glib-1-dev libgirepository1.0-dev libcairo2-dev python3-cairo-dev python3-venv python3-wheel -qq
				git clone https://github.com/erpalma/throttled.git
				./throttled/install.sh

				# stop thermald
				systemctl stop thermald.service
				systemctl disable thermald.service
				systemctl mask thermald.service

				#turn ./throttled.py in venv as cli
				if [[ ! -f $thrd_wrap ]]; then
					cat > $thrd_wrap << EOF
#!/bin/bash
exec "$thrd_dir/venv/bin/python" "$thrd_dir/throttled.py" "\$@"
EOF
					chmod +x $thrd_wrap
				else
					bold_yellow "throttled wrapper already exist in $thrd_wrap"
				fi

				if [[ ! -L $thrd_sym ]]; then
					ln -s $thrd_wrap $thrd_sym
				else
					bold_yellow "throttled symlink already exist in $thrd_sym"
				fi

				bold_yellow "Check throttled service via 'sudo systemctl status throttled'"
				bold_green "✅ throttled installed"
			fi
		else
			bold_green "✅ throttled is already installed."
		fi
	fi
else 
	bold_red "OS distro is not Debian or Ubuntu. No apps have been installed"
	exit 1
fi

# new shell (refresh) LAST AS ANYTHING AFTER WILL NOT RUN
cd $INSTALL_HOME
bold_yellow "Refresh bash: exec bash or source ~/.bashrc"
