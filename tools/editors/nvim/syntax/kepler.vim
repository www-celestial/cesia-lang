" Kepler syntax, for Vim and Neovim.
if exists("b:current_syntax")
  finish
endif
syn keyword keplerKeyword if else end for in while break return defn match struct then use
syn keyword keplerOperator and or not
syn keyword keplerConstant true false missing
syn match keplerNumber "\<\d\+\(\.\d\+\)\?\>"
syn match keplerFunction "\<\h\w*\ze("
syn match keplerHole "\$\h\w*\|\$(.\{-})" contained
syn region keplerString start=+"+ end=+"+ contains=keplerHole
syn match keplerComment "--.*$"
hi def link keplerKeyword Keyword
hi def link keplerOperator Operator
hi def link keplerConstant Constant
hi def link keplerNumber Number
hi def link keplerFunction Function
hi def link keplerHole Special
hi def link keplerString String
hi def link keplerComment Comment
let b:current_syntax = "kepler"
