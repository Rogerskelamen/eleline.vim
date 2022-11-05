" ============================================================================
" Filename: eleline.vim
" Author: theniceboy
" Fork: Rogerskelamen
" URL: https://github.com/theniceboy/eleline.vim
" License: MIT License
" =============================================================================
" set for script encode
scriptencoding utf-8
" If there is eleline exists or vim version is greater than 7.0, then exit
if exists('g:loaded_eleline') || v:version < 700
	finish
endif
let g:loaded_eleline = 1 " turn on eleline

let s:save_cpo = &cpoptions
set cpoptions&vim

" get the powerline_fonts
" if eleline_powerline_fonts does not exist then use
" airline_powerline_fonts(font = 1)
" if both not exist, then use font = 0
let s:font = get(g:, 'eleline_powerline_fonts', get(g:, 'airline_powerline_fonts', 0)) " s:font = 1
" use fn_icon if s:font is setted(use  if eleline_function_icon is not specified)
let s:fn_icon = s:font ? get(g:, 'eleline_function_icon', " \uf794 ") : ''
" whether running on gui
let s:gui = has('gui_running')
" whether running on Windows
let s:is_win = has('win32')
" set git branch command(diff cmd for diff OS)
" win: cmd /c git branch
" others: bash -c git branch
let s:git_branch_cmd = add(s:is_win ? ['cmd', '/c'] : ['bash', '-c'], 'git branch')
" set git symbol to \ue0a0 if powerline_fonts exists
let s:git_branch_symbol = s:font ? " \ue0a0 " : ' Git:'
let s:git_branch_star_substituted = s:font ? "  \ue0a0" : '  Git:'
let s:jobs = {}

" display number of current buffer and window
function! ElelineBufnrWinnr() abort
	let l:bufnr = bufnr('%') " find current buffer
	if !s:gui
		" transform to circled num: nr2char(9311 + l:bufnr)①
		let l:bufnr = l:bufnr > 20 ? l:bufnr : nr2char(9311 + l:bufnr).' '
	endif
	return '  '.l:bufnr.' ❖ '.winnr().' '
endfunction

" tip for current buffer(sum of bufs)
function! ElelineTotalBuf() abort
	return '[TOT:'.len(filter(range(1, bufnr('$')), 'buflisted(v:val)')).']'
endfunction

" tip for paste status
function! ElelinePaste() abort
	return &paste ? 'PASTE ' : ''
endfunction

" display fileSize
function! ElelineFsize(f) abort
	let l:size = getfsize(expand(a:f))
	" not a file | can't find file | file is too big -> don't display size
	if l:size == 0 || l:size == -1 || l:size == -2
		return ''
	endif
	if l:size < 1024
		let size = l:size.' bytes'
	elseif l:size < 1024*1024
		let size = printf('%.1f', l:size/1024.0) . 'K'
	elseif l:size < 1024*1024*1024
		let size = printf('%.1f', l:size/1024.0/1024.0) . 'M'
	else
		let size = printf('%.1f', l:size/1024.0/1024.0/1024.0) . 'G'
	endif
	return ' '.size.' '
endfunction

" display fileName
function! ElelineCurFname() abort
	return &filetype ==# 'startify' ? '' : '  '.expand('%:p:t').' '
endfunction

" display error info
function! ElelineError() abort
	if exists('g:loaded_ale')
		let s:ale_counts = ale#statusline#Count(bufnr(''))
		return s:ale_counts[0] == 0 ? '' : '•'.s:ale_counts[0].' '
	endif
	return ''
endfunction

" display warning info
function! ElelineWarning() abort
	if exists('g:loaded_ale')
		" Ensure ElelineWarning() is called after ElelineError() so that s:ale_counts can be reused.
		return s:ale_counts[1] == 0 ? '' : '•'.s:ale_counts[1].' '
	endif
	return ''
endfunction

" tip for readonly
function! ElelineReadonly() abort
  if !&readonly | return '' |endif
  return "   "
endfunction

" check if it's tmp file or startify plugin etc.
function! s:is_tmp_file() abort
	if !empty(&buftype)
		\ || index(['startify', 'gitcommit', 'coc-explorer', 'nerdtree'], &filetype) > -1
		\ || expand('%:p') =~# '^/tmp'
		return 1
	else
		return 0
	endif
endfunction

