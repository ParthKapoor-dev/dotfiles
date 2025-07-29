-- autocmds
-- -- :Ex open in new tab
-- vim.api.nvim_create_autocmd('filetype', {
--   pattern = 'netrw',
--   callback = function()
--     -- Map Ctrl+Shift+O (i.e., <C-S-o>) in netrw to open selected file in a new tab
--     vim.keymap.set('n', '<C-k>', function()
--       local file = vim.fn.expand '<cfile>' -- gets the selected file under cursor
--       if vim.fn.filereadable(file) == 1 or vim.fn.isdirectory(file) == 1 then
--         vim.cmd('tabnew ' .. file)
--       else
--         print 'Not a valid file or directory'
--       end
--     end, { buffer = true, silent = true })
--   end,
-- })

-- keybinds

-- Tab Movement
vim.keymap.set('n', 't', 'gt', { desc = 'Better Way to move to next tab' })
vim.keymap.set('n', 'T', 'gT', { desc = 'Better Way to move to prev tab' })
