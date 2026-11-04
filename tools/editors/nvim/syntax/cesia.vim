" Cesia syntax, for Vim and Neovim.
if exists("b:current_syntax")
  finish
endif
syn keyword cesiaKeyword if else end for in while break return defn match struct interface then use
syn keyword cesiaOperator and or not
syn keyword cesiaConstant true false missing
syn match cesiaNumber "\<\d\+\(\.\d\+\)\?\>"
syn match cesiaFunction "\<\h\w*\ze("
syn match cesiaHole "\$\h\w*\|\$(.\{-})" contained
syn region cesiaString start=+"+ end=+"+ contains=cesiaHole
syn match cesiaComment "--.*$"
syn region cesiaComment start="(\*" end="\*)" contains=cesiaComment
hi def link cesiaKeyword Keyword
hi def link cesiaOperator Operator
hi def link cesiaConstant Constant
hi def link cesiaNumber Number
hi def link cesiaFunction Function
hi def link cesiaHole Special
hi def link cesiaString String
hi def link cesiaComment Comment
let b:current_syntax = "cesia"
