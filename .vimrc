" line numbers
set nu
set relativenumber

" filetype
filetype on
filetype plugin on
filetype indent on

" folding
set foldmethod=indent
set foldlevel=99

" show tabs + spaces
set list
set listchars=space:·,tab:\|\-

" visual appearance
set ruler
set cursorline

" command line
set cmdheight=1
set wildmenu " command-line completion with visual menu
set history=500
set showcmd
set noshowmode

" status line
set statusline=
set statusline +=%5*%{&ff}%*            "file format
set statusline +=%3*\ %{''.(&fenc!=''?&fenc:&enc).''}      "Encoding
set statusline +=%3*%y%*                "file type
set statusline +=%4*\ %<%F%*            "full path
set statusline +=%2*%m%*                "modified flag
set statusline +=%1*%=%5l%*             "current line
set statusline +=%2*/%L%*               "total lines
set statusline +=%1*%4v\ %*             "virtual column number
set statusline +=%2*0x%04B\ %*          "character under cursor
set laststatus=2 " Always display the status line

" search patterns
set ignorecase
set smartcase " overrides ignorecase when search contains uppercase letters
set hlsearch
set incsearch " incremental search (when typing)

" syntax highlighting
syntax enable

" indent
set autoindent
set smartindent

" tabs
set softtabstop=0
set shiftwidth=4
set tabstop=4
set noexpandtab
" set expandtab " convert tabs into spaces, Ctrl-V + tab to use real tab

" misc
set autoread " updates file if changed outside of vim
set hid " switch buffers without saving current one
set clipboard=unnamedplus
set encoding=utf8
set t_Co=256

" maps
nmap oo o<Esc>k

" Vim-plug
" Install vim-plug if not found
if empty(glob('~/.vim/autoload/plug.vim'))
  silent !curl -fLo ~/.vim/autoload/plug.vim --create-dirs
    \ https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
endif

" Run PlugInstall if there are missing plugins
autocmd VimEnter * if len(filter(values(g:plugs), '!isdirectory(v:val.dir)'))
  \| PlugInstall --sync | source $MYVIMRC
\| endif

" ALE configs
let g:ale_linters = {'rust': ['analyzer', 'cargo'], 'python': ['flake8', 'pylint']}
let g:ale_fixers = {'rust': ['rustfmt'], 'python': ['black', 'isort']}

let g:ale_completion_enabled = 1
let g:ale_linters_explicit = 1
let g:ale_fix_on_save = 1

let g:ale_rust_cargo_check_tests = 1
let g:ale_rust_cargo_check_examples = 1
let g:ale_rust_cargo_use_clippy = executable('cargo-clippy')

let b:rust_default_edition = '2018'
let b:rust_edition = system('cargo get package.edition')
if v:shell_error > 0 || len(b:rust_edition) == 0
    let b:rust_edition = b:rust_default_edition
endif

let g:ale_rust_rustfmt_options = '--edition ' .. b:rust_edition

" Plugins
call plug#begin()

Plug 'andymass/vim-matchup'
Plug 'dense-analysis/ale'
Plug 'prettier/vim-prettier', {
    \ 'do': 'yarn install --frozen-lockfile --production',
    \ 'for': ['javascript', 'typescript', 'css', 'less', 'scss', 'json', 'graphql', 'markdown', 'vue', 'svelte', 'yaml', 'html'] }
Plug 'scrooloose/nerdtree'
Plug 'cocopon/iceberg.vim'

call plug#end()

" .rs files are recognised as rust not hercules
au BufRead,BufNewFile *.rs set filetype=rust

" checks for external changes when switching back to vim without panicking
au FocusGained,BufEnter * silent! checktime

" Powerline statusline
" for vim binding, it must be installed as a library not binary
set rtp+=/home/ethch/.local/share/powerline-venv/lib/python3.11/site-packages/powerline/bindings/vim

let g:airline#extensions#ale#enabled=1

" theme
set background=dark
colorscheme iceberg