" Reference: https://github.com/chemzqm/vimrc/blob/master/statusline.vim
function! ElelineGitBranch(...) abort
	if s:is_tmp_file() | return '' | endif
	let reload = get(a:, 1, 0) == 1 | " get the second arg
	if exists('b:eleline_branch') && !reload | return b:eleline_branch | endif
	if !exists('*FugitiveExtractGitDir') | return '' | endif
	let dir = exists('b:git_dir') ? b:git_dir : FugitiveExtractGitDir(resolve(expand('%:p'))) | " get git hidden dir .git
	if empty(dir) | return '' | endif
	let b:git_dir = dir
	let roots = values(s:jobs)
	let root = fnamemodify(dir, ':h') " get cwd for jobstart
	if index(roots, root) >= 0 | return '' | endif

	let argv = add(has('win32') ? ['cmd', '/c']: ['bash', '-c'], 'git branch')
	if exists('*job_start')
		let job = job_start(s:git_branch_cmd, {'out_io': 'pipe', 'err_io':'null', 'out_cb': function('s:out_cb')})
		if job_status(job) ==# 'fail' | return '' | endif
		let s:cwd = root
		let job_id = matchstr(job, '\d\+')
		let s:jobs[job_id] = root
	elseif exists('*jobstart')
		let job_id = jobstart(s:git_branch_cmd, {
			\ 'cwd': root,
			\ 'stdout_buffered': v:true,
			\ 'stderr_buffered': v:true,
			\ 'on_exit': function('s:on_exit')
			\})
		if job_id == 0 || job_id == -1 | return '' | endif
		let s:jobs[job_id] = root
	" if fugitive exists
	elseif exists('g:loaded_fugitive')
		let l:head = fugitive#head()
		return empty(l:head) ? '' : s:git_branch_symbol.l:head . ' '
	endif

	return ''
endfunction

function! s:out_cb(channel, message) abort
	if a:message =~# '^* '
		let l:job_id = ch_info(a:channel)['id']
		if !has_key(s:jobs, l:job_id) | return | endif
		let l:branch = substitute(a:message, '*', s:git_branch_star_substituted, '')
		call s:SetGitBranch(s:cwd, l:branch.' ')
		call remove(s:jobs, l:job_id)
	endif
endfunction

function! s:on_exit(job_id, data, _event) dict abort
	if !has_key(s:jobs, a:job_id) | return | endif
	if v:dying | return | endif
	let l:cur_branch = join(filter(self.stdout, 'v:val =~# "*"'))
	if !empty(l:cur_branch)
		let l:branch = substitute(l:cur_branch, '*', s:git_branch_star_substituted, '')
		call s:SetGitBranch(self.cwd, l:branch.' ')
	else
		let err = join(self.stderr)
		if !empty(err) | echoerr err | endif
	endif
	call remove(s:jobs, a:job_id)
endfunction

function! s:SetGitBranch(root, str) abort
	let buf_list = filter(range(1, bufnr('$')), 'bufexists(v:val)') | " get all bufs
	let root = a:root
	for nr in buf_list
		let path = fnamemodify(bufname(nr), ':p')
		if match(path, root) >= 0
			call setbufvar(nr, 'eleline_branch', a:str)
		endif
	endfor
	redraws!
endfunction

" tip for git status
function! ElelineGitStatus() abort
	let l:summary = [0, 0, 0] " three opt: add, modified, delete
	if exists('b:sy')
		let l:summary = b:sy.stats
	elseif exists('b:gitgutter.summary')
		let l:summary = b:gitgutter.summary
	endif
	if max(l:summary) > 0
		return '+'.l:summary[0].' ~'.l:summary[1].' -'.l:summary[2].' '
	endif
	return ''
endfunction

" tip for loading lsp
function! ElelineLCN() abort
	if !exists('g:LanguageClient_loaded') | return '' | endif
	return eleline#LanguageClientNeovim()
endfunction

function! ElelineVista() abort
	return !empty(get(b:, 'vista_nearest_method_or_function', '')) ? s:fn_icon.b:vista_nearest_method_or_function : ''
endfunction

" tip for coc
function! ElelineCoc() abort
	if s:is_tmp_file() | return '' | endif
	if get(g:, 'coc_enabled', 0) | return coc#status().' ' | endif
	return '' | " return nothing if anything can't match
endfunction

" display scroll
function! ElelineScroll() abort
	if !exists("*ScrollStatus") | return '' | endif
	return ScrollStatus()
endfunction

