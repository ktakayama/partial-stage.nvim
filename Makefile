.PHONY: test test-file

test:
	nvim --headless --noplugin -u test/minimal_init.lua \
		-c "lua require('plenary.test_harness').test_directory('test', {minimal_init = 'test/minimal_init.lua', sequential = true})"

test-file:
	nvim --headless --noplugin -u test/minimal_init.lua \
		-c "lua require('plenary.busted').run('$(FILE)')"

