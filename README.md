# xylene.nvim

*For that one time where you need to explore your project's architecture*

Wip file tree plugin inspired by oil.nvim and carbon.nvim

![image](https://github.com/user-attachments/assets/8a51422d-f508-46fb-9831-f1cfc3c72b21)

<!--toc:start-->
- [xylene.nvim](#xylenenvim)
  - [Philosophy](#philosophy)
  - [Features](#features)
  - [Usage](#usage)
    - [Keymaps](#keymaps)
    - [User commands](#user-commands)
<!--toc:end-->

## Philosophy

- Minimalism
- Designed to be used with other FS plugins, I recommend [oil.nvim](https://github.com/stevearc/oil.nvim)
- Fast, navigating should feel instant


## Features
- [x] Navigating like a buffer
- [x] Subsequent empty directories are flattened into one line
- [x] Incremental rerendering of tree
- [x] `Xylene!` opens xylene with the current file already opened
- [x] Icons
- [ ] Symlink support
- [ ] Search for a directory with telescope and open it
- [ ] Execute any code with files / directories (for example open currently hovering directory in oil.nvim)
- [ ] Detect external file changes

## Usage

While it's still missing some features listed above, I would be happy if you want to
try it out

Install with your favorite package manager and call the setup function

Default options are listed below

```lua
require("xylene").setup({
  icons = {
    files = true,
    dir_open = "  ",
    dir_close = "  ",
  },
  indent = 4,
  sort_names = function(a, b)
    return a.name < b.name
  end,
  skip = function(name, filetype)
    return name == ".git"
  end,
})
```

### Keymaps

Current (not changeable yet) keymaps

- `<cr>` toggle dir / enter file

### User commands

- `Xylene` open a new xylene buffer with `cwd` as the root
- `Xylene!` same as `Xylene` plus recursively opens directories to make your file seen
