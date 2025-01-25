#!/bin/bash

cur_dir=$(pwd)
no_files="$(ls -1q -log | wc -l)"

if [[ $cur_dir != *"dotfiles"* ]]; then
	echo "Not in dotfiles directory"
	return 2
fi
echo "Number of dotfiles: $no_files"

# symlink creation
home=(".tmux.conf" ".vimrc" "ethch.omp.toml")
dotconfig=("powerline")
directory=( "$HOME" "$HOME/.config")
objects=( "home[@]" "dotconfig[@]") 

for index in ${!directory[@]}; do
	dir="${directory[$index]}"
	for obj in ${!objects[$index]}; do 
		if [[ -d "$obj" ]]; then
			if [[ ! -d "$dir/$obj" ]]; then
				echo "No current $obj directory in $dir"
					echo "Creating symlink: $dir/$obj"
					ln -s "$cur_dir/$obj" "$HOME/$obj"
			else echo "Current $obj directory in $dir already exists"
			fi
		elif [[ -f "$obj" ]]; then
			if [[ ! -f "$dir/$obj" ]]; then
				echo "No current $obj file in $dir"
					echo "Creating symlink: $dir/$obj"
					ln -s "$cur_dir/$obj" "$HOME/$obj"
			else echo "Current $obj file in $dir already exists"
			fi
		else echo "Invalid file/directory: $obj"
		fi
	done
done

# oh-my-posh bashrc addition
if [[ $1 = "-omp" ]]; then
	echo 'eval "$(oh-my-posh init bash --config ~/ethch.omp.toml)"' >> $HOME/.bashrc
	echo "Oh-my-posh bashrc added"
fi
