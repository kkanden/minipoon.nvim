A trimmed down version of the [harpoon](https://github.com/ThePrimeagen/harpoon/) plugin. This was made mainly due to
the original harpoon no longer being unmaintained even on the harpoon 2 branch and the lack of certain features being
built-in.

Built-in features:

- git branch specific marks
- autosave marks on leaving the marks UI
- updating mark position on leaving the buffer

Example configuration using `lazy.nvim`:

```lua
{
    "kkanden/minipoon.nvim",
    init = function()
        -- no need to run setup function, it's all set up OOTB
        local minipoon = require("minipoon")

        vim.keymap.set("n", "<leader>a", function() minipoon:add_mark() end, {})
        vim.keymap.set("n", "<C-e>", function() minipoon:toggle_window() end, {})

        -- open at given position in mark list, can be set to any position
        vim.keymap.set("n", "<localleader>1", function() minipoon:open_at(1) end, {})
    end,
}

```
