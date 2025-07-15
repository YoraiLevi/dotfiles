## !accessibilityModeEnabled

### Terminal Navigation

```json
{"command":"cursorWordEndRight","key":"ctrl+right","when":"textInputFocus && !accessibilityModeEnabled"},
{"command":"cursorWordLeft","key":"ctrl+left","when":"textInputFocus && !accessibilityModeEnabled"},
{"command":"cursorWordEndRightSelect","key":"ctrl+shift+right","when":"textInputFocus && !accessibilityModeEnabled"},
{"command":"cursorWordLeftSelect","key":"ctrl+shift+left","when":"textInputFocus && !accessibilityModeEnabled"},
```

```json
{"command":"workbench.action.terminal.scrollToNextCommand","key":"ctrl+down","when":"terminalFocus && terminalHasBeenCreated && !accessibilityModeEnabled || terminalFocus && terminalProcessSupported && !accessibilityModeEnabled || terminalFocus && terminalHasBeenCreated && terminalProcessSupported && !accessibilityModeEnabled"},
{"command":"workbench.action.terminal.scrollToNextCommand","key":"ctrl+down","when":"terminalFocus && terminalHasBeenCreated && !accessibilityModeEnabled || terminalFocus && terminalProcessSupported && !accessibilityModeEnabled"},
{"command":"workbench.action.terminal.scrollToPreviousCommand","key":"ctrl+up","when":"terminalFocus && terminalHasBeenCreated && !accessibilityModeEnabled || terminalFocus && terminalProcessSupported && !accessibilityModeEnabled || terminalFocus && terminalHasBeenCreated && terminalProcessSupported && !accessibilityModeEnabled"},
{"command":"workbench.action.terminal.scrollToPreviousCommand","key":"ctrl+up","when":"terminalFocus && terminalHasBeenCreated && !accessibilityModeEnabled || terminalFocus && terminalProcessSupported && !accessibilityModeEnabled"},
```

#### pwsh specific

`"config.terminal.integrated.suggest.enabled" : true`
`"config.terminal.integrated.shellIntegration.suggestEnabled": true` - Deprecated?

```json
{"command":"workbench.action.terminal.sendSequence","key":"alt+space","when":"terminalFocus && terminalShellIntegrationEnabled && !accessibilityModeEnabled && terminalShellType == 'pwsh'","args":{"text":"\u001b[24~b"}},
{"command":"workbench.action.terminal.sendSequence","key":"ctrl+space","when":"config.terminal.integrated.shellIntegration.suggestEnabled && terminalFocus && terminalShellIntegrationEnabled && !accessibilityModeEnabled && terminalShellType == 'pwsh'","args":{"text":"\u001b[24~e"}},
{"command":"workbench.action.terminal.sendSequence","key":"ctrl+space","when":"config.terminal.integrated.suggest.enabled && terminalFocus && terminalShellIntegrationEnabled && !accessibilityModeEnabled && terminalShellType == 'pwsh'","args":{"text":"\u001b[24~e"}},

{"command":"workbench.action.terminal.sendSequence","key":"ctrl+space","when":"terminalFocus && terminalShellIntegrationEnabled && !accessibilityModeEnabled && terminalShellType == 'pwsh'","args":{"text":"\u001b[24~a"}},
{"command":"workbench.action.terminal.sendSequence","key":"ctrl+v","when":"terminalFocus && !accessibilityModeEnabled && terminalShellType == 'pwsh'","args":{"text":"\u0016"}},
{"command":"workbench.action.terminal.sendSequence","key":"shift+enter","when":"terminalFocus && terminalShellIntegrationEnabled && !accessibilityModeEnabled && terminalShellType == 'pwsh'","args":{"text":"\u001b[24~c"}},
```

### Jupyter

TODO: No idea?

