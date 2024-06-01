set clipboard=unnamedplus
set number

set history=500

filetype plugin on
filetype indent on

set autoread
au FocusGained,BufEnter * silent! checktime

set wildmenu

set ruler
set cmdheight=1
set hid

set cursorline

set ignorecase
set smartcase
set hlsearch
set incsearch

syntax enable

set encoding=utf8

set expandtab
set smarttab
set shiftwidth=4
set tabstop=4

let data_dir = has('nvim') ? stdpath('data') . '/site' : '~/.vim'
if empty(glob(data_dir . '/autoload/plug.vim'))
  silent execute '!curl -fLo '.data_dir.'/autoload/plug.vim --create-dirs  https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim'
  autocmd VimEnter * PlugInstall --sync | source $MYVIMRC
endif
