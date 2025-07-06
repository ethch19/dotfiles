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
	if command -v "$1" &> /dev/null; then
		bold_green "✅ $1 is already installed."
		return 0
	else
		return 1
	fi
}

cur_dir=$(pwd)
no_files="$(ls -1q -log | wc -l)"

if [[ $cur_dir != *"dotfiles"* ]]; then
	bold_red "Not in dotfiles directory"
	return 1
fi
default_echo "Number of dotfiles: $no_files"

# symlink creation
home=(".tmux.conf" ".vimrc" "ethch.omp.toml")
dotconfig=("powerline")
directory=( "$HOME" "$HOME/.config")
objects=( "home[@]" "dotconfig[@]") 

if confirm "Install Wayland config?"; then
	home+=("greetd_config.toml")
	dotconfig+=("sway" "waybar" "fuzzel")
fi

if confirm "Install t480 throttled config?"; then 
	home+=("throttled.conf")
	throttledvar=1
fi

mkdir -p ~/.config

for index in ${!directory[@]}; do
	dir="${directory[$index]}"
	for obj in ${!objects[$index]}; do 
		if [[ -f "$obj" ]]; then
			if [[ ! -f "$dir/$obj" ]]; then
				# default_echo "No current $obj file in $dir"
				ln -s "$cur_dir/$obj" "$dir/$obj"
				bold_green "🔗 $dir/$obj symlink created"
			else bold_yellow "$obj symlink in $dir already exists"
			fi
		elif [[ -d "$obj" ]]; then
			if [[ ! -d "$dir/$obj" ]]; then
				if [[ -L "$dir/$obj" ]]; then
					bold_yellow "$obj symlink in $dir already exists"
				else
					ln -s "$cur_dir/$obj" "$dir/$obj"
					bold_green "🔗 $dir/$obj symlink created"
				fi
			else bold_yellow "$obj directory in $dir already exists"
			fi
		else bold_red "Invalid file/directory: $obj"
		fi
	done
done
bold_green "🔗 All symlinks created"

if ! confirm "Install apps used in config?"; then
	return 1
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
	cd $HOME
	sudo apt-get update -qq && sudo apt-get upgrade -qq

	# This is added prior to oh-my-posh line
	# Add ~/.local/bin into PATH
	if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
		echo 'export PATH=$PATH:$HOME/.local/bin' >> ~/.bashrc
	fi

	# git + vim build tools
	if ! cmd_exist "git"; then
		sudo apt-get install git make clang libtool-bin libpython3-dev libncurses-dev -qq
		bold_green "✅ git installed"
	fi

	# vim
	if ! cmd_exist "vim"; then
		git clone https://github.com/vim/vim.git
		cd vim/src
		./configure --with-features=huge --enable-python3interp
		make -s
		sudo make -s install
		bold_green "✅ vim installed"
	fi

	# tmux
	if ! cmd_exist "tmux"; then
		sudo apt-get install tmux -qq
		bold_green "✅ tmux installed"
	fi

	# powerline
	if ! cmd_exist "powerline"; then
		sudo apt-get install python3-full python3-pip -qq 
		venvpath="$HOME/.local/share/powerline-venv"
		python3 -m venv --upgrade-deps $venvpath
		source $venvpath/bin/activate
		pip install powerline-status
		deactivate
		mkdir -p $HOME/.local/bin
		ln -s $venvpath/bin/powerline ~/.local/bin/powerline
		vimrtp=$(find "${venvpath}" -path "*powerline/bindings/vim")
		if [ -z "$vimrtp" ]; then
			bold_red "ERROR: Could not find the Powerline vim bindings path. Installation failed."
			return 1 
		fi
		bold_yellow "As powerline is installed via venv as a library at $venvpath, check that .vimrc contains this line:\nset rtp+=$vimrtp"
		sudo apt-get install fontconfig -qq
		wget -q https://github.com/powerline/powerline/raw/develop/font/PowerlineSymbols.otf
		wget -q https://github.com/powerline/powerline/raw/develop/font/10-powerline-symbols.conf
		mkdir -p $HOME/.local/share/fonts
		mv PowerlineSymbols.otf $HOME/.local/share/fonts/
		chmod 644 $HOME/.local/share/fonts/PowerlineSymbols.otf
		sudo fc-cache -vf $HOME/.local/share/fonts/
		mkdir -p $HOME/.config/fontconfig/conf.d
		mv 10-powerline-symbols.conf $HOME/.config/fontconfig/conf.d/
		chmod 644 $HOME/.config/fontconfig/conf.d/10-powerline-symbols.conf
		bold_yellow "If using WSL on Windows Powershell, the font should be installed on Windows separately."
		bold_green "✅ powerline installed"
	fi

	# curl
	if ! cmd_exist "curl"; then
		sudo apt-get install curl -qq
	fi

	# omp
	if ! cmd_exist "oh-my-posh"; then
		sudo apt-get install unzip -qq
		curl -s https://ohmyposh.dev/install.sh | bash -s
		oh-my-posh font install literationmono
		echo 'eval "$(oh-my-posh init bash --config ~/ethch.omp.toml)"' >> $HOME/.bashrc
		default_echo "Oh-my-posh bashrc added"
		bold_green "✅ oh-my-posh installed"	
	fi
	

	# wayland
	if [[ $waylandvar == [yY] ]]; then
		bold_yellow "Currently Wayland apps are not supported, as they all require building the binary manually. Do this yourself"
		bold_yellow "Apps not installed: sway,  waybar, fuzzel, greetd (+ tuigreet)"
	fi

	# throttled
	if (( throttledvar )); then
		if cmd_exist "throttled"; then # remember to add !, currently removed
			if confirm "Install throttled?"; then
				sudo apt-get install git build-essential python3-dev libdbus-glib-1-dev libgirepository1.0-dev libcairo2-dev python3-cairo-dev python3-venv python3-wheel -qq
				git clone https://github.com/erpalma/throttled.git
				sudo ./throttled/install.sh

				# stop thermald
				sudo systemctl stop thermald.service
				sudo systemctl disable thermald.service
				sudo systemctl mask thermald.service

				bold_yellow "Check throttled service via 'systemctl status throttled'"
				bold_green "✅ throttled installed"
			fi
		fi
	fi
else 
	bold_red "OS distro is not Debian or Ubuntu. No apps have been installed"
	return 1
fi

# new shell (refresh) LAST AS ANYTHING AFTER WILL NOT RUN
cd $HOME
bold_yellow "Refresh bash: exec bash or source ~/.bashrc"
