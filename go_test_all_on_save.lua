require 'config.util_find_func'
require 'config.util_go_test_on_save'

local mini_notify = require 'mini.notify'
local make_notify = mini_notify.make_notify {}

local attach_instace = {
  group = -1,
  job_id = -1,
}

local win_state = {
  floating = {
    buf = -1,
    win = -1,
  },
}

local ignored_actions = {
  pause = true,
  cont = true,
  start = true,
  skip = true,
}

local make_key = function(entry)
  assert(entry.Package, 'Must have package name' .. vim.inspect(entry))
  if not entry.Test then
    return entry.Package
  end
  assert(entry.Test, 'Must have test name' .. vim.inspect(entry))
  return string.format('%s/%s', entry.Package, entry.Test)
end

local add_golang_test = function(test_state, entry)
  test_state.tests[make_key(entry)] = {
    name = entry.Test,
  }
end

local mark_outcome = function(test_state, entry)
  local test = test_state.tests[make_key(entry)]
  if not test then
    return
  end
  test.success = entry.Action == 'pass'
end

local on_exit_fn = function(test_state)
  attach_instace.job_id = -1
  local test_outcome = true
  local failed_tests = {}
  local passed_tests = {}
  for _, test in pairs(test_state.tests) do
    if not test.success then
      table.insert(failed_tests, test.name)
      test_outcome = false
    else
      table.insert(passed_tests, test.name)
    end
  end

  print('Passed tests:\n  ' .. table.concat(passed_tests, '\n  '))
  print('Failed tests:\n  ' .. table.concat(failed_tests, '\n  '))

  if test_outcome then
    make_notify 'Tests passed'
  else
    make_notify('Tests failed:\n' .. table.concat(failed_tests, '\n'))
  end
end

local attach_on_write = function(command)
  local test_state = {
    tests = {},
    all_output = {},
  }

  local function output_go_test_all()
    Go_test_all_output(test_state, win_state)
  end

  vim.api.nvim_create_user_command('OutputAllTest', output_go_test_all, {})
  vim.keymap.set('n', '<leader>go', output_go_test_all, { desc = '[G]o [O]utput Test ' })

  vim.api.nvim_create_autocmd('BufWritePost', {
    group = attach_instace.group,
    pattern = '*.go',
    callback = function()
      Clean_up_prev_job(attach_instace.job_id)

      attach_instace.job_id = vim.fn.jobstart(command, {
        stdout_buffered = true,
        on_stdout = function(_, data)
          if not data then
            return
          end

          for _, line in ipairs(data) do
            if line == '' then
              goto continue
            end
            local decoded = vim.json.decode(line)
            assert(decoded, 'Failed to decode: ' .. line)
            table.insert(test_state.all_output, decoded)

            if ignored_actions[decoded.Action] then
              goto continue
            end

            if decoded.Action == 'run' then
              add_golang_test(test_state, decoded)
              goto continue
            end

            local test = test_state.tests[make_key(decoded)]
            if not test then
              goto continue
            end

            if decoded.Action == 'pass' or decoded.Action == 'fail' then
              mark_outcome(test_state, decoded)
            end

            ::continue::
          end
        end,

        on_exit = function()
          on_exit_fn(test_state)
        end,
      })
    end,
  })
end

local clear_group = function()
  if attach_instace.group == nil then
    return
  end
  local ok, _ = pcall(vim.api.nvim_get_autocmds, { group = 'live_go_test_group' })
  if not ok then
    return
  end
end

local new_attach_group = function()
  attach_instace.group = vim.api.nvim_create_augroup('live_go_test_group', { clear = true })
end

local attach_all_go_test = function()
  clear_group()
  new_attach_group()
  attach_on_write { 'go', 'test', './...', '-json', '-v' }
end

vim.api.nvim_create_user_command('GoTestOnSaveAll', attach_all_go_test, {})
