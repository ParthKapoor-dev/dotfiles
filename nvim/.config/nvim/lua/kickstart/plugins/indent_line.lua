return {
  { -- Add indentation guides even on blank lines
    'lukas-reineke/indent-blankline.nvim',
    -- Enable `lukas-reineke/indent-blankline.nvim`
    -- See `:help ibl`
    main = 'ibl',
    opts = {
      indent = { char = '▏' },
      -- Highlight only the guide of the scope the cursor is in
      scope = { char = '▏', show_start = false, show_end = false },
    },
  },
}
