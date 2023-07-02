local api = vim.api

---@class Utils
local utils = require 'multicursors.utils'

---@class InsertMode
local insert_mode = require 'multicursors.insert_mode'

local debug = utils.debug

local ESC = vim.api.nvim_replace_termcodes('<Esc>', true, false, true)
local C_R = vim.api.nvim_replace_termcodes('<C-r>', true, false, true)

---@class NormalMode
local M = {}

--- Returns the first match for pattern after a offset in a string
---@param string string
---@param last_match Match
---@param row_idx integer
---@param offset integer
---@param skip boolean
---@return Match?
local find_next_match = function(string, last_match, row_idx, offset, skip)
    if not string or string == '' then
        return
    end

    if offset ~= 0 then
        string = string:sub(offset + 1, -1)
    end

    local match =
        vim.fn.matchstrpos(string, '\\<' .. last_match.pattern .. '\\>')
    -- -1 range means not found
    if match[2] == -1 and match[3] == -1 then
        return
    end

    --- @class Match
    local found = { pattern = last_match.pattern }

    -- add offset to match position index
    found.start = match[2] + offset
    found.finish = match[3] + offset
    found.row = row_idx

    -- jump the cursor to last match
    utils.clear_namespace(utils.namespace.Main)
    if not skip then
        utils.create_extmark(last_match, utils.namespace.Multi)
    end
    utils.create_extmark(found, utils.namespace.Main)
    utils.move_cursor({ row_idx + 1, found.start }, nil)

    return found
end

--- Returns the last match before the cursor
---@param string string
---@param last_match Match
---@param row_idx integer
---@param till integer
---@param skip boolean
---@return Match?
local find_prev_match = function(string, last_match, row_idx, till, skip)
    if not string or string == '' then
        return
    end
    local sub = string
    if till ~= -1 then
        sub = string:sub(0, till)
    end
    ---@type any[]?
    local match = nil
    ---@type Match?
    local found = nil
    local offset = 0
    repeat
        match = vim.fn.matchstrpos(sub, '\\<' .. last_match.pattern .. '\\>')
        -- -1 range means not found
        if match[2] ~= -1 and match[3] ~= -1 then
            found = {
                pattern = last_match.pattern,
                start = match[2] + offset, -- add offset to match position index
                finish = match[3] + offset,
                row = row_idx,
            }
            offset = offset + match[3]
            sub = string:sub(offset + 1, till)
        end
    until match and match[2] == -1 and match[3] == -1

    if not found then
        return
    end

    -- jump the cursor to last match
    utils.clear_namespace(utils.namespace.Main)
    if not skip then
        utils.create_extmark(last_match, utils.namespace.Multi)
    end
    utils.create_extmark(found, utils.namespace.Main)
    utils.move_cursor({ row_idx + 1, found.start }, nil)

    return found
end
--
-- creates a mark for word under the cursor
---@return Match?
M.find_cursor_word = function()
    local line = api.nvim_get_current_line()
    if not line then
        return
    end

    local cursor = api.nvim_win_get_cursor(0)
    local left = vim.fn.matchstrpos(line:sub(1, cursor[2] + 1), [[\k*$]])
    local right = vim.fn.matchstrpos(line:sub(cursor[2] + 1), [[^\k*]])

    if left == -1 and right == -1 then
        return
    end
    local match = {
        row = cursor[1] - 1,
        start = left[2],
        finish = right[3] + cursor[2],
        pattern = left[1] .. right[1]:sub(2),
    }
    utils.create_extmark(match, utils.namespace.Main)
    return match
end

---finds next match and marks it
---@param last_match Match?
---@param skip boolean
---@return Match? next next Match
M.find_next = function(last_match, skip)
    if not last_match then
        return
    end
    local line_count = api.nvim_buf_line_count(0)
    local row_idx = last_match.row
    local column = last_match.finish

    -- search the same line as cursor with cursor col as offset cursor
    local line = api.nvim_buf_get_lines(0, row_idx, row_idx + 1, true)[1]
    local match = find_next_match(line, last_match, row_idx, column, skip)
    if match then
        return match
    end

    -- search from cursor to end of buffer for pattern
    for idx = row_idx + 1, line_count - 1, 1 do
        line = api.nvim_buf_get_lines(0, idx, idx + 1, true)[1]
        match = find_next_match(line, last_match, idx, 0, skip)
        if match then
            return match
        end
    end

    -- when we didn't find the pattern we start searching again
    -- from start of the buffer
    for idx = 0, row_idx, 1 do
        line = api.nvim_buf_get_lines(0, idx, idx + 1, true)[1]
        match = find_next_match(line, last_match, idx, 0, skip)
        if match then
            return match
        end
    end
