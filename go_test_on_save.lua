require("config.util_find_func")
require("config.util_go_test_on_save")

local mini_notify = require("mini.notify")
local make_notify = mini_notify.make_notify({})

local ignored_actions = {
	pause = true,
	cont = true,
	start = true,
	skip = true,
}

local attach_instace = {
	group = -1,
	ns = -1,
	job_id = -1,
}

local win_state = {
	floating = {
		buf = -1,
		win = -1,
	},
}

local group_name = "live_go_test_group"
local ns_name = "live_go_test_ns"

local make_key = function(entry)
	assert(entry.Package, "Must have package name" .. vim.inspect(entry))
	if not entry.Test then
		return entry.Package
	end
	assert(entry.Test, "Must have test name" .. vim.inspect(entry))
	return string.format("%s/%s", entry.Package, entry.Test)
end

local add_golang_test = function(bufnr, test_state, entry)
	local testLine = Find_test_line_by_name(bufnr, entry.Test)
	if not testLine then
		testLine = 0
	end
	test_state.tests[make_key(entry)] = {
		name = entry.Test,
		line = testLine - 1,
		output = {},
	}
end

local add_golang_output = function(test_state, entry)
	assert(test_state.tests, vim.inspect(test_state))
	local trimmed_output = vim.trim(entry.Output)
	table.insert(test_state.tests[make_key(entry)].output, vim.trim(entry.Output))
end

local mark_outcome = function(test_state, entry)
	local test = test_state.tests[make_key(entry)]
	if not test then
		return
	end
	test.success = entry.Action == "pass"
end

local on_exit_fn = function(test_state, bufnr)
	attach_instace.job_id = -1
	local failed = {}
	for _, test in pairs(test_state.tests) do
		if not test.line or test.success then
			goto continue
		end

		table.insert(failed, {
			bufnr = bufnr,
			lnum = test.line,
			col = 0,
			severity = vim.diagnostic.severity.ERROR,
			source = "go-test",
			message = "Test Failed",
			user_data = {},
		})

		::continue::
	end

	if #failed == 0 then
		make_notify("Test passed")
	else
		make_notify("Test failed")
	end

	vim.diagnostic.set(attach_instace.ns, bufnr, failed, {})
end

local attach_to_buffer = function(bufnr, command)
	local test_state = {
		bufnr = bufnr,
		tests = {},
		all_output = {},
	}

	vim.api.nvim_create_user_command("OutputAllTest", function()
		Go_test_all_output(test_state, win_state)
	end, {})
	vim.api.nvim_create_user_command("OutputOneTest", function()
		Toggle_test_output(test_state, win_state)
	end, {})
	vim.keymap.set("n", "<leader>to", function()
		Toggle_test_output(test_state, win_state)
	end, { desc = "Test [O]utput", buffer = bufnr })

	local extmark_ids = {}
	vim.api.nvim_create_autocmd("BufWritePost", {
		group = attach_instace.group,
		pattern = "*.go",
		callback = function()
			Clean_up_prev_job(attach_instace.job_id)

			attach_instace.job_id = vim.fn.jobstart(command, {
				shell = true,
				stdout_buffered = true,
				on_stdout = function(_, data)
					if not data then
						return
					end

					for _, line in ipairs(data) do
						if line == "" then
							goto continue
						end
						local decoded = vim.json.decode(line)
						assert(decoded, "Failed to decode: " .. line)
						table.insert(test_state.all_output, decoded)

						if ignored_actions[decoded.Action] then
							goto continue
						end

						if decoded.Action == "run" then
							add_golang_test(bufnr, test_state, decoded)
							goto continue
						end

						if decoded.Action == "output" then
							if decoded.Test then
								add_golang_output(test_state, decoded)
							end
							goto continue
						end

						local test = test_state.tests[make_key(decoded)]
						if not test then
							goto continue
						end

						if decoded.Action == "pass" then
							mark_outcome(test_state, decoded)

							local test_extmark_id = extmark_ids[test.name]
							if test_extmark_id then
								vim.api.nvim_buf_del_extmark(bufnr, attach_instace.ns, test_extmark_id)
							end

							local current_time = os.date("%H:%M:%S")
							extmark_ids[test.name] =
								vim.api.nvim_buf_set_extmark(bufnr, attach_instace.ns, test.line, -1, {
									virt_text = {
										{ string.format("%s %s", "✅", current_time) },
									},
								})
						end

						if decoded.Action == "fail" then
							mark_outcome(test_state, decoded)
							local test_extmark_id = extmark_ids[test.name]
							if test_extmark_id then
								vim.api.nvim_buf_del_extmark(bufnr, attach_instace.ns, test_extmark_id)
							end
						end

						::continue::
					end
				end,

				on_exit = function()
					on_exit_fn(test_state, bufnr)
				end,
			})
		end,
	})
