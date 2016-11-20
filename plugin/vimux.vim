if exists("g:loaded_vimux") || &cp
  finish
endif
let g:loaded_vimux = 1

command -nargs=* VimuxRunCommand :call VimuxRunCommand(<args>)
command VimuxRunLastCommand :call VimuxRunLastCommand()
command VimuxCloseRunner :call VimuxCloseRunner()
command VimuxZoomRunner :call VimuxZoomRunner()
command VimuxInspectRunner :call VimuxInspectRunner()
command VimuxScrollUpInspect :call VimuxScrollUpInspect()
command VimuxScrollDownInspect :call VimuxScrollDownInspect()
command VimuxInterruptRunner :call VimuxInterruptRunner()
command -nargs=? VimuxPromptCommand :call VimuxPromptCommand(<args>)
command VimuxClearRunnerHistory :call VimuxClearRunnerHistory()
command VimuxTogglePane :call VimuxTogglePane()

function! VimuxRunCommandInDir(command, useFile)
    let l:file = ""
    if a:useFile ==# 1
        let l:file = shellescape(expand('%:t'), 1)
    endif
    call VimuxRunCommand("(cd ".shellescape(expand('%:p:h'), 1)." && ".a:command." ".l:file.")")
endfunction

function! VimuxRunLastCommand()
  if exists("g:VimuxRunnerIndex")
    call VimuxRunCommand(g:VimuxLastCommand)
  else
    echo "No last vimux command."
  endif
endfunction

function! VimuxRunCommand(command, ...)
  if !exists("g:VimuxRunnerID") || _VimuxHasRunner(g:VimuxRunnerID) == -1
    call VimuxOpenRunner()
  endif

  let l:autoreturn = 1
  if exists("a:1")
    let l:autoreturn = a:1
  endif

  let resetSequence = _VimuxOption("g:VimuxResetSequence", "q C-u")
  let g:VimuxLastCommand = a:command

  call VimuxSendKeys(resetSequence)
  call VimuxSendText(a:command)

  if l:autoreturn == 1
    call VimuxSendKeys("Enter")
  endif
endfunction

function! VimuxSendText(text)
  call VimuxSendKeys('"'.escape(a:text, '\"$').'"')
endfunction

function! VimuxSendKeys(keys)
  if exists("g:VimuxRunnerID")
    call _VimuxTmux("send-keys -t ".g:VimuxRunnerID." ".a:keys)
  else
    echo "No vimux runner pane/window. Create one with VimuxOpenRunner"
  endif
endfunction

function! VimuxOpenRunner()
  let nearestIndex = _VimuxNearestIndex()

  if _VimuxOption("g:VimuxUseNearest", 1) == 1 && nearestIndex != -1
	let g:VimuxRunnerID=substitute(_VimuxTmux("display-message -p -t '{next}' '#{pane_id}'"), '\n$', '', '')
    let g:VimuxRunnerIndex = nearestIndex
  else
    if _VimuxRunnerType() == "pane"
      let height = _VimuxOption("g:VimuxHeight", 20)
      let orientation = _VimuxOption("g:VimuxOrientation", "v")
      let command = "split-window -p ".height." -".orientation
    elseif _VimuxRunnerType() == "window"
      let command = "new-window"
    endif
	
	let command .= " -d -P -F '#{pane_id}'"

    let g:VimuxRunnerID=substitute(_VimuxTmux(command), '\n$', '', '')
	call VimuxUpdateRunnerIndex()
  endif
endfunction

function! VimuxUpdateRunnerIndex()
	if exists("g:VimuxRunnerID")
		let g:VimuxRunnerIndex=substitute(_VimuxTmux("display-message -p -t ".g:VimuxRunnerID." '#{pane_index}'"), '\n$', '', '')
	elseif
		unlet g:VimuxRunnerIndex
	endif
endfunction

function! VimuxCloseRunner()
  if exists("g:VimuxRunnerID")
    call _VimuxTmux("kill-pane -t ".g:VimuxRunnerID)
    unlet g:VimuxRunnerID
    unlet g:VimuxRunnerIndex
  endif
endfunction

function! VimuxTogglePane()
  if exists("g:VimuxRunnerID")
    if _VimuxRunnerType() == "window"
        call _VimuxTmux("join-pane -d -s ".g:VimuxRunnerID." -p "._VimuxOption("g:VimuxHeight", 20))
        let g:VimuxRunnerType = "pane"
    elseif _VimuxRunnerType() == "pane"
		call _VimuxTmux("break-pane -d -s ".g:VimuxRunnerID)
        let g:VimuxRunnerType = "window"
    endif
	call VimuxUpdateRunnerIndex()
  endif
endfunction

function! VimuxZoomRunner()
  if exists("g:VimuxRunnerID")
    if _VimuxRunnerType() == "pane"
      call _VimuxTmux("resize-pane -Z -t ".g:VimuxRunnerID)
    elseif _VimuxRunnerType() == "window"
      call _VimuxTmux("select-window -t ".g:VimuxRunnerID)
    endif
  endif
endfunction

function! VimuxInspectRunner()
  call _VimuxTmux("select-"._VimuxRunnerType()." -t ".g:VimuxRunnerID)
  call _VimuxTmux("copy-mode")
endfunction

function! VimuxScrollUpInspect()
  call VimuxInspectRunner()
  call _VimuxTmux("last-"._VimuxRunnerType())
  call VimuxSendKeys("C-u")
endfunction

function! VimuxScrollDownInspect()
  call VimuxInspectRunner()
  call _VimuxTmux("last-"._VimuxRunnerType())
  call VimuxSendKeys("C-d")
endfunction

function! VimuxInterruptRunner()
  call VimuxSendKeys("^c")
endfunction

function! VimuxClearRunnerHistory()
  if exists("g:VimuxRunnerID")
    call _VimuxTmux("clear-history -t ".g:VimuxRunnerID)
  endif
endfunction

function! VimuxPromptCommand(...)
  let command = a:0 == 1 ? a:1 : ""
  let l:command = input(_VimuxOption("g:VimuxPromptString", "Command? "), command)
  call VimuxRunCommand(l:command)
endfunction

function! _VimuxTmux(arguments)
  let l:command = _VimuxOption("g:VimuxTmuxCommand", "tmux")
  return system(l:command." ".a:arguments)
endfunction

function! _VimuxTmuxSession()
  return _VimuxTmuxProperty("#S")
endfunction

function! _VimuxNearestIndex()
  let views = split(_VimuxTmux("list-"._VimuxRunnerType()."s"), "\n")

  for view in views
    if match(view, "(active)") == -1
      return split(view, ":")[0]
    endif
  endfor

  return -1
endfunction

function! _VimuxRunnerType()
  return _VimuxOption("g:VimuxRunnerType", "pane")
endfunction

function! _VimuxOption(option, default)
  if exists(a:option)
    return eval(a:option)
  else
    return a:default
  endif
endfunction

function! _VimuxTmuxProperty(property, ...)
	let command = "display -p '".a:property."'"

	if exists("a:1")
		let command .=  " -t ".a:1
	endif

    return substitute(_VimuxTmux(command), '\n$', '', '')
endfunction

function! _VimuxHasRunner(id)
  return match(_VimuxTmux("list-panes -a -F '#{pane_id}'"), a:id)
endfunction
