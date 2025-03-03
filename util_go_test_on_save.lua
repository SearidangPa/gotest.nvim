local ts_utils = require 'nvim-treesitter.ts_utils'
local get_node_text = vim.treesitter.get_node_text

local mini_notify = require 'mini.notify'
local make_notify = mini_notify.make_notify {}

function Get_enclosing_fn_info()
  local node = ts_utils.get_node_at_cursor()
  while node do
    if node:type() ~= 'function_declaration' then
      node = node:parent() -- Traverse up the node tree to find a function node
      goto continue
    end

    local func_name_node = node:child(1)
    if func_name_node then
      local func_name = get_node_text(func_name_node, 0)
      local startLine, _, _ = node:start()
      return startLine + 1, func_name -- +1 to convert 0-based to 1-based lua indexing system
    end
    ::continue::
  end

  return nil
end

function Get_enclosing_test()
  local _, testName = Get_enclosing_fn_info()
  if not testName then
    print 'Not in a function'
    return nil
  end
  if not string.match(testName, 'Test_') then
    print(string.format('Not in a test function: %s', testName))
    return nil
  end
  return testName
end

function Clean_up_prev_job(job_id)
  if job_id ~= -1 then
    make_notify(string.format('Stopping job: %d', job_id))
    vim.fn.jobstop(job_id)
    vim.diagnostic.reset()
  end
end

---@param win_state winState
Go_test_all_output = function(test_state, win_state)
  if vim.api.nvim_win_is_valid(win_state.floating.win) then
    vim.api.nvim_win_hide(win_state.floating.win)
    return
  end

  local content = {}
  for _, decodedLine in ipairs(test_state.all_output) do
    local output = decodedLine.Output
    if output then
      local trimmed_str = string.gsub(output, '\n', '')
      table.insert(content, trimmed_str)
    end
  end
  win_state.floating.buf, win_state.floating.win = Create_floating_window(win_state.floating.buf)
  vim.api.nvim_buf_set_lines(win_state.floating.buf, 0, -1, false, content)
end

---@param win_state winState
Toggle_test_output = function(test_state, win_state)
  if vim.api.nvim_win_is_valid(win_state.floating.win) then
    vim.api.nvim_win_hide(win_state.floating.win)
    return
  end

  local _, testName = Get_enclosing_fn_info()
  for _, test in pairs(test_state.tests) do
    if test.name == testName then
      win_state.floating.buf, win_state.floating.win = Create_floating_window(win_state.floating.buf)
      vim.api.nvim_buf_set_lines(win_state.floating.buf, 0, -1, false, test.output)
    end
  end
end
