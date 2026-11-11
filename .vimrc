set nocompatible

" leader before any mapping is defined: space is reachable with either thumb
let mapleader = " "

" Vim links the system libpython3.12, but its embedded interpreter resolves
" `python3` from PATH and adopts conda's/venv's stdlib when one is active.
" Mixing that stdlib with the system libpython segfaults on `import ctypes`,
" which Powerline does at load time. Pin the stdlib to match the linkage.
let $PYTHONHOME = '/usr'

" ...but only for Vim's own interpreter: children inherit the environment, and
" any venv python (pyright-langserver, black, ...) dies instantly under
" PYTHONHOME=/usr with "Failed to import encodings module". Init the embedded
" interpreter here, then drop the variable before anything can spawn a child.
if has('python3')
    py3 pass
endif
unlet $PYTHONHOME

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
" powerline's plugin sets &statusline at startup; keep the plain one as the
" fallback only, so re-sourcing this file does not clobber it
if !exists('g:powerline_loaded')
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
endif
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
" next/previous buffer; vim has no native ]b/[b, count works like 2]b
nnoremap <silent> ]b :<C-u>execute 'bnext ' . v:count1<CR>
nnoremap <silent> [b :<C-u>execute 'bprevious ' . v:count1<CR>

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

" restart the LSP server of this buffer: picks up new deps, e.g. after `uv add`
" (vim-lsp here has no :LspRestart - servers start on BufReadPost, so stop + :edit)
function! s:lsp_restart() abort
    if &modified
        echohl WarningMsg
        echomsg 'LSP restart reloads the buffer, save it first'
        echohl None
        return
    endif
    silent! LspStopServer
    edit
endfunction
nnoremap <silent> <leader>lr :<C-u>call <SID>lsp_restart()<CR>

let g:lsp_diagnostics_enabled = 0

" pyright starts from whatever python3 is first in PATH (miniforge3 here) and it
" does not look for a .venv on its own, so imports from the project venv stay
" unresolved. Hand it the nearest venv of the buffer being opened instead.
" called both by vim-lsp-settings (name, key) and by vim-lsp (server_info)
function! s:pyright_settings(...) abort
    let l:analysis = {'useLibraryCodeForTypes': v:true}
    let l:dir = expand('%:p:h')
    while l:dir !=# '/'
        for l:name in ['.venv', 'venv', 'env']
            if executable(l:dir . '/' . l:name . '/bin/python')
                return {'python': {'venvPath': l:dir, 'venv': l:name, 'analysis': l:analysis}}
            endif
        endfor
        let l:dir = fnamemodify(l:dir, ':h')
    endwhile
    return {'python': {'analysis': l:analysis}}
endfunction

let g:lsp_settings = {'pyright-langserver': {'workspace_config': function('s:pyright_settings')}}

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
let s:candidates = glob(expand('~/.local/share/dotfiles-venv/lib/python3.*/site-packages'), 0, 1)

if !empty(s:candidates)
    let s:site_packages = s:candidates[0]

    if isdirectory(s:site_packages)
        " 1. Inject venv site-packages into Vim's Python sys.path first
        if has('python3')
            python3 << EOF
import sys, vim
site_packages = vim.eval('s:site_packages')
if site_packages and site_packages not in sys.path:
    sys.path.insert(0, site_packages)
EOF
        endif

        " 2. Add Powerline's vim binding to runtimepath so Vim auto-loads the plugin
        let s:powerline_vim = s:site_packages . '/powerline/bindings/vim'
        if isdirectory(s:powerline_vim) && stridx(&runtimepath, s:powerline_vim) < 0
            let &runtimepath .= ',' . fnameescape(s:powerline_vim)
        endif
    endif
endif

" wsl clipboard: WSLg already bridges the X11 clipboard to Windows.
" Piping yanks through clip.exe stores CRLF on the Windows side, which the
" bridge syncs back - that is the ^M you get from d-then-p.

" theme
set background=dark
if !empty(globpath(&runtimepath, 'colors/iceberg.vim'))
    colorscheme iceberg
endif
