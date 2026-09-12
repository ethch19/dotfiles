set nocompatible
" line numbers
set number
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
set softtabstop=4
set shiftwidth=4
set tabstop=4
set expandtab 

" misc
set autoread " updates file if changed outside of vim
set hid " switch buffers without saving current one
set clipboard=unnamedplus
set encoding=utf8
set t_Co=256
set backupcopy=yes " prevent symlinkg from breaking when saving

" maps
nmap oo o<Esc>k

" Vim-plug
" Install vim-plug if not found
if empty(glob('~/.vim/autoload/plug.vim'))
  silent !curl -fLo ~/.vim/autoload/plug.vim --create-dirs
    \ https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
endif

" ALE configs
let g:ale_linters = {'rust': ['analyzer', 'cargo'], 'python': ['ruff']}
let g:ale_fixers = {'rust': ['rustfmt'], 'python': ['ruff', 'black']}

let g:ale_linters_explicit = 1
let g:ale_fix_on_save = 1
let g:ale_completion_enabled = 0
let g:ale_disable_lsp = 1

let g:ale_python_ruff_options = '--line-length 88 --ignore E501'

let g:ale_rust_cargo_check_tests = 1
let g:ale_rust_cargo_check_examples = 1
let g:ale_rust_cargo_use_clippy = executable('cargo-clippy')

let b:rust_default_edition = '2018'
let b:rust_edition = system('cargo get package.edition')
if v:shell_error > 0 || len(b:rust_edition) == 0
    let b:rust_edition = b:rust_default_edition
endif

let g:ale_rust_rustfmt_options = '--edition ' .. b:rust_edition

" vim-lsp config
inoremap <expr> <Tab>   pumvisible() ? "\<C-n>" : "\<Tab>"
inoremap <expr> <S-Tab> pumvisible() ? "\<C-p>" : "\<S-Tab>"
inoremap <expr> <cr>    pumvisible() ? asyncomplete#close_popup() : "\<cr>"

function! s:on_lsp_buffer_enabled() abort
    setlocal omnifunc=lsp#complete
    setlocal signcolumn=yes

    " Let Ctrl-] jump using LSP definition
    if exists('+tagfunc') | setlocal tagfunc=lsp#tagfunc | endif

    " Navigation
    nmap <buffer> gd <plug>(lsp-definition)
    nmap <buffer> gt <plug>(lsp-type-definition)
    nmap <buffer> gi <plug>(lsp-implementation)
    nmap <buffer> gr <plug>(lsp-references)
    nmap <buffer> gs <plug>(lsp-document-symbol-search)
    nmap <buffer> gS <plug>(lsp-workspace-symbol-search)

    " Hover & Floating Doc Scroll
    nmap <buffer> K  <plug>(lsp-hover)
    nnoremap <buffer> <expr><c-f> lsp#scroll(+4)
    nnoremap <buffer> <expr><c-d> lsp#scroll(-4)

    " Actions & Diagnostics
    nmap <buffer> <leader>rn <plug>(lsp-rename)
    nmap <buffer> [g <plug>(lsp-previous-diagnostic)
    nmap <buffer> ]g <plug>(lsp-next-diagnostic)
endfunction

augroup lsp_install
    autocmd!
    autocmd User lsp_buffer_enabled call s:on_lsp_buffer_enabled()
augroup END

let g:lsp_diagnostics_enabled = 0

" Plugins
call plug#begin()

Plug 'andymass/vim-matchup'
Plug 'dense-analysis/ale'
Plug 'prettier/vim-prettier', {
    \ 'do': 'npm install --omit=dev',
    \ 'for': ['javascript', 'typescript', 'css', 'less', 'scss', 'json', 'graphql', 'markdown', 'vue', 'svelte', 'yaml', 'html'] }
Plug 'scrooloose/nerdtree'
Plug 'cocopon/iceberg.vim'
Plug 'prabirshrestha/vim-lsp'
Plug 'mattn/vim-lsp-settings'
Plug 'prabirshrestha/asyncomplete.vim'
Plug 'prabirshrestha/asyncomplete-lsp.vim'

call plug#end()

" .rs files are recognised as rust not hercules
au BufRead,BufNewFile *.rs set filetype=rust

" checks for external changes when switching back to vim without panicking
au FocusGained,BufEnter * silent! checktime

" Powerline statusline
" for vim binding, it must be installed as a library not binary
let g:enable_powerline_vim = get(g:, 'enable_powerline_vim', 1)

if g:enable_powerline_vim
    let $PYTHONHOME = ''
    let $PYTHONPATH = ''

    let s:powerline_site_packages = glob(
                \ expand('~/.local/share/powerline-venv/lib/python3.*/site-packages'),
                \ 1)
    let s:powerline_python = expand('~/.local/share/powerline-venv/bin/python')
    let s:powerline_python_prefix = ''

    if executable(s:powerline_python)
        let s:powerline_python_prefix = substitute(
                    \ system(shellescape(s:powerline_python)
                    \ . ' -c '
                    \ . shellescape('import sys; print(sys.base_prefix)')),
                    \ '\n\+$', '', '')
    endif

    if !empty(s:powerline_python_prefix)
        let $PYTHONHOME = s:powerline_python_prefix
    endif

    if has('python3')
                \ && !empty(s:powerline_site_packages)
                \ && filereadable(s:powerline_site_packages . '/powerline/__init__.py')
                \ && !empty(s:powerline_python_prefix)

        python3 import sys

        if py3eval('sys.prefix') ==# s:powerline_python_prefix
            execute 'python3 import sys; sys.path.insert(0, '
                        \ . string(s:powerline_site_packages) . ')'

            python3 from powerline.vim import setup as powerline_setup
            python3 powerline_setup()
            python3 del powerline_setup
        else
            echohl WarningMsg
            echomsg 'Powerline disabled: Vim Python does not match the Powerline virtualenv.'
            echohl None
        endif
    endif
endif

" theme
set background=dark
if !empty(globpath(&runtimepath, 'colors/iceberg.vim'))
    colorscheme iceberg
endif