" https://github.com/liuchengxu/eleline.vim/wiki
function! s:StatusLine() abort
	function! s:def(fn) abort
		return printf('%%#%s#%%{%s()}%%*', a:fn, a:fn)
	endfunction
	let l:bufnr_winnr = s:def('ElelineBufnrWinnr')
	let l:paste = s:def('ElelinePaste')
	let l:curfname = s:def('ElelineCurFname').'%m'.s:def('ElelineReadonly')
	let l:branch = s:def('ElelineGitBranch')
	let l:status = s:def('ElelineGitStatus')
	let l:error = s:def('ElelineError')
	let l:warning = s:def('ElelineWarning')
	let l:tags = '%{exists("b:gutentags_files") ? gutentags#statusline() : ""} '
	let l:lcn = '%{ElelineLCN()}'
	let l:coc = '%{ElelineCoc()}'
	let l:scroll = '%{ElelineScroll()}'
	let l:vista = '%#ElelineVista#%{ElelineVista()}%*'
	let l:prefix = l:bufnr_winnr.l:paste
	if get(g:, 'eleline_slim', 0)
		return l:prefix.'%<'.l:common
	endif
	let l:tot = s:def('ElelineTotalBuf')
	let l:fsize = '%#ElelineFsize#%{ElelineFsize(@%)}'
	let l:m_r_f = '%#Eleline7# %y %*'
	let l:pos = '%#Eleline8# '.(s:font?"\ue0a1":'').'%l/%L:%c%V '
	let l:enc = ' %{&fenc != "" ? &fenc : &enc} | %{&bomb ? ",BOM " : ""}'
	let l:ff = '%{&ff} %*'
	let l:pct = '%#Eleline9# %P %*'
	if l:scroll != ''
		let l:pct = ''
		let l:scroll = '%#Eleline7#%*'.l:scroll
	endif
	let l:common = l:paste.l:curfname.l:branch.' '.l:status.l:error.l:warning.l:tags.l:lcn.l:coc.l:vista
	return l:common.'%='.l:m_r_f.l:pos.l:scroll.l:fsize " .l:enc.l:ff.l:pct
endfunction

let s:colors = {
	\   140 : '#af87d7', 149 : '#99cc66', 160 : '#d70000',
	\   171 : '#d75fd7', 178 : '#ffbb7d', 184 : '#ffe920',
	\   208 : '#ff8700', 232 : '#333300', 197 : '#cc0033',
	\   214 : '#ffff66', 124 : '#af3a03', 172 : '#b57614',
	\   32  : '#3a81c3', 89  : '#6c3163', 150 : '#a7c080',
	\   179 : '#d3c6aa', 110 : '#e67e80', 116 : '#e69875',
	\   108 : '#83c092', 175 : '#d699b6',
	\
	\   235 : '#262626', 236 : '#303030', 237 : '#3a3a3a',
	\   238 : '#444444', 239 : '#4e4e4e', 240 : '#585858',
	\   241 : '#606060', 242 : '#666666', 243 : '#767676',
	\   244 : '#808080', 245 : '#8a8a8a', 246 : '#949494',
	\   247 : '#9e9e9e', 248 : '#a8a8a8', 249 : '#b2b2b2',
	\   250 : '#bcbcbc', 251 : '#c6c6c6', 252 : '#d0d0d0',
	\   253 : '#dadada', 254 : '#e4e4e4', 255 : '#eeeeee',
	\ }

function! s:extract(group, what, ...) abort
	if a:0 == 1
		return synIDattr(synIDtrans(hlID(a:group)), a:what, a:1)
	else
		return synIDattr(synIDtrans(hlID(a:group)), a:what)
	endif
endfunction

" whether to set eleline_background
if !exists('g:eleline_background')
	let s:normal_bg = s:extract('Normal', 'bg', 'cterm')
	if s:normal_bg >= 233 && s:normal_bg <= 243
		let s:bg = s:normal_bg
	else
		let s:bg = 235 | " set default bg to 235
	endif
else
	let s:bg = g:eleline_background
endif

" Don't change in gui mode
if has('termguicolors') && &termguicolors
	let s:bg = 235
endif

" set color for a certain tip
function! s:hi(group, dark, light, ...) abort
	let [fg, bg] = &bg ==# 'dark' ? a:dark : a:light

	if empty(bg) && &bg ==# 'light' | " if light then reverse
		let reverse = s:extract('StatusLine', 'reverse')
		let ctermbg = s:extract('StatusLine', reverse ? 'fg' : 'bg', 'cterm')
		let guibg = s:extract('StatusLine', reverse ? 'fg': 'bg' , 'gui')
	else
		let ctermbg = bg
		let guibg = s:colors[bg]
	endif
	" change the tip color display
	execute printf('hi %s ctermfg=%d guifg=%s ctermbg=%d guibg=%s',
								\ a:group, fg, s:colors[fg], ctermbg, guibg)
	if a:0 == 1
		execute printf('hi %s cterm=%s gui=%s', a:group, a:1, a:1)
	endif