```json
{"command":"notebook.cell.chat.arrowOutDown","key":"ctrl+down","when":"inlineChatFocused && inlineChatInnerCursorLast && notebookCellChatFocused && !accessibilityModeEnabled && !notebookCellEditorFocused"},
{"command":"notebook.cell.chat.arrowOutUp","key":"ctrl+up","when":"inlineChatFocused && inlineChatInnerCursorFirst && notebookCellChatFocused && !accessibilityModeEnabled && !notebookCellEditorFocused"},
{"command":"notebook.cell.focusChatWidget","key":"ctrl+up","when":"editorTextFocus && inputFocus && notebookEditorFocused && !accessibilityModeEnabled && !isEmbeddedDiffEditor && notebookEditorCursorAtBoundary != 'bottom' && notebookEditorCursorAtBoundary != 'none'"},
{"command":"notebook.cell.focusNextChatWidget","key":"ctrl+down","when":"editorTextFocus && inputFocus && isCompositeNotebook && !accessibilityModeEnabled && !isEmbeddedDiffEditor && !notebookCellEditorFocused && notebookEditorCursorAtBoundary != 'none' && notebookEditorCursorAtBoundary != 'top' || editorTextFocus && inputFocus && notebookCellEditorFocused && !accessibilityModeEnabled && !isCompositeNotebook && !isEmbeddedDiffEditor && notebookEditorCursorAtBoundary != 'none' && notebookEditorCursorAtBoundary != 'top'"},
```

jupytyer up down between cells
`"config.notebook.navigation.allowNavigateToSurroundingCells": true`

```json
{"command":"notebook.focusNextEditor","key":"down","when":"config.notebook.navigation.allowNavigateToSurroundingCells && editorTextFocus && inputFocus && notebookEditorFocused && !accessibilityModeEnabled && !isEmbeddedDiffEditor && notebookEditorCursorAtBoundary != 'none' && notebookEditorCursorAtBoundary != 'top'"},
{"command":"notebook.focusNextEditor","key":"down","when":"config.notebook.navigation.allowNavigateToSurroundingCells && editorTextFocus && inputFocus && notebookEditorFocused && !accessibilityModeEnabled && notebookEditorCursorAtBoundary != 'none' && notebookEditorCursorAtBoundary != 'top'"},
{"command":"notebook.focusNextEditor","key":"down","when":"config.notebook.navigation.allowNavigateToSurroundingCells && notebookCursorNavigationMode && notebookEditorFocused && !accessibilityModeEnabled && !isEmbeddedDiffEditor && !notebookCellMarkdownEditMode && notebookCellType == 'markup'"},
{"command":"notebook.focusNextEditor","key":"down","when":"config.notebook.navigation.allowNavigateToSurroundingCells && notebookCursorNavigationMode && notebookEditorFocused && !accessibilityModeEnabled && !notebookCellMarkdownEditMode && notebookCellType == 'markup'"},
{"command":"notebook.focusPreviousEditor","key":"up","when":"config.notebook.navigation.allowNavigateToSurroundingCells && editorTextFocus && inputFocus && notebookEditorFocused && !accessibilityModeEnabled && !isEmbeddedDiffEditor && notebookEditorCursorAtBoundary != 'bottom' && notebookEditorCursorAtBoundary != 'none'"},
{"command":"notebook.focusPreviousEditor","key":"up","when":"config.notebook.navigation.allowNavigateToSurroundingCells && editorTextFocus && inputFocus && notebookEditorFocused && !accessibilityModeEnabled && notebookEditorCursorAtBoundary != 'bottom' && notebookEditorCursorAtBoundary != 'none'"},
{"command":"notebook.focusPreviousEditor","key":"up","when":"config.notebook.navigation.allowNavigateToSurroundingCells && notebookCursorNavigationMode && notebookEditorFocused && !accessibilityModeEnabled && !isEmbeddedDiffEditor && !notebookCellMarkdownEditMode && notebookCellType == 'markup'"},
{"command":"notebook.focusPreviousEditor","key":"up","when":"config.notebook.navigation.allowNavigateToSurroundingCells && notebookCursorNavigationMode && notebookEditorFocused && !accessibilityModeEnabled && !notebookCellMarkdownEditMode && notebookCellType == 'markup'"},
{"command":"workbench.action.terminal.runRecentCommand","key":"ctrl+alt+r","when":"terminalFocus && terminalHasBeenCreated && !accessibilityModeEnabled || terminalFocus && terminalProcessSupported && !accessibilityModeEnabled || terminalFocus && terminalHasBeenCreated && terminalProcessSupported && !accessibilityModeEnabled"},
{"command":"workbench.action.terminal.runRecentCommand","key":"ctrl+alt+r","when":"terminalFocus && terminalHasBeenCreated && !accessibilityModeEnabled || terminalFocus && terminalProcessSupported && !accessibilityModeEnabled"},
```