end

---finds previous match and marks it
---@param last_match Match?
---@param skip boolean
---@return Match? prev previus match
M.find_prev = function(last_match, skip)
    if not last_match then
        return
    end
    local line_count = api.nvim_buf_line_count(0)
    local row_idx = last_match.row
    local column = last_match.finish

    -- search the same line untill the cursor
    local line = api.nvim_buf_get_lines(0, row_idx, row_idx + 1, true)[1]
    local match = find_prev_match(
        line,
        last_match,
        row_idx,
        column - #last_match.pattern,
        skip
    )
    if match then
        return match
    end

    -- search from cursor to beginning of buffer for pattern
    -- fo
    for idx = row_idx - 1, 0, -1 do
        line = api.nvim_buf_get_lines(0, idx, idx + 1, true)[1]
        match = find_prev_match(line, last_match, idx, -1, skip)
        if match then
            return match
        end
    end

    -- when we didn't find the pattern we start searching again
    -- from start of the buffer
    for idx = line_count - 1, row_idx, -1 do
        line = api.nvim_buf_get_lines(0, idx, idx + 1, true)[1]
        match = find_prev_match(line, last_match, idx, -1, skip)
        if match then
            return match
        end
    end
end

--- runs a macro on the beginning of every selection
---@param config Config
M.run_macro = function(config)
    local register = utils.get_char()
    if not register or register == ESC then
        M.listen(config)
        return
    end

    utils.call_on_selections(function(mark)
        api.nvim_win_set_cursor(0, { mark[1] + 1, mark[2] })
        vim.cmd('normal @' .. register)
    end, true, true)

    utils.exit()
end

--- puts the text inside unnamed register before or after selections
---@param pos ActionPosition
M.paste = function(pos)
    utils.call_on_selections(function(mark)
        local position = { mark[1] + 1, mark[2] }
        if pos == utils.position.after then
            position = { mark[3].end_row + 1, mark[3].end_col }
        end

        api.nvim_win_set_cursor(0, position)
        vim.cmd 'normal P'
        vim.cmd 'redraw!'
    end, true, true)
end

M.dot_repeat = function()
    utils.call_on_selections(function(mark)
        api.nvim_win_set_cursor(0, { mark[1] + 1, mark[2] })
        vim.cmd 'normal .'
    end, true, true)
end

--- Deletes the text inside selections and starts insert mode
---@param config Config
M.change = function(config)
    utils.call_on_selections(function(mark)
        api.nvim_buf_set_text(
            0,
            mark[1],
            mark[2],
            mark[3].end_row,
            mark[3].end_col,
            {}
        )
    end, true, true)
    insert_mode.start(config)
end

--- Selects the word under cursor and starts listening for the actions
---@param config Config
M.start = function(config)
    local last_mark = M.find_cursor_word()

    --TODO when nil just add the cursor???
    if not last_mark then
        return
    end
    debug 'listening for mod selector'
    M.listen(config, last_mark)
end

---@param config Config
---@param last_mark? Match
M.listen = function(config, last_mark)
    while true do
        local key = utils.get_char()
        if not key then
            utils.exit()
            return
        end

        if key == ESC then
            utils.exit()
            return
        elseif key == 'n' then
            last_mark = M.find_next(last_mark, false)
        elseif key == 'N' then
            last_mark = M.find_prev(last_mark, false)
        elseif key == 'q' then
            last_mark = M.find_next(last_mark, true)
        elseif key == 'Q' then
            last_mark = M.find_prev(last_mark, true)
        elseif key == 'p' then
            last_mark = M.paste(utils.position.after)
        elseif key == 'P' then
            last_mark = M.paste(utils.position.before)
        elseif key == 'u' then
            vim.cmd.undo()
        elseif key == '.' then
            M.dot_repeat()
            return
        elseif key == C_R then
            vim.cmd.redo()
        elseif key == 'i' then
            insert_mode.start(config)
            return
        elseif key == 'a' then
            insert_mode.append(config)
            return
        elseif key == '@' then
            M.run_macro(config)
            return
        elseif key == 'c' then
            M.change(config)
            return
        end
    end
end

return M