end

local clear_group_ns = function()
	if attach_instace.group == nil or attach_instace.ns == nil then
		return
	end
	local ok, _ = pcall(vim.api.nvim_get_autocmds, { group = group_name })
	if not ok then
		return
	end
	vim.api.nvim_del_augroup_by_name(group_name)
	vim.api.nvim_buf_clear_namespace(vim.api.nvim_get_current_buf(), attach_instace.ns, 0, -1)
	vim.diagnostic.reset()
end

local new_attach_instance = function()
	attach_instace.group = vim.api.nvim_create_augroup(group_name, { clear = true })
	attach_instace.ns = vim.api.nvim_create_namespace(ns_name)
end

local attach_all_go_test_in_buf = function()
	clear_group_ns()
	local bufnr = vim.api.nvim_get_current_buf()
	local testsInCurrBuf = Find_all_tests(bufnr)
	local concatTestName = ""
	for testName, _ in pairs(testsInCurrBuf) do
		concatTestName = concatTestName .. testName .. "|"
	end
	concatTestName = concatTestName:sub(1, -2) -- remove the last |
	local command = { "go", "test", "./...", "-json", "-v", "-run", string.format("%s", concatTestName) }
	new_attach_instance()
	attach_to_buffer(bufnr, command)
end

local attach_go_test = function()
	clear_group_ns()
	local test_name = Get_enclosing_test()
	make_notify(string.format("Attaching test: %s", test_name))
	local command = { "go", "test", "./...", "-json", "-v", "-run", test_name }
	new_attach_instance()
	attach_to_buffer(vim.api.nvim_get_current_buf(), command)
end

local function drive_test_command()
	local test_name = Get_enclosing_test()
	make_notify(string.format("Attaching drive test: %s", test_name))
	local command = { "go", "test", "./integration_tests/*.go", "-json", "-v", "-run", test_name }
	local command_str = string.format("go test integration_tests/*.go -json -v -run %s", test_name)
	return command_str
end

local function drive_test_on_save_dev()
	vim.env.UKS = "others"
	vim.env.MODE = "dev"
	new_attach_instance()
	attach_to_buffer(vim.api.nvim_get_current_buf(), drive_test_command())
end

local function drive_test_on_save_staging()
	vim.env.UKS = "others"
	vim.env.MODE = "staging"
	new_attach_instance()
	attach_to_buffer(vim.api.nvim_get_current_buf(), drive_test_command())
end

vim.api.nvim_create_user_command("GoTestClear", clear_group_ns, {})
vim.api.nvim_create_user_command("DriveTestOnSaveDev", drive_test_on_save_dev, {})
vim.api.nvim_create_user_command("DriveTestOnSaveStaging", drive_test_on_save_staging, {})
vim.api.nvim_create_user_command("GoTestOnSave", attach_go_test, {})
vim.api.nvim_create_user_command("GoTestOnSaveBuf", attach_all_go_test_in_buf, {})
vim.keymap.set("n", "<leader>gt", attach_go_test, { desc = "[T]oggle [G]o Test on save" })

return {}