## accessibilityModeEnabled

TODO?

```json
{"command":"cursorWordAccessibilityLeft","key":"ctrl+left","when":"accessibilityModeEnabled && isWindows && textInputFocus && focusedView == 'workbench.panel.output'"},
{"command":"cursorWordAccessibilityLeftSelect","key":"ctrl+shift+left","when":"accessibilityModeEnabled && isWindows && textInputFocus && focusedView == 'workbench.panel.output'"},
{"command":"cursorWordAccessibilityRight","key":"ctrl+right","when":"accessibilityModeEnabled && isWindows && textInputFocus && focusedView == 'workbench.panel.output'"},
{"command":"cursorWordAccessibilityRightSelect","key":"ctrl+shift+right","when":"accessibilityModeEnabled && isWindows && textInputFocus && focusedView == 'workbench.panel.output'"},
{"command":"editor.action.nextCommentingRange","key":"ctrl+m ctrl+alt+down","when":"accessibilityModeEnabled && commentFocused || accessibilityModeEnabled && editorFocus || accessibilityHelpIsShown && accessibilityModeEnabled && accessibleViewCurrentProviderId == 'comments'"},
```

```json
{"command":"editor.action.previousCommentingRange","key":"ctrl+m ctrl+alt+up","when":"accessibilityModeEnabled && commentFocused || accessibilityModeEnabled && editorFocus || accessibilityHelpIsShown && accessibilityModeEnabled && accessibleViewCurrentProviderId == 'comments'"},
{"command":"notebook.focusNextEditor","key":"ctrl+pagedown","when":"accessibilityModeEnabled && notebookCellEditorFocused"},
{"command":"notebook.focusPreviousEditor","key":"ctrl+pageup","when":"accessibilityModeEnabled && notebookCellEditorFocused"},

{"command":"search.action.focusSearchFromResults","key":"ctrl+up","when":"accessibilityModeEnabled && searchViewletVisible || firstMatchFocus && searchViewletVisible"},

{"command":"workbench.action.terminal.focus","key":"ctrl+down","when":"accessibilityModeEnabled && accessibleViewOnLastLine && terminalHasBeenCreated && accessibleViewCurrentProviderId == 'terminal' || accessibilityModeEnabled && accessibleViewOnLastLine && terminalProcessSupported && accessibleViewCurrentProviderId == 'terminal'"},
{"command":"workbench.action.terminal.focusAccessibleBuffer","key":"alt+f2","when":"accessibilityModeEnabled && terminalFocus && terminalHasBeenCreated || accessibilityModeEnabled && terminalFocus && terminalProcessSupported"},
{"command":"workbench.action.terminal.focusAccessibleBuffer","key":"ctrl+up","when":"accessibilityModeEnabled && terminalFocus && terminalHasBeenCreated || accessibilityModeEnabled && terminalFocus && terminalProcessSupported"},
{"command":"workbench.action.terminal.focusAccessibleBuffer","key":"shift+tab","when":"accessibilityModeEnabled && terminalHasBeenCreated && terminalTabFocusMode && !terminalAccessibleBufferFocus || accessibilityModeEnabled && terminalProcessSupported && terminalTabFocusMode && !terminalAccessibleBufferFocus"},
{"command":"workbench.action.terminal.runRecentCommand","key":"ctrl+r","when":"accessibilityModeEnabled && terminalFocus && terminalHasBeenCreated || accessibilityModeEnabled && terminalFocus && terminalProcessSupported || accessibilityModeEnabled && accessibleViewIsShown && terminalHasBeenCreated && accessibleViewCurrentProviderId == 'terminal' || accessibilityModeEnabled && accessibleViewIsShown && terminalProcessSupported && accessibleViewCurrentProviderId == 'terminal'"},
{"command":"workbench.action.terminal.runRecentCommand","key":"ctrl+r","when":"accessibilityModeEnabled && terminalFocus && terminalHasBeenCreated || accessibilityModeEnabled && terminalFocus && terminalProcessSupported || accessibilityModeEnabled && terminalFocus && terminalHasBeenCreated && terminalProcessSupported"},
{"command":"workbench.action.terminal.sendSequence","key":"ctrl+alt+r","when":"accessibilityModeEnabled && terminalFocus","args":{"text":"\u0012"}},
```
