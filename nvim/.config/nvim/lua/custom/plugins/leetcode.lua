return {
  'kawre/leetcode.nvim',
  build = ':TSUpdate html', -- if you have `nvim-treesitter` installed
  dependencies = {
    -- include a picker of your choice, see picker section for more details
    'nvim-lua/plenary.nvim',
    'MunifTanjim/nui.nvim',
  },
  opts = {
    lang = 'cpp', -- or "python3", etc.
    plugins = {
      non_standalone = true, -- enable :Leet in a normal session
    },
    console = {
      open_on_runcode = true,
    },
  },
}
