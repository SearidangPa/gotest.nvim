local get_node_text = vim.treesitter.get_node_text
local ts_utils = require('nvim-treesitter.ts_utils')

local test_function_query_string = [[
(function_declaration
  name: (identifier) @name
  parameters: (parameter_list
    (parameter_declaration
      name: (identifier)
      type: (pointer_type
        (qualified_type
          package: (package_identifier) @_package_name
          name: (type_identifier) ))))
  (#eq? @_package_name "testing")
  (#eq? @name "%s")
)
]]

Find_test_line_by_name = function(go_bufnr, testName)
  local formatted = string.format(test_function_query_string, testName)
  local query = vim.treesitter.query.parse('go', formatted)
  local parser = vim.treesitter.get_parser(go_bufnr, 'go', {})
  local tree = parser:parse()[1]
  local root = tree:root()

  for _, node in query:iter_captures(root, go_bufnr, 0, -1) do
    local nodeContent = get_node_text(node, go_bufnr)

    if nodeContent == testName then
      local start_line, _, _, _ = node:range()
      return start_line + 1
    end
  end
end

local function_query = [[
(function_declaration
  name: (identifier) @name
  parameters: (parameter_list
    (parameter_declaration
      name: (identifier)
      type: (pointer_type
        (qualified_type
          package: (package_identifier) @_package_name
          name: (type_identifier) ))))
)
]]

function Find_all_tests (go_bufnr)
  local query = vim.treesitter.query.parse('go', function_query)
  local parser = vim.treesitter.get_parser(go_bufnr, 'go', {})
  local tree = parser:parse()[1]
  local root = tree:root()
  assert(root, 'root is nil')

  local res = {}
  for _, node in query:iter_captures(root, go_bufnr, 0, -1) do
    if node == nil then
      return res
    end
    local nodeContent = get_node_text(node, go_bufnr)

    -- all tests start with Test_
    if not string.match(nodeContent, 'Test_') then
      goto continue
    end

    res[nodeContent] = node:start() + 1
    ::continue::
  end
  return res
end



---@param bufnr number
---@param line number
---@return TSNode|nil
local function nearest_function_at_line(bufnr, line)
  local lang = vim.treesitter.language.get_lang(vim.bo[bufnr].filetype) -- Get language from filetype
  local parser = vim.treesitter.get_parser(bufnr, lang)
  local tree = parser:parse()[1]
  local root = tree:root()
  assert(tree, 'tree is nil')
  assert(parser, 'parser is nil')
  assert(root, 'root is nil')

  local function traverse(node)
    local nearest_function = nil
    for child in node:iter_children() do
      if child:type() == 'function_declaration' or child:type() == 'method_declaration' then
        local start_row, _, end_row, _ = child:range()
        if start_row <= line and end_row >= line then
          nearest_function = child
        end
      end

      if not nearest_function then
        nearest_function = traverse(child)
      end
      if nearest_function then
        break
      end
    end
    return nearest_function
  end

  return traverse(root)
end

function Nearest_func_name()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor_pos = vim.api.nvim_win_get_cursor(0)
  local line = cursor_pos[1] - 1
  local func_node = nearest_function_at_line(bufnr, line)
  assert(func_node, 'No function found')
  for child in func_node:iter_children() do
      if child:type() == 'identifier' or child:type() == 'field_identifier' or child:type() == 'name' then
          return vim.treesitter.get_node_text(child, bufnr)
      end
  end
end

vim.api.nvim_create_user_command('NearestFuncName', function()
  local func_name = Nearest_func_name()
  print("Nearest func name: " .. func_name)
end, {})

---@return TSNode
function Nearest_func_node()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor_pos = vim.api.nvim_win_get_cursor(0)
  local line = cursor_pos[1] - 1
  local func_node = nearest_function_at_line(bufnr, line)
  assert(func_node, 'No function found')
  return func_node
end