endfunction

" set color for tips
function! s:hi_statusline() abort
	call s:hi('ElelineBufnrWinnr' , [232 , 178]    , [89  , ''])
	call s:hi('ElelineTotalBuf'   , [178 , s:bg+8] , [240 , ''])
	call s:hi('ElelinePaste'      , [232 , 178]    , [232 , 178]    , 'bold')
	call s:hi('ElelineFsize'      , [253 , s:bg+8] , [235 , ''])
	call s:hi('ElelineCurFname'   , [236 , 150]    , [171 , '']     , 'bold')
	call s:hi('ElelineGitBranch'  , [184 , s:bg+2] , [89  , '']     , 'bold')
	call s:hi('ElelineGitStatus'  , [208 , s:bg+2] , [89  , ''])
	call s:hi('ElelineError'      , [197 , s:bg+2] , [197 , ''])
	call s:hi('ElelineWarning'    , [214 , s:bg+2] , [214 , ''])
	call s:hi('ElelineVista'      , [149 , s:bg+2] , [149 , ''])
	call s:hi('ElelineReadonly'   , [178 , s:bg+2] , [178 , '']     , 'bold')

	if &bg ==# 'dark'
		call s:hi('StatusLine' , [150 , s:bg+2], [150, ''] , 'none')
	endif

	call s:hi('Eleline7'      , [249 , s:bg+3], [237, ''] )
	call s:hi('Eleline8'      , [250 , s:bg+5], [238, ''] )
	call s:hi('Eleline9'      , [251 , s:bg+5], [239, ''] )
endfunction

" set for insertmode color
function! s:InsertStatuslineColor(mode) abort
	if a:mode ==# 'i'
		call s:hi('ElelineCurFname' , [232, 179], [232, 179])
	elseif a:mode ==# 'v'
		call s:hi('ElelineCurFname' , [232, 110], [232, 110])
	elseif a:mode ==# 'r'
		call s:hi('ElelineCurFname' , [232, 116] , [232, 116])
	else
		call s:hi('ElelineCurFname' , [232, 178], [89, ''])
	endif
	redraw!
endfunction

" Note that the "%!" expression is evaluated in the context of the
" current window and buffer, while %{} items are evaluated in the
" context of the window that the statusline belongs to.
function! s:SetStatusLine(...) abort
	call ElelineGitBranch(1)
	let &l:statusline = s:StatusLine()
	" User-defined highlightings shoule be put after colorscheme command.
	call s:hi_statusline()
	call s:DetectModeChange()
endfunction

if exists('*timer_start')
	call timer_start(100, function('s:SetStatusLine'))
else
	call s:SetStatusLine()
endif

function! s:DetectModeChange() abort
	if mode() ==# 'n'
		call s:hi('ElelineCurFname' , [236, 150], [89, ''])
	elseif mode() ==# 'i'
		call s:hi('ElelineCurFname' , [232, 179], [232, 179])
	elseif mode() ==# 'R'
		call s:hi('ElelineCurFname' , [232, 116] , [232, 116])
	elseif mode() ==# 'c'
		call s:hi('ElelineCurFname' , [232, 108] , [232, 108])
	elseif mode() ==# 't'
		call s:hi('ElelineCurFname' , [232, 175] , [232, 175])
	else | " for visual mode
		call s:hi('ElelineCurFname' , [232, 110], [232, 110])
	endif
endfunction

augroup eleline
	autocmd!
	autocmd User GitGutter,Startified,LanguageClientStarted call s:SetStatusLine()
	" Change colors for insert mode
	autocmd InsertLeave * call s:hi('ElelineCurFname', [236, 150], [89, ''])
	autocmd InsertEnter,InsertChange,ModeChanged * call s:DetectModeChange()
	autocmd BufWinEnter,ShellCmdPost,BufWritePost * call s:SetStatusLine()
	autocmd FileChangedShellPost,ColorScheme * call s:SetStatusLine()
	autocmd FileReadPre,ShellCmdPost,FileWritePost * call s:SetStatusLine()
augroup END

let &cpoptions = s:save_cpo
unlet s:save_cpo
