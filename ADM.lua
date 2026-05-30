script_name("ADV-RP.RU ADM CHECKER")
script_author("Casual Alvarez")
script_version("1.0.1")
script_description("ADV-RP.RU ADM CHECKER by Casual Alvarez")
script_moonloader(26)
script_dependencies("SAMPFUNCS", "SAMP")

require("lib.sampfuncs")
require("lib.moonloader")

local inicfg = require("inicfg")
local dlstatus = require("moonloader").download_status
local encoding = require("encoding")
local sampev = require("lib.samp.events")
local bit = require("bit")
local has_ffi, ffi = pcall(require, "ffi")
local winmm = nil
local imgui = nil

if has_ffi then
    pcall(function()
        ffi.cdef[[
            int PlaySoundA(const char *pszSound, void *hmod, unsigned int fdwSound);
        ]]
    end)

    local ok_winmm, loaded_winmm = pcall(ffi.load, "winmm")
    if ok_winmm then
        winmm = loaded_winmm
    end
end

encoding.default = "CP1251"
u8 = encoding.UTF8

local function cp1251_to_utf8(str)
    return tostring(u8(str or ""))
end

local function utf8_to_cp1251(str)
    return u8:decode(tostring(str or ""))
end

local BASE_DIR = "moonloader\\ADM"
local CHECKER_DIR = BASE_DIR .. "\\checker"
local CONFIG_REL = "ADM\\config.ini"
local CONFIG_PATH = "moonloader\\config\\" .. CONFIG_REL
local NOTIFY_SOUND_FILE = CHECKER_DIR .. "\\join_notify.wav"
local TARGET_SERVER_IP = "185.169.134.239"
local TARGET_SERVER_PORT = 7777
local STARTUP_SEPARATOR = "========================================"

local function is_target_server()
    if sampGetCurrentServerAddress == nil then
        return false
    end

    local ok, address, port = pcall(sampGetCurrentServerAddress)
    if not ok then
        return false
    end

    address = tostring(address or "")
    port = tonumber(port)

    if port == nil then
        local parsed_address, parsed_port = string.match(address, "^([^:]+):(%d+)$")
        if parsed_address ~= nil then
            address = parsed_address
            port = tonumber(parsed_port)
        end
    end

    return address == TARGET_SERVER_IP and port == TARGET_SERVER_PORT
end

local function unload_on_wrong_server()
    sampAddChatMessage(utf8_to_cp1251("{D9A657}[ADM] {E8E8E8}ADM Checker отключён: доступен только на " .. TARGET_SERVER_IP .. ":" .. tostring(TARGET_SERVER_PORT) .. "."), -1)

    if thisScript ~= nil then
        pcall(function()
            thisScript():unload()
        end)
    end
end


local defaults = {
    checker = {
        leaders_checker_status = true,
        friends_checker_status = true,
        admins_checker_status = true,
        source_updates_enabled = true,
        admin_checker_auto_update = true,
        notify_hidden_leader_events = false,
        notify_admin_events = true,
        notify_leader_events = true,
        notify_friend_events = true,
        friend_notify_mode = "all",
        sound_notify_enabled = false,
        sound_notify_admins = false,
        sound_notify_leaders = false,
        sound_notify_friends = false
    },
    overlay = {
        font = "Arial",
        font_size = 8,
        xpos = 5,
        ypos = 183,
        admin_show_level = true,
        admin_show_role = false,
        show_background = true,
        show_numbering = true,
        show_ids = true,
        hidden_leader_orgs = ""
    }
}

local FONT_OPTIONS = {
    "Arial",
    "Tahoma",
    "Verdana",
    "Trebuchet MS",
    "Calibri",
    "Segoe UI",
    "Consolas",
    "Lucida Console",
    "Times New Roman",
    "Georgia",
    "Cambria",
    "Courier New",
    "Franklin Gothic Medium",
    "Book Antiqua",
    "Palatino Linotype",
    "Garamond",
    "Impact",
    "MS Sans Serif"
}

local APP_TITLE = "Advance-RP AdminChecker by Casual Alvarez"
local APP_AUTHOR = "Casual Alvarez"
local APP_VERSION = "1.0.1"
UPDATE_INFO_URL = "https://raw.githubusercontent.com/ameskrillex/ADMCHECKERARP/main/version.json"
UPDATE_TEMP_INFO_PATH = CHECKER_DIR .. "\\version_remote.json"
UPDATE_TEMP_SCRIPT_PATH = CHECKER_DIR .. "\\ADM_update.lua"

local config = nil
local font = nil
local last_sync = 0
local imgui_loaded = false
local overlay_drag_active = false
local overlay_drag_saved = false
local overlay_drag_offset_x = 0
local overlay_drag_offset_y = 0
local overlay_drag_bounds = { x = 0, y = 0, w = 260, h = 18, active = false }
local admin_refresh_active = false
local admin_refresh_seen_nicks = {}
local admin_refresh_last_line_at = 0
local list_refresh_in_progress = false
local auto_close_refresh_dialogs = false

local admins_nick, admins_lvl, admins_id, admins_role, admins_notify, admins_locked, admins_sound_notify = {}, {}, {}, {}, {}, {}, {}
local leaders_nick, leaders_org, leaders_org_name, leaders_id, leaders_notify, leaders_sound_notify = {}, {}, {}, {}, {}, {}
local friends_nick, friends_id, friends_best, friends_notify, friends_sound_notify = {}, {}, {}, {}, {}
local checker_window = nil
local help_window = nil
local checker_window_just_opened = false
local overlay_move_mode = nil
local selected_admin = nil
local selected_leader = nil
local selected_friend = nil
local gui_page = nil
local admin_name_buffer = nil
local admin_level_buffer = nil
local admin_role_buffer = nil
local leader_name_buffer = nil
local leader_org_buffer = nil
local friend_name_buffer = nil
local friend_best_toggle = nil
local selected_font_index = nil
local font_size_value = nil
local save_config = nil
local remove_admin = nil
local sync_online_ids = nil
local ensure_default_admins = nil
update_check_in_progress = false

local function message(text)
    if text ~= nil and string.find(tostring(text), "Standalone%-") then
        text = "Команды: /ac"
    end

    sampAddChatMessage(utf8_to_cp1251("{D9A657}[ADM] {E8E8E8}" .. tostring(text or "")), -1)
end

local function trim(value)
    if value == nil then
        return nil
    end

    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function same_name(left, right)
    if left == nil or right == nil then
        return false
    end

    return string.lower(left) == string.lower(right)
end

local function split_args(text)
    local result = {}

    for token in string.gmatch(text or "", "%S+") do
        table.insert(result, token)
    end

    return result
end

local function split_pipe_fields(text)
    local fields = {}
    text = tostring(text or "")

    while true do
        local separator = string.find(text, "|", 1, true)
        if separator == nil then
            table.insert(fields, text)
            break
        end

        table.insert(fields, string.sub(text, 1, separator - 1))
        text = string.sub(text, separator + 1)
    end

    return fields
end

local function flag_to_bool(value, default_value)
    if value == nil or value == "" then
        return default_value ~= false
    end

    value = string.lower(trim(tostring(value)) or "")
    return not (value == "0" or value == "false" or value == "off" or value == "no")
end

local function bool_to_flag(value)
    return value == true and "1" or "0"
end

local function clean_list_field(value)
    return tostring(value or ""):gsub("|", "/")
end

function read_file_text(path)
    local file = io.open(path, "rb")
    if file == nil then
        return nil
    end

    local content = file:read("*a")
    file:close()
    return content
end

function write_file_text(path, content)
    local file = io.open(path, "wb")
    if file == nil then
        return false
    end

    file:write(content or "")
    file:close()
    return true
end

function parse_version_components(version)
    local result = {}
    for value in tostring(version or "0"):gmatch("(%d+)") do
        table.insert(result, tonumber(value) or 0)
    end
    return result
end

function is_remote_version_newer(local_version, remote_version)
    local local_parts = parse_version_components(local_version)
    local remote_parts = parse_version_components(remote_version)
    local length = math.max(#local_parts, #remote_parts)

    for index = 1, length do
        local left = local_parts[index] or 0
        local right = remote_parts[index] or 0
        if right > left then
            return true
        elseif right < left then
            return false
        end
    end

    return false
end

function parse_update_info(content)
    content = tostring(content or "")
    content = content:gsub("^\239\187\191", "")
    content = content:gsub("^%s+", "")

    local remote_version = string.match(content, '"version"%s*:%s*"([^"]+)"')
    local remote_url = string.match(content, '"url"%s*:%s*"([^"]+)"')
    local changelog = string.match(content, '"changelog"%s*:%s*"([^"]*)"')

    if remote_version == nil then
        remote_version = string.match(content, "'version'%s*:%s*'([^']+)'")
    end

    if remote_url == nil then
        remote_url = string.match(content, "'url'%s*:%s*'([^']+)'")
    end

    if changelog == nil then
        changelog = string.match(content, "'changelog'%s*:%s*'([^']*)'")
    end

    if remote_version == nil or remote_url == nil then
        return nil
    end

    remote_url = remote_url:gsub("\\/", "/")
    changelog = (changelog or ""):gsub("\\n", "\n"):gsub("\\/", "/")

    return {
        version = remote_version,
        url = remote_url,
        changelog = changelog
    }
end

function replace_current_script_from_file(downloaded_path)
    local downloaded_content = read_file_text(downloaded_path)
    if downloaded_content == nil or downloaded_content == "" then
        return false
    end

    local script_path = thisScript() ~= nil and thisScript().path or nil
    if script_path == nil or script_path == "" then
        return false
    end

    return write_file_text(script_path, downloaded_content)
end

function check_script_update(show_no_update_message, show_error_message)
    if update_check_in_progress then
        if show_error_message then
            message("Проверка обновления уже выполняется.")
        end
        return
    end

    if downloadUrlToFile == nil then
        if show_error_message then
            message("Функция загрузки недоступна, автообновление не поддерживается.")
        end
        return
    end

    update_check_in_progress = true
    pcall(os.remove, UPDATE_TEMP_INFO_PATH)
    pcall(os.remove, UPDATE_TEMP_SCRIPT_PATH)

    downloadUrlToFile(UPDATE_INFO_URL, UPDATE_TEMP_INFO_PATH, function(_, status)
        if status ~= dlstatus.STATUS_ENDDOWNLOADDATA then
            return
        end

        local info_content = read_file_text(UPDATE_TEMP_INFO_PATH)
        local info = parse_update_info(info_content)
        if info == nil then
            update_check_in_progress = false
            if show_error_message then
                local preview = tostring(info_content or ""):gsub("[%c]", " ")
                preview = preview:sub(1, 80)
                if string.find(string.lower(preview), "not found", 1, true) or string.find(string.lower(preview), "<!doctype", 1, true) or string.find(string.lower(preview), "<html", 1, true) then
                    message("Источник обновления вернул не JSON, а другую страницу.")
                else
                    message("Не удалось прочитать version.json обновления.")
                end
            end
            return
        end

        if not is_remote_version_newer(APP_VERSION, info.version) then
            update_check_in_progress = false
            if show_no_update_message then
                if show_error_message then
                    message("У вас уже установлена последняя версия.")
                else
                    message("Автообновление: используется актуальная версия.")
                end
            end
            return
        end

        downloadUrlToFile(info.url, UPDATE_TEMP_SCRIPT_PATH, function(_, download_status)
            if download_status ~= dlstatus.STATUS_ENDDOWNLOADDATA then
                return
            end

            update_check_in_progress = false

            if not replace_current_script_from_file(UPDATE_TEMP_SCRIPT_PATH) then
                if show_error_message then
                    message("Не удалось заменить текущий файл скрипта.")
                end
                return
            end

            message(string.format("Скачано обновление ADM Checker до версии %s.", tostring(info.version)))
            if info.changelog ~= nil and info.changelog ~= "" then
                message("Изменения: " .. tostring(info.changelog))
            end
            message("Перезагрузите скрипт или игру, чтобы применить обновление.")
        end)
    end)
end

function checker_update_command()
    check_script_update(true, true)
end

local function normalize_admin_level(level)
    if level == nil then
        return "-1"
    end

    level = string.upper(trim(tostring(level)) or "-1")

    if level == "S1" or level == "S2" or level == "S3" then
        return level
    end

    local numeric = tonumber(level)
    if numeric ~= nil then
        return tostring(math.floor(numeric))
    end

    if level == "S" then
        return "S1"
    end

    return "-1"
end

local function admin_level_sort_rank(level)
    level = normalize_admin_level(level)

    if level == "7" then
        return 9
    elseif level == "6" then
        return 8
    elseif level == "5" then
        return 7
    elseif level == "4" then
        return 6
    elseif level == "3" then
        return 5
    elseif level == "2" then
        return 4
    elseif level == "1" then
        return 3
    elseif level == "S3" then
        return 2
    elseif level == "S2" then
        return 1
    elseif level == "S1" then
        return 0
    end

    return -1
end

local function admin_level_text(level)
    level = normalize_admin_level(level)

    if level == "-1" then
        return "?"
    end

    return level
end

local function admin_role_title(level)
    level = normalize_admin_level(level)

    if level == "7" then
        return "Красный Администратор"
    elseif level == "6" then
        return "Главный Администратор"
    elseif level == "5" then
        return "Заместитель Главного Администратора"
    elseif level == "4" then
        return "Модератор"
    elseif level == "3" then
        return "Младший модератор"
    elseif level == "2" or level == "1" then
        return "Хелпер"
    elseif level == "S1" or level == "S2" or level == "S3" then
        return "YouTube"
    end

    return "Администратор"
end

local function get_admin_role_title(index, level)
    local custom_role = ""

    if index ~= nil then
        custom_role = trim(admins_role[index] or "") or ""
    end

    if custom_role ~= "" then
        return custom_role
    end

    return admin_role_title(level)
end

local function is_youtube_level(level)
    level = normalize_admin_level(level)
    return level == "S1" or level == "S2" or level == "S3"
end

local function format_display_nickname(nickname)
    return tostring(nickname or ""):gsub("_", " ")
end

local function youtube_level_hex(level)
    level = normalize_admin_level(level)

    if level == "S1" then
        return "FF6A6A"
    elseif level == "S2" then
        return "FF3F3F"
    elseif level == "S3" then
        return "FF1010"
    end

    return "FF3F3F"
end

local function format_youtube_nickname(nickname, level)
    local color = youtube_level_hex(level)
    local first_name, last_name = string.match(tostring(nickname or ""), "^([^_]+)_(.+)$")
    if first_name == nil or last_name == nil then
        return "{" .. color .. "}" .. format_display_nickname(nickname)
    end

    return string.format("{%s}%s {FFFFFF}%s", color, first_name, last_name)
end

local function build_admin_suffix(index, level)
    local parts = {}

    if config.overlay.admin_show_level then
        table.insert(parts, admin_level_text(level))
    end

    if config.overlay.admin_show_role then
        table.insert(parts, get_admin_role_title(index, level))
    end

    if #parts == 0 then
        return ""
    end

    return " [" .. table.concat(parts, " | ") .. "]"
end

local function leader_org_fallback_name(org_id)
    org_id = tonumber(org_id) or -1

    if org_id == 1 then
        return "Правительство"
    elseif org_id == 2 then
        return "МВД"
    elseif org_id == 3 then
        return "МО"
    elseif org_id == 4 then
        return "МЗ"
    elseif org_id == 5 then
        return "СМИ"
    elseif org_id >= 6 and org_id <= 10 then
        return "Банда"
    elseif org_id >= 11 and org_id <= 13 then
        return "Мафия"
    end

    return "Организация"
end

local function normalize_leader_org_title(org_title, org_id)
    local normalized = trim(tostring(org_title or ""))
    if normalized == nil or normalized == "" then
        return leader_org_fallback_name(org_id)
    end

    return normalized
end

local function normalize_leader_org_key(org_title)
    return string.lower(trim(tostring(org_title or "")) or "")
end

local function is_valid_leader_row(nickname, organization)
    nickname = trim(tostring(nickname or ""))
    organization = trim(tostring(organization or ""))

    if nickname == "" or organization == "" then
        return false
    end

    local lower_nickname = string.lower(nickname)
    local lower_org = string.lower(organization)

    if nickname == "Имя" or organization == "Организация" then
        return false
    end

    if string.find(lower_nickname, "id:", 1, true) or string.find(lower_nickname, "id ", 1, true) then
        return false
    end

    if string.find(nickname, "/", 1, true) or string.find(nickname, "|", 1, true) then
        return false
    end

    if string.find(lower_org, "организация", 1, true) and string.find(lower_nickname, "имя", 1, true) then
        return false
    end

    return true
end

local function parse_hidden_leader_orgs()
    local hidden = {}

    for org_title in string.gmatch(tostring(config.overlay.hidden_leader_orgs or ""), "([^|]+)") do
        local key = normalize_leader_org_key(org_title)
        if key ~= "" then
            hidden[key] = true
        end
    end

    return hidden
end

local function is_leader_org_visible(org_title)
    local key = normalize_leader_org_key(org_title)
    if key == "" then
        return true
    end

    return not parse_hidden_leader_orgs()[key]
end

local function should_notify_leader_org(org_title)
    if is_leader_org_visible(org_title) then
        return true
    end

    return config ~= nil and config.checker ~= nil and config.checker.notify_hidden_leader_events == true
end

local function is_best_friend(index)
    return friends_best[index] == true
end

local function should_notify_admin(index)
    if config ~= nil and config.checker ~= nil and config.checker.notify_admin_events ~= true then
        return false
    end

    return admins_notify[index] ~= false
end

local function should_notify_leader(index)
    if config ~= nil and config.checker ~= nil and config.checker.notify_leader_events ~= true then
        return false
    end

    if leaders_notify[index] == false then
        return false
    end

    local org_title = normalize_leader_org_title(leaders_org_name[index], leaders_org[index])
    return should_notify_leader_org(org_title)
end

local function should_notify_friend(index)
    if config ~= nil and config.checker ~= nil and config.checker.notify_friend_events ~= true then
        return false
    end

    if friends_notify[index] == false then
        return false
    end

    if config ~= nil and config.checker ~= nil and config.checker.friend_notify_mode == "best" then
        return is_best_friend(index)
    end

    return true
end


local function should_sound_notify_admin(index)
    return admins_sound_notify[index] == true
end

local function should_sound_notify_leader(index)
    if leaders_sound_notify[index] ~= true then
        return false
    end

    local org_title = normalize_leader_org_title(leaders_org_name[index], leaders_org[index])
    return should_notify_leader_org(org_title)
end

local function should_sound_notify_friend(index)
    if friends_sound_notify[index] ~= true then
        return false
    end

    if config ~= nil and config.checker ~= nil and config.checker.friend_notify_mode == "best" then
        return is_best_friend(index)
    end

    return true
end

local function set_leader_org_visible(org_title, visible)
    local hidden = parse_hidden_leader_orgs()
    local key = normalize_leader_org_key(org_title)

    if key == "" then
        return
    end

    if visible then
        hidden[key] = nil
    else
        hidden[key] = true
    end

    local values = {}
    for _, value in ipairs(leaders_org_name) do
        local current_key = normalize_leader_org_key(value)
        if current_key ~= "" and hidden[current_key] then
            table.insert(values, value)
            hidden[current_key] = nil
        end
    end

    table.sort(values, function(left, right)
        return string.lower(left) < string.lower(right)
    end)

    config.overlay.hidden_leader_orgs = table.concat(values, "|")
    save_config()
end

local function collect_leader_org_options()
    local unique = {}
    local result = {}

    for index = 1, #leaders_nick do
        local org_title = normalize_leader_org_title(leaders_org_name[index], leaders_org[index])
        local key = normalize_leader_org_key(org_title)
        if key ~= "" and not unique[key] then
            unique[key] = true
            table.insert(result, org_title)
        end
    end

    table.sort(result, function(left, right)
        return string.lower(left) < string.lower(right)
    end)

    return result
end

local function set_all_leader_orgs_visible(visible)
    local options = collect_leader_org_options()
    local hidden = {}

    if not visible then
        for _, org_title in ipairs(options) do
            local key = normalize_leader_org_key(org_title)
            if key ~= "" then
                hidden[key] = org_title
            end
        end
    end

    local values = {}
    for _, org_title in ipairs(options) do
        local key = normalize_leader_org_key(org_title)
        if key ~= "" and hidden[key] then
            table.insert(values, hidden[key])
        end
    end

    table.sort(values, function(left, right)
        return string.lower(left) < string.lower(right)
    end)

    config.overlay.hidden_leader_orgs = table.concat(values, "|")
    save_config()
end

local function invert_leader_org_visibility()
    local options = collect_leader_org_options()

    for _, org_title in ipairs(options) do
        set_leader_org_visible(org_title, not is_leader_org_visible(org_title))
    end
end

local function close_current_dialog_safely()
    if sampCloseCurrentDialogWithButton ~= nil then
        sampCloseCurrentDialogWithButton(0)
    elseif sampCloseCurrentDialog ~= nil then
        sampCloseCurrentDialog()
    end
end

local function send_chat_command(command)
    if sampProcessChatInput ~= nil then
        sampProcessChatInput(utf8_to_cp1251(command))
    else
        sampSendChat(utf8_to_cp1251(command))
    end
end

local function refresh_server_lists()
    if list_refresh_in_progress then
        message("Обновление списков уже запущено.")
        return
    end

    if config == nil or config.checker == nil or config.checker.source_updates_enabled == false then
        message("Обновление из источников отключено.")
        return
    end

    if not isSampAvailable() or sampGetGamestate() ~= 3 then
        message("Серверные списки можно обновить только в игре.")
        return
    end

    list_refresh_in_progress = true
    auto_close_refresh_dialogs = true
    message("Обновляю списки через /leaders, /admins и /adms...")

    lua_thread.create(function()
        send_chat_command("/leaders")
        wait(800)
        close_current_dialog_safely()

        send_chat_command("/admins")
        wait(1400)

        send_chat_command("/adms")
        wait(800)
        close_current_dialog_safely()

        wait(400)
        sync_online_ids()
        auto_close_refresh_dialogs = false
        list_refresh_in_progress = false
        message("Запрос обновления списков завершён.")
    end)
end

local function start_admin_refresh()
    admin_refresh_active = true
    admin_refresh_seen_nicks = {}
    admin_refresh_last_line_at = os.clock()
end

local function skip_admin_removal_on_refresh(level)
    level = normalize_admin_level(level)
    return level == "5" or level == "6" or level == "7" or level == "S1"
end

local function finalize_admin_refresh()
    if not admin_refresh_active then
        return
    end

    if config ~= nil and config.checker ~= nil and config.checker.source_updates_enabled == false then
        admin_refresh_active = false
        admin_refresh_seen_nicks = {}
        admin_refresh_last_line_at = 0
        return
    end

    for index = #admins_nick, 1, -1 do
        if (tonumber(admins_id[index]) or -1) ~= -1
            and not admin_refresh_seen_nicks[string.lower(admins_nick[index])]
            and admins_locked[index] ~= true
            and not skip_admin_removal_on_refresh(admins_lvl[index]) then
            local removed_name = admins_nick[index]
            remove_admin(removed_name)
            message(string.format("Администратор %s удалён из чекера: его нет в /admins.", format_display_nickname(removed_name)))
        end
    end

    admin_refresh_active = false
    admin_refresh_seen_nicks = {}
    admin_refresh_last_line_at = 0
end

local function sort_admins_by_level()
    local rows = {}

    for index = 1, #admins_nick do
        table.insert(rows, {
            nick = admins_nick[index],
            lvl = normalize_admin_level(admins_lvl[index]),
            id = tonumber(admins_id[index]) or -1,
            role = admins_role[index] or "",
            notify = admins_notify[index] ~= false,
            locked = admins_locked[index] == true,
            sound = admins_sound_notify[index] == true
        })
    end

    table.sort(rows, function(left, right)
        local left_rank = admin_level_sort_rank(left.lvl)
        local right_rank = admin_level_sort_rank(right.lvl)

        if left_rank ~= right_rank then
            return left_rank > right_rank
        end

        return string.lower(left.nick) < string.lower(right.nick)
    end)

    admins_nick, admins_lvl, admins_id, admins_role, admins_notify, admins_locked, admins_sound_notify = {}, {}, {}, {}, {}, {}, {}

    for _, row in ipairs(rows) do
        table.insert(admins_nick, row.nick)
        table.insert(admins_lvl, row.lvl)
        table.insert(admins_id, row.id)
        table.insert(admins_role, row.role)
        table.insert(admins_notify, row.notify)
        table.insert(admins_locked, row.locked)
        table.insert(admins_sound_notify, row.sound)
    end
end

local function set_buffer(buffer, value)
    if buffer ~= nil then
        buffer.v = tostring(value or "")
    end
end

local function find_font_index(font_name)
    local target = string.lower(tostring(font_name or ""))

    for index, name in ipairs(FONT_OPTIONS) do
        if string.lower(name) == target then
            return index
        end
    end

    return 1
end

local function init_imgui_state()
    checker_window = imgui.ImBool(false)
    help_window = imgui.ImBool(false)
    overlay_move_mode = imgui.ImBool(false)
    selected_admin = imgui.ImInt(-1)
    selected_leader = imgui.ImInt(-1)
    selected_friend = imgui.ImInt(-1)
    gui_page = imgui.ImInt(0)
    admin_name_buffer = imgui.ImBuffer("", 192)
    admin_level_buffer = imgui.ImBuffer("", 32)
    admin_role_buffer = imgui.ImBuffer("", 256)
    leader_name_buffer = imgui.ImBuffer("", 192)
    leader_org_buffer = imgui.ImBuffer("", 256)
    friend_name_buffer = imgui.ImBuffer("", 192)
    friend_best_toggle = imgui.ImBool(false)
    selected_font_index = imgui.ImInt(0)
    font_size_value = imgui.ImInt(8)
end


local function write_all(path, content)
    local file = io.open(path, "wb")
    if file == nil then
        return false
    end

    file:write(content or "")
    io.close(file)
    return true
end

local function pack_u32_le(value)
    value = math.floor(tonumber(value) or 0)
    local b1 = value % 256
    local b2 = math.floor(value / 256) % 256
    local b3 = math.floor(value / 65536) % 256
    local b4 = math.floor(value / 16777216) % 256
    return string.char(b1, b2, b3, b4)
end

local function pack_u16_le(value)
    value = math.floor(tonumber(value) or 0)
    return string.char(value % 256, math.floor(value / 256) % 256)
end

local function pack_s16_le(value)
    value = math.floor(tonumber(value) or 0)
    if value < 0 then
        value = 65536 + value
    end
    return pack_u16_le(value)
end

local function build_join_notify_wav()
    local sample_rate = 22050
    local duration = 0.085
    local total_samples = math.floor(sample_rate * duration)
    local samples = {}

    for index = 0, total_samples - 1 do
        local time = index / sample_rate
        local attack = math.min(1, time / 0.003)
        local click_decay = math.exp(-58 * time)
        local body_decay = math.exp(-24 * time)
        local click = (
            math.sin(2 * math.pi * 920 * time) * 0.22 +
            math.sin(2 * math.pi * 1460 * time) * 0.11 +
            math.sin(2 * math.pi * 2380 * time) * 0.035
        ) * click_decay
        local body = math.sin(2 * math.pi * 360 * time) * 0.075 * body_decay
        local fade_out = math.min(1, (duration - time) / 0.012)
        local value = (click + body) * attack * fade_out
        value = math.max(-0.35, math.min(0.35, value))
        samples[#samples + 1] = pack_s16_le(value * 32767)
    end

    local pcm_data = table.concat(samples)
    local byte_rate = sample_rate * 2
    local header = table.concat({
        "RIFF",
        pack_u32_le(36 + #pcm_data),
        "WAVE",
        "fmt ",
        pack_u32_le(16),
        pack_u16_le(1),
        pack_u16_le(1),
        pack_u32_le(sample_rate),
        pack_u32_le(byte_rate),
        pack_u16_le(2),
        pack_u16_le(16),
        "data",
        pack_u32_le(#pcm_data)
    })

    return header .. pcm_data
end

local function ensure_notify_sound_file()
    if doesFileExist(NOTIFY_SOUND_FILE) then
        return
    end

    write_all(NOTIFY_SOUND_FILE, build_join_notify_wav())
end

local last_notify_sound_at = 0

local function play_join_notification_sound(category)
    if config == nil or config.checker == nil or config.checker.sound_notify_enabled ~= true then
        return
    end

    if category == "admin" and config.checker.sound_notify_admins ~= true then
        return
    elseif category == "leader" and config.checker.sound_notify_leaders ~= true then
        return
    elseif category == "friend" and config.checker.sound_notify_friends ~= true then
        return
    end

    ensure_notify_sound_file()

    if winmm == nil or not doesFileExist(NOTIFY_SOUND_FILE) then
        return
    end

    local now = os.clock()
    if now - last_notify_sound_at < 0.15 then
        return
    end

    last_notify_sound_at = now
    pcall(function()
        winmm.PlaySoundA(NOTIFY_SOUND_FILE, nil, 0x00020000 + 0x00000001 + 0x00000002)
    end)
end

local function ensure_directory(path)
    if not doesDirectoryExist(path) then
        createDirectory(path)
    end
end

local function ensure_file(path)
    if not doesFileExist(path) then
        local file = io.open(path, "w")

        if file ~= nil then
            file:write("")
            io.close(file)
        end
    end
end

local function ensure_environment()
    ensure_directory(BASE_DIR)
    ensure_directory(CHECKER_DIR)
    ensure_directory("moonloader\\config")
    ensure_directory("moonloader\\config\\ADM")

    ensure_file(CHECKER_DIR .. "\\admins.txt")
    ensure_file(CHECKER_DIR .. "\\leaders.txt")
    ensure_file(CHECKER_DIR .. "\\friends.txt")
    ensure_notify_sound_file()
end

local function load_config()
    config = inicfg.load(defaults, CONFIG_PATH)

    if config == nil then
        config = {
            checker = {
                leaders_checker_status = defaults.checker.leaders_checker_status,
                friends_checker_status = defaults.checker.friends_checker_status,
                admins_checker_status = defaults.checker.admins_checker_status,
                source_updates_enabled = defaults.checker.source_updates_enabled,
                admin_checker_auto_update = defaults.checker.admin_checker_auto_update,
                notify_hidden_leader_events = defaults.checker.notify_hidden_leader_events,
                notify_admin_events = defaults.checker.notify_admin_events,
                notify_leader_events = defaults.checker.notify_leader_events,
                notify_friend_events = defaults.checker.notify_friend_events,
                friend_notify_mode = defaults.checker.friend_notify_mode,
                sound_notify_enabled = defaults.checker.sound_notify_enabled,
                sound_notify_admins = defaults.checker.sound_notify_admins,
                sound_notify_leaders = defaults.checker.sound_notify_leaders,
                sound_notify_friends = defaults.checker.sound_notify_friends
            },
            overlay = {
                font = defaults.overlay.font,
                font_size = defaults.overlay.font_size,
                xpos = defaults.overlay.xpos,
                ypos = defaults.overlay.ypos,
                admin_show_level = defaults.overlay.admin_show_level,
                admin_show_role = defaults.overlay.admin_show_role,
                show_background = defaults.overlay.show_background,
                show_numbering = defaults.overlay.show_numbering,
                show_ids = defaults.overlay.show_ids,
                hidden_leader_orgs = defaults.overlay.hidden_leader_orgs
            }
        }
    end

    if config.overlay.admin_show_level == nil then
        config.overlay.admin_show_level = defaults.overlay.admin_show_level
    end

    if config.overlay.admin_show_role == nil then
        config.overlay.admin_show_role = defaults.overlay.admin_show_role
    end

    if config.overlay.show_background == nil then
        config.overlay.show_background = defaults.overlay.show_background
    end

    if config.overlay.show_numbering == nil then
        config.overlay.show_numbering = defaults.overlay.show_numbering
    end

    if config.overlay.show_ids == nil then
        config.overlay.show_ids = defaults.overlay.show_ids
    end

    if config.overlay.hidden_leader_orgs == nil then
        config.overlay.hidden_leader_orgs = defaults.overlay.hidden_leader_orgs
    end

    if config.checker.notify_hidden_leader_events == nil then
        config.checker.notify_hidden_leader_events = defaults.checker.notify_hidden_leader_events
    end

    if config.checker.source_updates_enabled == nil then
        config.checker.source_updates_enabled = defaults.checker.source_updates_enabled
    end

    if config.checker.notify_admin_events == nil then
        config.checker.notify_admin_events = defaults.checker.notify_admin_events
    end

    if config.checker.notify_leader_events == nil then
        config.checker.notify_leader_events = defaults.checker.notify_leader_events
    end

    if config.checker.notify_friend_events == nil then
        config.checker.notify_friend_events = defaults.checker.notify_friend_events
    end

    if config.checker.friend_notify_mode ~= "best" then
        config.checker.friend_notify_mode = "all"
    end

    if config.checker.sound_notify_enabled == nil then
        config.checker.sound_notify_enabled = defaults.checker.sound_notify_enabled
    end

    if config.checker.sound_notify_admins == nil then
        config.checker.sound_notify_admins = defaults.checker.sound_notify_admins
    end

    if config.checker.sound_notify_leaders == nil then
        config.checker.sound_notify_leaders = defaults.checker.sound_notify_leaders
    end

    if config.checker.sound_notify_friends == nil then
        config.checker.sound_notify_friends = defaults.checker.sound_notify_friends
    end

    if not doesFileExist(CONFIG_PATH) then
        inicfg.save(config, CONFIG_REL)
    end
end

save_config = function()
    inicfg.save(config, CONFIG_REL)
end

local function reload_font()
    font = renderCreateFont(config.overlay.font, tonumber(config.overlay.font_size) or 8, 13)
end

local function explode_argb(color)
    local alpha = bit.band(bit.rshift(color, 24), 255)
    local red = bit.band(bit.rshift(color, 16), 255)
    local green = bit.band(bit.rshift(color, 8), 255)
    local blue = bit.band(color, 255)

    return alpha, red, green, blue
end

local function normalize_rgb(red, green, blue)
    if red == 34 and green == 34 and blue == 34 then
        return 110, 110, 110
    end

    if red == 0 and green == 0 and blue == 255 then
        return 30, 144, 255
    end

    return red, green, blue
end

local function clear_online_ids()
    for index = 1, #admins_id do
        admins_id[index] = -1
    end

    for index = 1, #leaders_id do
        leaders_id[index] = -1
    end

    for index = 1, #friends_id do
        friends_id[index] = -1
    end
end

local function load_admins()
    admins_nick, admins_lvl, admins_id, admins_role, admins_notify, admins_locked, admins_sound_notify = {}, {}, {}, {}, {}, {}, {}

    local file = io.open(CHECKER_DIR .. "\\admins.txt", "r")
    if file == nil then
        return
    end

    while true do
        local line = file:read()
        if line == nil then
            break
        end

        line = trim(line)
        if line ~= "" then
            local fields = split_pipe_fields(line)
            local nick = fields[1]
            local level = fields[2]
            local role = fields[3]
            local notify = fields[4]
            local locked = fields[5]
            local sound_notify = fields[6]

            if level == nil then
                nick = string.match(line, "(%S+)")
                level = string.match(line, "%S+%s+(%S+)")
                role = ""
                notify = "1"
                sound_notify = "0"
                locked = "0"
                sound_notify = "0"
            end

            if nick ~= nil and trim(nick) ~= "" then
                table.insert(admins_nick, trim(nick))
                table.insert(admins_lvl, normalize_admin_level(level))
                table.insert(admins_id, -1)
                table.insert(admins_role, trim(role or "") or "")
                table.insert(admins_notify, flag_to_bool(notify, true))
                table.insert(admins_locked, flag_to_bool(locked, false))
                table.insert(admins_sound_notify, flag_to_bool(sound_notify, false))
            end
        end
    end

    io.close(file)
    sort_admins_by_level()
end

local function load_leaders()
    leaders_nick, leaders_org, leaders_org_name, leaders_id, leaders_notify, leaders_sound_notify = {}, {}, {}, {}, {}, {}

    local file = io.open(CHECKER_DIR .. "\\leaders.txt", "r")
    if file == nil then
        return
    end

    while true do
        local line = file:read()
        if line == nil then
            break
        end

        line = trim(line)
        if line ~= "" then
            local fields = split_pipe_fields(line)
            local nick = fields[1]
            local org = fields[2]
            local org_title = fields[3]
            local notify = fields[4]
            local sound_notify = fields[5]

            if org == nil then
                nick = string.match(line, "(%S+)")
                org = string.match(line, "%S+%s+(%d+)")
                org_title = nil
                notify = "1"
                sound_notify = "0"
            end

            nick = trim(nick)
            org_title = normalize_leader_org_title(org_title, tonumber(org) or -1)

            if is_valid_leader_row(nick, org_title) then
                local org_id = tonumber(org) or -1
                table.insert(leaders_nick, nick)
                table.insert(leaders_org, org_id)
                table.insert(leaders_org_name, org_title)
                table.insert(leaders_id, -1)
                table.insert(leaders_notify, flag_to_bool(notify, true))
                table.insert(leaders_sound_notify, flag_to_bool(sound_notify, false))
            end
        end
    end

    io.close(file)
end

local function load_friends()
    friends_nick, friends_id, friends_best, friends_notify, friends_sound_notify = {}, {}, {}, {}, {}

    local file = io.open(CHECKER_DIR .. "\\friends.txt", "r")
    if file == nil then
        return
    end

    while true do
        local line = file:read()
        if line == nil then
            break
        end

        line = trim(line)
        if line ~= "" then
            local fields = split_pipe_fields(line)
            local nick = fields[1]
            local best_flag = fields[2]
            local notify = fields[3]
            local sound_notify = fields[4]
            if best_flag == nil then
                nick = line
                best_flag = "0"
                notify = "1"
                sound_notify = "0"
            end

            table.insert(friends_nick, trim(nick))
            table.insert(friends_id, -1)
            table.insert(friends_best, tostring(best_flag or "0") == "1")
            table.insert(friends_notify, flag_to_bool(notify, true))
            table.insert(friends_sound_notify, flag_to_bool(sound_notify, false))
        end
    end

    io.close(file)
end

local function load_all_lists()
    load_admins()
    if ensure_default_admins ~= nil then
        ensure_default_admins()
    end
    load_leaders()
    load_friends()
end

local function save_admins()
    sort_admins_by_level()

    local file = io.open(CHECKER_DIR .. "\\admins.txt", "w")
    if file == nil then
        return
    end

    for index, nick in ipairs(admins_nick) do
        local role = clean_list_field(admins_role[index])
        file:write(string.format("%s|%s|%s|%s|%s|%s\n", clean_list_field(nick), normalize_admin_level(admins_lvl[index]), role, bool_to_flag(admins_notify[index] ~= false), bool_to_flag(admins_locked[index] == true), bool_to_flag(admins_sound_notify[index] == true)))
    end

    io.close(file)
end

local function save_leaders()
    local file = io.open(CHECKER_DIR .. "\\leaders.txt", "w")
    if file == nil then
        return
    end

    for index, nick in ipairs(leaders_nick) do
        local org_title = clean_list_field(normalize_leader_org_title(leaders_org_name[index], leaders_org[index]))
        file:write(string.format("%s|%s|%s|%s|%s\n", clean_list_field(nick), tostring(leaders_org[index] or -1), org_title, bool_to_flag(leaders_notify[index] ~= false), bool_to_flag(leaders_sound_notify[index] == true)))
    end

    io.close(file)
end

local function save_friends()
    local file = io.open(CHECKER_DIR .. "\\friends.txt", "w")
    if file == nil then
        return
    end

    for index, nick in ipairs(friends_nick) do
        file:write(string.format("%s|%s|%s|%s\n", clean_list_field(nick), friends_best[index] and "1" or "0", bool_to_flag(friends_notify[index] ~= false), bool_to_flag(friends_sound_notify[index] == true)))
    end

    io.close(file)
end

local function select_admin(index)
    if selected_admin ~= nil then
        selected_admin.v = index
    end

    if index ~= nil and index >= 0 and admins_nick[index + 1] ~= nil then
        set_buffer(admin_name_buffer, admins_nick[index + 1])
        set_buffer(admin_level_buffer, admins_lvl[index + 1])
        set_buffer(admin_role_buffer, admins_role[index + 1] or "")
    else
        set_buffer(admin_name_buffer, "")
        set_buffer(admin_level_buffer, "")
        set_buffer(admin_role_buffer, "")
    end
end

local function select_leader(index)
    if selected_leader ~= nil then
        selected_leader.v = index
    end

    if index ~= nil and index >= 0 and leaders_nick[index + 1] ~= nil then
        set_buffer(leader_name_buffer, leaders_nick[index + 1])
        set_buffer(leader_org_buffer, leaders_org_name[index + 1] or leaders_org[index + 1])
    else
        set_buffer(leader_name_buffer, "")
        set_buffer(leader_org_buffer, "")
    end
end

local function select_friend(index)
    if selected_friend ~= nil then
        selected_friend.v = index
    end

    if index ~= nil and index >= 0 and friends_nick[index + 1] ~= nil then
        set_buffer(friend_name_buffer, friends_nick[index + 1])
        friend_best_toggle.v = friends_best[index + 1] == true
    else
        set_buffer(friend_name_buffer, "")
        if friend_best_toggle ~= nil then
            friend_best_toggle.v = false
        end
    end
end

local function refresh_gui_buffers()
    if config ~= nil then
        if selected_font_index ~= nil then
            selected_font_index.v = find_font_index(config.overlay.font) - 1
        end

        if font_size_value ~= nil then
            font_size_value.v = tonumber(config.overlay.font_size) or 8
        end
    end
end

local function find_index_by_name(list, nickname)
    for index, value in ipairs(list) do
        if same_name(value, nickname) then
            return index
        end
    end

    return nil
end

local function resolve_name_and_id(target)
    local player_id = tonumber(target)
    if player_id ~= nil and sampIsPlayerConnected(player_id) then
        return cp1251_to_utf8(sampGetPlayerNickname(player_id)), player_id
    end

    return target, player_id or -1
end

sync_online_ids = function()
    if not isSampAvailable() then
        return
    end

    clear_online_ids()

    local max_player_id = sampGetMaxPlayerId(false)
    for player_id = 0, max_player_id do
        if sampIsPlayerConnected(player_id) then
            local nickname = cp1251_to_utf8(sampGetPlayerNickname(player_id))

            for index, tracked_name in ipairs(admins_nick) do
                if same_name(tracked_name, nickname) then
                    admins_id[index] = player_id
                    break
                end
            end

            for index, tracked_name in ipairs(leaders_nick) do
                if same_name(tracked_name, nickname) then
                    leaders_id[index] = player_id
                    break
                end
            end

            for index, tracked_name in ipairs(friends_nick) do
                if same_name(tracked_name, nickname) then
                    friends_id[index] = player_id
                    break
                end
            end
        end
    end
end

local function upsert_admin(nickname, level, player_id, custom_role)
    local normalized_level = normalize_admin_level(level)
    local index = find_index_by_name(admins_nick, nickname)
    local normalized_role = trim(custom_role or "") or ""
    if index == nil then
        table.insert(admins_nick, nickname)
        table.insert(admins_lvl, normalized_level)
        table.insert(admins_id, tonumber(player_id) or -1)
        table.insert(admins_role, normalized_role)
        table.insert(admins_notify, true)
        table.insert(admins_locked, false)
        table.insert(admins_sound_notify, false)
    else
        admins_nick[index] = nickname
        admins_lvl[index] = normalized_level ~= "-1" and normalized_level or (admins_lvl[index] or "-1")
        admins_id[index] = tonumber(player_id) or admins_id[index] or -1
        if custom_role ~= nil then
            admins_role[index] = normalized_role
        else
            admins_role[index] = admins_role[index] or ""
        end
        admins_notify[index] = admins_notify[index] ~= false
        admins_locked[index] = admins_locked[index] == true
        admins_sound_notify[index] = admins_sound_notify[index] == true
    end

    save_admins()
end

ensure_default_admins = function()
    local defaults_to_add = {
        { nick = "Andrey_Ringo", level = "7", role = "" },
        { nick = "Smart_Jackson", level = "7", role = "" },
        { nick = "Alexey_Bartolomeo", level = "7", role = "Чел из тех. раздела." },
        { nick = "Daniel_Rubino", level = "7", role = "Игрок в кальмара" },
        { nick = "Aleksey_Krestovskiy", level = "4", role = "Чел из тех. раздела." },
        { nick = "Casual_Alvarez", level = "4", role = "" }
    }
    local changed = false

    for _, row in ipairs(defaults_to_add) do
        if find_index_by_name(admins_nick, row.nick) == nil then
            table.insert(admins_nick, row.nick)
            table.insert(admins_lvl, normalize_admin_level(row.level))
            table.insert(admins_id, -1)
            table.insert(admins_role, row.role)
            table.insert(admins_notify, true)
            table.insert(admins_locked, false)
            table.insert(admins_sound_notify, false)
            changed = true
        end
    end

    if changed then
        save_admins()
    end
end


local function upsert_leader(nickname, org_id, player_id, org_title)
    local index = find_index_by_name(leaders_nick, nickname)
    local normalized_org_id = tonumber(org_id) or -1
    local normalized_org_title = normalize_leader_org_title(org_title, normalized_org_id)

    if index == nil then
        table.insert(leaders_nick, nickname)
        table.insert(leaders_org, normalized_org_id)
        table.insert(leaders_org_name, normalized_org_title)
        table.insert(leaders_id, tonumber(player_id) or -1)
        table.insert(leaders_notify, true)
        table.insert(leaders_sound_notify, false)
    else
        leaders_nick[index] = nickname
        leaders_org[index] = normalized_org_id ~= -1 and normalized_org_id or leaders_org[index] or -1
        leaders_org_name[index] = normalized_org_title ~= "" and normalized_org_title or leaders_org_name[index] or leader_org_name(leaders_org[index])
        leaders_id[index] = tonumber(player_id) or leaders_id[index] or -1
        leaders_notify[index] = leaders_notify[index] ~= false
        leaders_sound_notify[index] = leaders_sound_notify[index] == true
    end

    save_leaders()
end

local function upsert_friend(nickname, player_id, is_best)
    local index = find_index_by_name(friends_nick, nickname)
    local best_value = is_best == true
    if index == nil then
        table.insert(friends_nick, nickname)
        table.insert(friends_id, tonumber(player_id) or -1)
        table.insert(friends_best, best_value)
        table.insert(friends_notify, true)
        table.insert(friends_sound_notify, false)
    else
        friends_nick[index] = nickname
        friends_id[index] = tonumber(player_id) or friends_id[index] or -1
        if is_best ~= nil then
            friends_best[index] = best_value
        else
            friends_best[index] = friends_best[index] == true
        end
        friends_notify[index] = friends_notify[index] ~= false
        friends_sound_notify[index] = friends_sound_notify[index] == true
    end

    save_friends()
end

remove_admin = function(nickname)
    local index = find_index_by_name(admins_nick, nickname)
    if index == nil then
        return false
    end

    table.remove(admins_nick, index)
    table.remove(admins_lvl, index)
    table.remove(admins_id, index)
    table.remove(admins_role, index)
    table.remove(admins_notify, index)
    table.remove(admins_locked, index)
    table.remove(admins_sound_notify, index)
    save_admins()

    return true
end

local function remove_leader(nickname)
    local index = find_index_by_name(leaders_nick, nickname)
    if index == nil then
        return false
    end

    table.remove(leaders_nick, index)
    table.remove(leaders_org, index)
    table.remove(leaders_org_name, index)
    table.remove(leaders_id, index)
    table.remove(leaders_notify, index)
    table.remove(leaders_sound_notify, index)
    save_leaders()

    return true
end

local function remove_friend(nickname)
    local index = find_index_by_name(friends_nick, nickname)
    if index == nil then
        return false
    end

    table.remove(friends_nick, index)
    table.remove(friends_id, index)
    table.remove(friends_best, index)
    table.remove(friends_notify, index)
    table.remove(friends_sound_notify, index)
    save_friends()

    return true
end

local function leader_org_name(org_id)
    org_id = tonumber(org_id) or -1

    if org_id == 1 then
        return "Правительство"
    elseif org_id == 2 then
        return "МВД"
    elseif org_id == 3 then
        return "МО"
    elseif org_id == 4 then
        return "МЗ"
    elseif org_id == 5 then
        return "СМИ"
    elseif org_id >= 6 and org_id <= 10 then
        return "Банда"
    elseif org_id >= 11 and org_id <= 13 then
        return "Мафия"
    end

    return "Организация"
end

local function leader_org_id_from_name(org_name)
    local value = string.lower(org_name or "")

    if string.find(value, "президент") or string.find(value, "губернат") then
        return 1
    elseif string.find(value, "полиции") or string.find(value, "мвд") or string.find(value, "фбр") then
        return 2
    elseif string.find(value, "военно") or string.find(value, "минобор") then
        return 3
    elseif string.find(value, "здраво") or string.find(value, "мгц") or string.find(value, "клиник") then
        return 4
    elseif string.find(value, "сми") or string.find(value, "news") or string.find(value, "радио") or string.find(value, "телевиз") then
        return 5
    elseif string.find(value, "ballas") or string.find(value, "rifa") or string.find(value, "vagos") or string.find(value, "grove") or string.find(value, "ацтек") then
        return 6
    elseif string.find(value, "mafia") or string.find(value, "мафи") or string.find(value, "cosa nostra") or string.find(value, "yakuza") or string.find(value, "русская мафия") then
        return 11
    end

    return -1
end

local function admin_level_color(level)
    level = normalize_admin_level(level)

    if level == "S1" then
        return 0xFFFF6A6A
    elseif level == "S2" then
        return 0xFFFF3F3F
    elseif level == "S3" then
        return 0xFFFF1010
    elseif level == "7" then
        return 0xFFFF0000
    elseif level == "6" then
        return 0xFF36B90E
    elseif level == "5" then
        return 0xFF4FF87B
    elseif level == "4" then
        return 0xFF436EEE
    elseif level == "3" then
        return 0xFFA73ADA
    elseif level == "2" or level == "1" then
        return 0xFF00BFFF
    end

    return 0xFFFFFFFF
end

local function admin_list_label(index)
    return string.format("%s [%s]", format_display_nickname(admins_nick[index]), admin_level_text(admins_lvl[index]))
end

local function leader_list_label(index)
    return string.format("%s | %s", format_display_nickname(leaders_nick[index]), normalize_leader_org_title(leaders_org_name[index], leaders_org[index]))
end

local function friend_list_label(index)
    if friends_best[index] == true then
        return "[BEST] " .. format_display_nickname(friends_nick[index])
    end

    return format_display_nickname(friends_nick[index])
end

local function player_has_character(player_id)
    if not sampIsPlayerConnected(player_id) then
        return false
    end

    local ok, handle = sampGetCharHandleBySampPlayerId(player_id)
    return ok and doesCharExist(handle)
end

local function draw_line(text, x, y, color)
    renderFontDrawText(font, utf8_to_cp1251(text), x + 1, y + 1, 0x90000000)
    renderFontDrawText(font, utf8_to_cp1251(text), x, y, color)
end

local function draw_box(x, y, w, h, color)
    if renderDrawBox ~= nil then
        pcall(renderDrawBox, x, y, w, h, color)
    end
end

local function count_online_entries(list, predicate)
    local count = 0

    for index, player_id in ipairs(list) do
        if player_id ~= -1 and (predicate == nil or predicate(index, player_id)) then
            count = count + 1
        end
    end

    return count
end

local function get_overlay_layout()
    local line_height = renderGetFontDrawHeight(font)
    local total_height = 16
    local width = 300
    local shown = 0

    if config.checker.leaders_checker_status then
        local online_count = count_online_entries(leaders_id, function(index)
            return is_leader_org_visible(normalize_leader_org_title(leaders_org_name[index], leaders_org[index]))
        end)
        local rows = 1 + math.max(online_count, 1)
        total_height = total_height + rows * line_height
        shown = shown + 1
    end

    if config.checker.friends_checker_status then
        if shown > 0 then
            total_height = total_height + math.floor(line_height * 1.3)
        end
        local online_count = count_online_entries(friends_id)
        local rows = 1 + math.max(online_count, 1)
        total_height = total_height + rows * line_height
        shown = shown + 1
    end

    if config.checker.admins_checker_status then
        if shown > 0 then
            total_height = total_height + math.floor(line_height * 1.3)
        end
        local online_count = count_online_entries(admins_id)
        local rows = 1 + math.max(online_count, 1)
        total_height = total_height + rows * line_height
        shown = shown + 1
        if config.overlay.admin_show_role then
            width = 420
        elseif config.overlay.admin_show_level then
            width = 340
        end
    end

    return width, total_height, line_height
end

local function draw_leaders(x, y)
    local count = 0
    local line_height = renderGetFontDrawHeight(font)

    draw_line("Лидеры в сети:", x, y, 0xFAFFFFFF)
    y = y + 0.5

    for index, player_id in ipairs(leaders_id) do
        if player_id ~= -1 and is_leader_org_visible(normalize_leader_org_title(leaders_org_name[index], leaders_org[index])) then
            count = count + 1

            local nickname = format_display_nickname(leaders_nick[index])
            local player_color = sampGetPlayerColor(player_id)
            local _, red, green, blue = explode_argb(player_color)

            red, green, blue = normalize_rgb(red, green, blue)

            local line
            if sampIsPlayerPaused(player_id) then
                line = string.format("{%02X%02X%02X}%d. %s [%d] {FF0000}[AFK]", red, green, blue, count, nickname, player_id)
            else
                line = string.format("{%02X%02X%02X}%d. %s [%d]", red, green, blue, count, nickname, player_id)
            end

            y = y + line_height
            if player_has_character(player_id) then
                line = line .. " {808080}[#]"
            end

            draw_line(line, x, y, 0xFFFFFFFF)
        end
    end

    if count == 0 then
        y = y + line_height
        draw_line("Лидеров в сети нет", x, y, 0x64FFFFFF)
    end

    return y
end

local function draw_friends(x, y, add_gap)
    local count = 0
    local line_height = renderGetFontDrawHeight(font)

    if add_gap then
        y = y + line_height * 1.3
    end

    draw_line("Друзья в сети:", x, y, 0xFAFFFFFF)
    y = y + 0.5

    for index, player_id in ipairs(friends_id) do
        if player_id ~= -1 then
            count = count + 1

            local nickname = format_display_nickname(friends_nick[index])
            local player_color = sampGetPlayerColor(player_id)
            local _, red, green, blue = explode_argb(player_color)

            red, green, blue = normalize_rgb(red, green, blue)

            local line
            if sampIsPlayerPaused(player_id) then
                line = string.format("{%02X%02X%02X}%d. %s [%d] {FF0000}[AFK]", red, green, blue, count, nickname, player_id)
            else
                line = string.format("{%02X%02X%02X}%d. %s [%d]", red, green, blue, count, nickname, player_id)
            end

            y = y + line_height
            if player_has_character(player_id) then
                line = line .. " {808080}[#]"
            end

            draw_line(line, x, y, 0xFFFFFFFF)
        end
    end

    if count == 0 then
        y = y + line_height
        draw_line("Друзей в сети нет", x, y, 0x64FFFFFF)
    end

    return y
end

local function draw_admins(x, y, add_gap)
    local count = 0
    local line_height = renderGetFontDrawHeight(font)

    if add_gap then
        y = y + line_height * 1.3
    end

    draw_line("Администраторы в сети:", x, y, 0xFAFFFFFF)
    y = y + 0.5

    for index, player_id in ipairs(admins_id) do
        if player_id ~= -1 then
            count = count + 1

            local nickname = admins_nick[index]
            local level = admins_lvl[index]
            local line_color = admin_level_color(level)
            local display_nickname = format_display_nickname(nickname)
            local suffix = build_admin_suffix(index, level)

            if is_youtube_level(level) then
                display_nickname = format_youtube_nickname(nickname, level)
            end

            local line = string.format("%d. %s [%d]%s", count, display_nickname, player_id, suffix)
            if sampIsPlayerPaused(player_id) then
                line = line .. " {FF0000}[AFK]"
            end

            y = y + line_height
            if player_has_character(player_id) then
                line = line .. " {808080}[#]"
            end

            if is_youtube_level(level) then
                draw_line(line, x, y, 0xFFFFFFFF)
            else
                draw_line(line, x, y, line_color)
            end
        end
    end

    if count == 0 then
        y = y + line_height
        draw_line("Администраторов в сети нет", x, y, 0x64FFFFFF)
    end

    return y
end

local function draw_overlay()
    if config == nil or font == nil or not sampIsChatVisible() or not sampIsLocalPlayerSpawned() then
        overlay_drag_bounds.active = false
        return
    end

    local anchor_x, anchor_y = convertGameScreenCoordsToWindowScreenCoords(config.overlay.xpos, config.overlay.ypos)
    local panel_w, panel_h, line_height = get_overlay_layout()
    local panel_x = anchor_x - 10
    local panel_y = anchor_y - 8
    local x = anchor_x
    local y = anchor_y
    local drew_previous = false

    if config.overlay.show_background then
        draw_box(panel_x + 3, panel_y + 3, panel_w, panel_h, 0x30000000)
        draw_box(panel_x, panel_y, panel_w, panel_h, 0x55101722)
        draw_box(panel_x, panel_y, panel_w, 3, 0xCCB45555)
    end

    overlay_drag_bounds.x = panel_x
    overlay_drag_bounds.y = panel_y
    overlay_drag_bounds.w = panel_w
    overlay_drag_bounds.h = panel_h
    overlay_drag_bounds.active = config.checker.leaders_checker_status or config.checker.friends_checker_status or config.checker.admins_checker_status

    if config.checker.leaders_checker_status then
        y = draw_leaders(x, y)
        drew_previous = true
    end

    if config.checker.friends_checker_status then
        y = draw_friends(x, y, drew_previous)
        drew_previous = true
    end

    if config.checker.admins_checker_status then
        y = draw_admins(x, y, drew_previous)
    end
end

local function get_imgui_mouse_pos()
    if not imgui_loaded or imgui == nil then
        return nil, nil
    end

    local ok, mouse_pos = pcall(imgui.GetMousePos)
    if not ok or mouse_pos == nil then
        return nil, nil
    end

    return mouse_pos.x, mouse_pos.y
end

local function point_in_rect(px, py, rect)
    return rect ~= nil
        and px ~= nil
        and py ~= nil
        and px >= rect.x
        and px <= rect.x + rect.w
        and py >= rect.y
        and py <= rect.y + rect.h
end

local function handle_overlay_drag()
    if not imgui_loaded or checker_window == nil or overlay_move_mode == nil then
        overlay_drag_active = false
        overlay_drag_saved = false
        return
    end

    if not checker_window.v or not overlay_move_mode.v or not overlay_drag_bounds.active then
        overlay_drag_active = false
        overlay_drag_saved = false
        return
    end

    local mouse_x, mouse_y = get_imgui_mouse_pos()
    if mouse_x == nil or mouse_y == nil then
        return
    end

    if not overlay_drag_active then
        if imgui.IsMouseClicked(0) and point_in_rect(mouse_x, mouse_y, overlay_drag_bounds) then
            overlay_drag_active = true
            overlay_drag_saved = false
            overlay_drag_offset_x = mouse_x - overlay_drag_bounds.x
            overlay_drag_offset_y = mouse_y - overlay_drag_bounds.y
        end
    else
        if imgui.IsMouseDown(0) then
            local window_x = mouse_x - overlay_drag_offset_x
            local window_y = mouse_y - overlay_drag_offset_y
            local game_x, game_y = convertWindowScreenCoordsToGameScreenCoords(window_x, window_y)

            config.overlay.xpos = math.floor(game_x)
            config.overlay.ypos = math.floor(game_y)
        else
            overlay_drag_active = false

            if not overlay_drag_saved then
                save_config()
                refresh_gui_buffers()
                overlay_drag_saved = true
                message("Overlay position saved.")
            end
        end
    end
end

local function toggle_checker_window()
    if not imgui_loaded or checker_window == nil then
        message("ImGui недоступен.")
        return
    end

    checker_window.v = not checker_window.v
    sync_imgui_input()

    if checker_window.v then
        checker_window_just_opened = true
        refresh_gui_buffers()
    else
        checker_window_just_opened = false
        overlay_move_mode.v = false
        overlay_drag_active = false
        overlay_drag_saved = false
        if showCursor ~= nil then
            pcall(showCursor, false, false)
        end
        if lockPlayerControl ~= nil then
            pcall(lockPlayerControl, false)
        end
        if sampToggleCursor ~= nil then
            pcall(sampToggleCursor, false)
        end
    end
end

local function draw_admin_editor()
    imgui.BeginChild("admins_list", imgui.ImVec2(420, 520), true)
    imgui.Text("Список")
    imgui.Separator()

    for index = 1, #admins_nick do
        if imgui.Selectable(admin_list_label(index), selected_admin.v == index - 1) then
            select_admin(index - 1)
        end
    end

    imgui.EndChild()
    imgui.SameLine()
    imgui.BeginChild("admins_edit", imgui.ImVec2(0, 520), true)
    imgui.Text("Карточка")
    imgui.Separator()

    if selected_admin.v >= 0 and admins_nick[selected_admin.v + 1] ~= nil then
        local idx = selected_admin.v + 1
        imgui.Text("Ник: " .. format_display_nickname(admins_nick[idx]))
        imgui.Text("Уровень: " .. admin_level_text(admins_lvl[idx]))
        imgui.Text("Должность: " .. get_admin_role_title(idx, admins_lvl[idx]))
        imgui.Text((tonumber(admins_id[idx]) or -1) ~= -1 and "Статус: онлайн" or "Статус: оффлайн")
        imgui.Separator()
    else
        imgui.Text("Выберите запись слева.")
        imgui.Separator()
    end

    imgui.Text("Ник")
    imgui.InputText("##admin_name", admin_name_buffer)
    imgui.Text("Уровень")
    imgui.InputText("##admin_level", admin_level_buffer)
    imgui.Text("Должность")
    imgui.InputText("##admin_role", admin_role_buffer)
    imgui.Spacing()

    if imgui.Button("Сохранить", imgui.ImVec2(-1, 32)) then
        local nickname = trim(admin_name_buffer.v)

        if nickname ~= "" then
            upsert_admin(nickname, admin_level_buffer.v, -1, admin_role_buffer.v)
            sync_online_ids()
            local sorted_index = find_index_by_name(admins_nick, nickname)

            if sorted_index ~= nil then
                select_admin(sorted_index - 1)
            end
        end
    end

    if imgui.Button("Удалить", imgui.ImVec2(-1, 32)) then
        if selected_admin.v >= 0 and admins_nick[selected_admin.v + 1] ~= nil then
            remove_admin(admins_nick[selected_admin.v + 1])
            sync_online_ids()
            select_admin(-1)
        end
    end

    imgui.EndChild()
end

local function draw_leader_editor()
    imgui.BeginChild("leaders_list", imgui.ImVec2(420, 520), true)
    imgui.Text("Список")
    imgui.Separator()

    for index = 1, #leaders_nick do
        if imgui.Selectable(leader_list_label(index), selected_leader.v == index - 1) then
            select_leader(index - 1)
        end
    end

    imgui.EndChild()
    imgui.SameLine()
    imgui.BeginChild("leaders_edit", imgui.ImVec2(0, 520), true)
    imgui.Text("Карточка")
    imgui.Separator()

    if selected_leader.v >= 0 and leaders_nick[selected_leader.v + 1] ~= nil then
        local idx = selected_leader.v + 1
        imgui.Text("Ник: " .. format_display_nickname(leaders_nick[idx]))
        imgui.Text("Фракция: " .. normalize_leader_org_title(leaders_org_name[idx], leaders_org[idx]))
        imgui.Text((tonumber(leaders_id[idx]) or -1) ~= -1 and "Статус: онлайн" or "Статус: оффлайн")
        imgui.Separator()
    else
        imgui.Text("Выберите запись слева.")
        imgui.Separator()
    end

    imgui.Text("Ник")
    imgui.InputText("##leader_name", leader_name_buffer)
    imgui.Text("Фракция")
    imgui.InputText("##leader_org", leader_org_buffer)
    imgui.Spacing()

    if imgui.Button("Сохранить", imgui.ImVec2(-1, 32)) then
        local nickname = trim(leader_name_buffer.v)

        if nickname ~= "" then
            local existing_index = find_index_by_name(leaders_nick, nickname)
            local org_title = trim(leader_org_buffer.v)
            local org_id = tonumber(org_title) or leader_org_id_from_name(org_title)
            upsert_leader(nickname, org_id, -1, org_title)
            sync_online_ids()

            if existing_index ~= nil then
                select_leader(existing_index - 1)
            else
                select_leader(#leaders_nick - 1)
            end
        end
    end

    if imgui.Button("Удалить", imgui.ImVec2(-1, 32)) then
        if selected_leader.v >= 0 and leaders_nick[selected_leader.v + 1] ~= nil then
            remove_leader(leaders_nick[selected_leader.v + 1])
            sync_online_ids()
            select_leader(-1)
            set_buffer(leader_name_buffer, "")
            set_buffer(leader_org_buffer, "")
        end
    end

    imgui.EndChild()
end

local function draw_friend_editor()
    imgui.BeginChild("friends_list", imgui.ImVec2(420, 520), true)
    imgui.Text("Список")
    imgui.Separator()

    for index = 1, #friends_nick do
        if imgui.Selectable(friend_list_label(index), selected_friend.v == index - 1) then
            select_friend(index - 1)
        end
    end

    imgui.EndChild()
    imgui.SameLine()
    imgui.BeginChild("friends_edit", imgui.ImVec2(0, 520), true)
    imgui.Text("Карточка")
    imgui.Separator()

    if selected_friend.v >= 0 and friends_nick[selected_friend.v + 1] ~= nil then
        local idx = selected_friend.v + 1
        imgui.Text("Ник: " .. format_display_nickname(friends_nick[idx]))
        imgui.Text((tonumber(friends_id[idx]) or -1) ~= -1 and "Статус: онлайн" or "Статус: оффлайн")
        imgui.Separator()
    else
        imgui.Text("Выберите запись слева.")
        imgui.Separator()
    end

    imgui.Text("Ник")
    imgui.InputText("##friend_name", friend_name_buffer)
    imgui.Spacing()

    if imgui.Button("Сохранить", imgui.ImVec2(-1, 32)) then
        local nickname = trim(friend_name_buffer.v)

        if nickname ~= "" then
            local existing_index = find_index_by_name(friends_nick, nickname)
            upsert_friend(nickname, -1)
            sync_online_ids()

            if existing_index ~= nil then
                select_friend(existing_index - 1)
            else
                select_friend(#friends_nick - 1)
            end
        end
    end

    if imgui.Button("Удалить", imgui.ImVec2(-1, 32)) then
        if selected_friend.v >= 0 and friends_nick[selected_friend.v + 1] ~= nil then
            remove_friend(friends_nick[selected_friend.v + 1])
            sync_online_ids()
            select_friend(-1)
            set_buffer(friend_name_buffer, "")
        end
    end

    imgui.EndChild()
end

local function draw_settings_editor()
    imgui.BeginChild("settings_left", imgui.ImVec2(500, 520), true)
    imgui.Text("Общее")
    imgui.Separator()

    if imgui.Checkbox("Показывать лидеров", imgui.ImBool(config.checker.leaders_checker_status)) then
        config.checker.leaders_checker_status = not config.checker.leaders_checker_status
        save_config()
    end

    if imgui.Checkbox("Показывать друзей", imgui.ImBool(config.checker.friends_checker_status)) then
        config.checker.friends_checker_status = not config.checker.friends_checker_status
        save_config()
    end

    if imgui.Checkbox("Показывать администраторов", imgui.ImBool(config.checker.admins_checker_status)) then
        config.checker.admins_checker_status = not config.checker.admins_checker_status
        save_config()
    end

    if imgui.Checkbox("Автообновление админов из /admins", imgui.ImBool(config.checker.admin_checker_auto_update)) then
        config.checker.admin_checker_auto_update = not config.checker.admin_checker_auto_update
        save_config()
    end

    if imgui.Checkbox("Показывать уровень админа", imgui.ImBool(config.overlay.admin_show_level)) then
        config.overlay.admin_show_level = not config.overlay.admin_show_level
        save_config()
    end

    if imgui.Checkbox("Показывать должность", imgui.ImBool(config.overlay.admin_show_role)) then
        config.overlay.admin_show_role = not config.overlay.admin_show_role
        save_config()
    end

    if imgui.Checkbox("Показывать фон чекера", imgui.ImBool(config.overlay.show_background)) then
        config.overlay.show_background = not config.overlay.show_background
        save_config()
    end

    if imgui.Checkbox("Перемещать чекер мышкой", overlay_move_mode) then
        overlay_drag_active = false
        overlay_drag_saved = false
    end

    imgui.Text(string.format("Позиция чекера: %s / %s", tostring(config.overlay.xpos), tostring(config.overlay.ypos)))
    imgui.Text("Перемещение: тяните чекер за верхнюю строку")
    imgui.Separator()
    imgui.Text("Фракции лидеров")
    imgui.BeginChild("leader_org_filters", imgui.ImVec2(0, 320), true)

    local leader_org_options = collect_leader_org_options()
    if #leader_org_options == 0 then
        imgui.Text("Список появится после /leaders")
    else
        for _, org_title in ipairs(leader_org_options) do
            if imgui.Checkbox(org_title, imgui.ImBool(is_leader_org_visible(org_title))) then
                set_leader_org_visible(org_title, not is_leader_org_visible(org_title))
            end
        end
    end

    imgui.EndChild()
    imgui.EndChild()
    imgui.SameLine()
    imgui.BeginChild("settings_right", imgui.ImVec2(0, 520), true)
    imgui.Text("Шрифт")
    imgui.Separator()
    imgui.BeginChild("font_selector", imgui.ImVec2(0, 260), true)

    for index, font_name in ipairs(FONT_OPTIONS) do
        if imgui.Selectable(font_name, selected_font_index.v == index - 1) then
            selected_font_index.v = index - 1
        end
    end

    imgui.EndChild()
    imgui.BeginChild("font_size_controls", imgui.ImVec2(0, 100), true)
    imgui.Text("Размер")

    if imgui.Button("Меньше", imgui.ImVec2(150, 30)) then
        font_size_value.v = math.max(6, font_size_value.v - 1)
    end

    imgui.SameLine()

    if imgui.Button("Больше", imgui.ImVec2(150, 30)) then
        font_size_value.v = math.min(20, font_size_value.v + 1)
    end

    imgui.Text("Текущий размер: " .. tostring(font_size_value.v))
    imgui.EndChild()

    if imgui.Button("Применить", imgui.ImVec2(-1, 32)) then
        local font_index = math.max(1, math.min(#FONT_OPTIONS, selected_font_index.v + 1))
        config.overlay.font = FONT_OPTIONS[font_index]
        config.overlay.font_size = math.max(6, math.min(20, font_size_value.v))
        save_config()
        reload_font()
        refresh_gui_buffers()
    end

    if imgui.Button("Обновить списки", imgui.ImVec2(-1, 32)) then
        load_all_lists()
        sync_online_ids()
    end

    if imgui.Button("Сохранить позицию", imgui.ImVec2(-1, 32)) then
        save_config()
    end

    imgui.EndChild()
end

local function draw_gui_page_buttons()
    local pages = {
        "Настройки",
        "Админы",
        "Лидеры",
        "Друзья"
    }

    local available_width = imgui.GetContentRegionAvailWidth()
    local button_width = math.floor((available_width - 18) / 4)

    for index, label in ipairs(pages) do
        if index > 1 then
            imgui.SameLine()
        end

        if imgui.Button(label, imgui.ImVec2(button_width, 30)) then
            gui_page.v = index - 1
        end
    end
end

function imguiOnDrawFrame()
    if not imgui_loaded or checker_window == nil or not checker_window.v or config == nil then
        return
    end

    if checker_window_just_opened then
        local screen_x, screen_y = getScreenResolution()
        local window_width = math.max(1040, screen_x - 20)
        local window_height = math.max(690, screen_y - 24)
        imgui.SetNextWindowPos(imgui.ImVec2(screen_x / 2, screen_y / 2), imgui.Cond.Always, imgui.ImVec2(0.5, 0.5))
        imgui.SetNextWindowSize(imgui.ImVec2(window_width, window_height), imgui.Cond.Always)
        checker_window_just_opened = false
    end

    imgui.SetNextWindowSize(imgui.ImVec2(1260, 800), imgui.Cond.FirstUseEver)
    imgui.Begin("ADV-RP.RU ADM CHECKER", checker_window)
    imgui.Text(APP_TITLE)
    imgui.SameLine()
    imgui.TextDisabled("/checkerui")
    draw_gui_page_buttons()
    imgui.Separator()

    if gui_page.v == 0 then
        draw_settings_editor()
    elseif gui_page.v == 1 then
        draw_admin_editor()
    elseif gui_page.v == 2 then
        draw_leader_editor()
    else
        draw_friend_editor()
    end
    imgui.End()

    if not checker_window.v then
        imgui.Process = false
        imgui.ShowCursor = false
        checker_window_just_opened = false
        overlay_move_mode.v = false
        overlay_drag_active = false
        overlay_drag_saved = false

        if showCursor ~= nil then
            pcall(showCursor, false, false)
        end
        if lockPlayerControl ~= nil then
            pcall(lockPlayerControl, false)
        end
        if sampToggleCursor ~= nil then
            pcall(sampToggleCursor, false)
        end
    end
end

local function print_help()
    message("Использование: /checker [admin/leader/friend] [add/remove] [id/ник] [lvl/org]")
    message("Служебное: /checker reload, /checker status")
    message("Настройки: /checker set [leaders/friends/admins/autoupdate] [on/off]")
    message("Оверлей: /checker set [x/y/font/fontsize] [значение]")
end

local function print_status()
    message(string.format("leaders=%s, friends=%s, admins=%s, autoupdate=%s",
        tostring(config.checker.leaders_checker_status),
        tostring(config.checker.friends_checker_status),
        tostring(config.checker.admins_checker_status),
        tostring(config.checker.admin_checker_auto_update)))

    message(string.format("overlay: x=%s y=%s font=%s size=%s",
        tostring(config.overlay.xpos),
        tostring(config.overlay.ypos),
        tostring(config.overlay.font),
        tostring(config.overlay.font_size)))
end

print_help = function()
    message("Usage: /checker [admin/leader/friend] [add/remove] [id/nick] [lvl/org]")
    message("Service: /checker reload, /checker status")
    message("Settings: /checker set [leaders/friends/admins/autoupdate] [on/off]")
    message("Overlay: /checker set [x/y/font/fontsize] [value]")
    message("GUI: /checkerui")
end

print_status = function()
    message(string.format("leaders=%s, friends=%s, admins=%s, autoupdate=%s",
        tostring(config.checker.leaders_checker_status),
        tostring(config.checker.friends_checker_status),
        tostring(config.checker.admins_checker_status),
        tostring(config.checker.admin_checker_auto_update)))

    message(string.format("overlay: x=%s y=%s font=%s size=%s",
        tostring(config.overlay.xpos),
        tostring(config.overlay.ypos),
        tostring(config.overlay.font),
        tostring(config.overlay.font_size)))
end

local function parse_on_off(value)
    if value == nil then
        return nil
    end

    value = string.lower(value)

    if value == "on" or value == "true" or value == "1" then
        return true
    elseif value == "off" or value == "false" or value == "0" then
        return false
    end

    return nil
end

local function checker_help()
    message("Использование: /checker [admin/leader/friend] [add/remove] [id/ник] [lvl/org]")
    message("Служебное: /checker reload, /checker status")
    message("Настройки: /checker set [leaders/friends/admins/autoupdate] [on/off]")
    message("Оверлей: /checker set [x/y/font/fontsize] [значение]")
    message("GUI: /checkerui")
end

local function checker_status()
    message(string.format("Лидеры=%s, друзья=%s, админы=%s, автообновление=%s",
        tostring(config.checker.leaders_checker_status),
        tostring(config.checker.friends_checker_status),
        tostring(config.checker.admins_checker_status),
        tostring(config.checker.admin_checker_auto_update)))

    message(string.format("Оверлей: x=%s y=%s, шрифт=%s, размер=%s",
        tostring(config.overlay.xpos),
        tostring(config.overlay.ypos),
        tostring(config.overlay.font),
        tostring(config.overlay.font_size)))
end

local function checker_command(params)
    if config == nil then
        return
    end

    params = cp1251_to_utf8(params)
    local args = split_args(params)
    if #args == 0 then
        checker_help()
        return
    end

    local group = string.lower(args[1])

    if group == "reload" then
        load_all_lists()
        sync_online_ids()
        message("Списки чекера перезагружены.")
        return
    end

    if group == "status" then
        checker_status()
        return
    end

    if group == "update" then
        checker_update_command()
        return
    end

    if group == "set" then
        local key = string.lower(args[2] or "")
        local value = args[3]

        if key == "leaders" then
            local state = parse_on_off(value)
            if state == nil then
                checker_help()
                return
            end

            config.checker.leaders_checker_status = state
        elseif key == "friends" then
            local state = parse_on_off(value)
            if state == nil then
                checker_help()
                return
            end

            config.checker.friends_checker_status = state
        elseif key == "admins" then
            local state = parse_on_off(value)
            if state == nil then
                checker_help()
                return
            end

            config.checker.admins_checker_status = state
        elseif key == "sources" then
            local state = parse_on_off(value)
            if state == nil then
                checker_help()
                return
            end

            config.checker.source_updates_enabled = state
        elseif key == "autoupdate" then
            local state = parse_on_off(value)
            if state == nil then
                checker_help()
                return
            end

            config.checker.admin_checker_auto_update = state
        elseif key == "x" then
            config.overlay.xpos = tonumber(value) or config.overlay.xpos
        elseif key == "y" then
            config.overlay.ypos = tonumber(value) or config.overlay.ypos
        elseif key == "font" then
            config.overlay.font = tostring(value or config.overlay.font)
            reload_font()
        elseif key == "fontsize" then
            config.overlay.font_size = tonumber(value) or config.overlay.font_size
            reload_font()
        else
            checker_help()
            return
        end

        save_config()
        message("Настройка обновлена.")
        return
    end

    local action = string.lower(args[2] or "")
    local target = args[3]
    local extra = args[4]

    if target == nil then
        checker_help()
        return
    end

    local nickname, player_id = resolve_name_and_id(target)
    if nickname == nil or nickname == "" then
        message("Не удалось определить игрока.")
        return
    end

    if group == "admin" then
        if action == "add" then
            upsert_admin(nickname, extra or -1, player_id)
            message("Админ добавлен в чекер: " .. nickname)
        elseif action == "remove" then
            if remove_admin(nickname) then
                message("Админ удалён из чекера: " .. nickname)
            else
                message("Админ не найден в списке: " .. nickname)
            end
        else
            checker_help()
        end
    elseif group == "leader" then
        if action == "add" then
            upsert_leader(nickname, tonumber(extra) or -1, player_id)
            message("Лидер добавлен в чекер: " .. nickname)
        elseif action == "remove" then
            if remove_leader(nickname) then
                message("Лидер удалён из чекера: " .. nickname)
            else
                message("Лидер не найден в списке: " .. nickname)
            end
        else
            checker_help()
        end
    elseif group == "friend" then
        if action == "add" then
            upsert_friend(nickname, player_id)
            message("Друг добавлен в чекер: " .. nickname)
        elseif action == "remove" then
            if remove_friend(nickname) then
                message("Друг удалён из чекера: " .. nickname)
            else
                message("Друг не найден в списке: " .. nickname)
            end
        else
            checker_help()
        end
    else
        checker_help()
    end
end

local function refresh_s_admins_from_dialog(text)
    if text == nil or text == "" then
        return false
    end

    local parsed_text = cp1251_to_utf8(text)
    local parsed = 0

    for line in string.gmatch(parsed_text, "[^\r\n]+") do
        local nickname, level = string.match(line, "^([^\t]+)\t([^\t]+)")
        if nickname ~= nil and level ~= nil then
            nickname = trim(nickname)
            level = normalize_admin_level(trim(level))

            if nickname ~= "" and nickname ~= "Ник" and is_youtube_level(level) then
                upsert_admin(nickname, level, nil)
                parsed = parsed + 1
            end
        end
    end

    if parsed == 0 then
        return false
    end

    sync_online_ids()
    message(string.format("Список S-администраторов обновлён из диалога /adms. Записей: %d.", parsed))
    return true
end

function sampOnPlayerJoin(player_id, _, _, nickname)
    nickname = cp1251_to_utf8(nickname)

    for index, tracked_name in ipairs(admins_nick) do
        if same_name(tracked_name, nickname) then
            admins_id[index] = player_id

            if sampIsLocalPlayerSpawned() then
                local level = normalize_admin_level(admins_lvl[index])

                if level == "S1" or level == "S2" or level == "S3" then
                    message(string.format("Подключился ютубер-администратор %s уровня, %s[%d].", level, nickname, player_id))
                elseif level == "7" or level == "6" then
                    message(string.format("Подключился главный администратор, %s[%d].", nickname, player_id))
                elseif level == "5" then
                    message(string.format("Подключился зам. главного администратора, %s[%d].", nickname, player_id))
                elseif level == "1" or level == "2" or level == "3" or level == "4" then
                    message(string.format("Подключился администратор %s уровня, %s[%d].", level, nickname, player_id))
                else
                    message(string.format("Подключился администратор %s[%d].", nickname, player_id))
                end
            end

            break
        end
    end

    for index, tracked_name in ipairs(leaders_nick) do
        if same_name(tracked_name, nickname) then
            leaders_id[index] = player_id

            if sampIsLocalPlayerSpawned() then
                message(string.format("Подключился лидер %s, %s[%d].", leader_org_name(leaders_org[index]), nickname, player_id))
            end

            break
        end
    end

    for index, tracked_name in ipairs(friends_nick) do
        if same_name(tracked_name, nickname) then
            friends_id[index] = player_id

            if sampIsLocalPlayerSpawned() then
                message(string.format("%s[%d] подключился.", nickname, player_id))
            end

            break
        end
    end
end

function sampOnPlayerQuit(player_id, _)
    for index, tracked_id in ipairs(admins_id) do
        if tracked_id == player_id then
            admins_id[index] = -1
            message(string.format("Администратор %s[%d] отключился.", admins_nick[index], player_id))
            break
        end
    end

    for index, tracked_id in ipairs(leaders_id) do
        if tracked_id == player_id then
            leaders_id[index] = -1
            message(string.format("Лидер %s[%d] отключился.", leaders_nick[index], player_id))
            break
        end
    end

    for index, tracked_id in ipairs(friends_id) do
        if tracked_id == player_id then
            friends_id[index] = -1
            message(string.format("%s[%d] отключился.", friends_nick[index], player_id))
            break
        end
    end
end

local function parse_admin_line(text)
    if text == nil then
        return nil, nil, nil
    end

    text = cp1251_to_utf8(text)
    local nickname, tracked_id, level = string.match(text, "^([%w_]+)%[(%d+)%]%s*%(([%w]+)%s+lvl%)")
    if nickname == nil then
        nickname, tracked_id, level = string.match(text, "([%w_]+)%[(%d+)%]%s*%(([%w]+)%s+lvl%)")
    end

    tracked_id = tonumber(tracked_id)
    level = normalize_admin_level(level)

    if nickname == nil or tracked_id == nil or level == "-1" then
        return nil, nil, nil
    end

    return nickname, tracked_id, level
end

local function update_admin_from_line(text, local_name)
    local nickname, tracked_id, level = parse_admin_line(text)
    if nickname == nil or same_name(local_name, nickname) then
        return false
    end

    local index = find_index_by_name(admins_nick, nickname)
    if index ~= nil and admins_locked[index] == true then
        return false
    end

    if index == nil then
        upsert_admin(nickname, level, tracked_id)
        message(string.format("В чекер добавлен администратор %s [%d], уровень %s.", nickname, tracked_id, level))
        return true
    end

    local old_level = normalize_admin_level(admins_lvl[index])
    local old_id = tonumber(admins_id[index]) or -1

    admins_id[index] = tracked_id

    if old_level ~= level then
        admins_lvl[index] = level
        save_admins()
        message(string.format("Обновлён уровень администратора %s: %s -> %s.", nickname, old_level, level))
        return true
    end

    if old_id ~= tracked_id then
        message(string.format("Обновлён ID администратора %s: [%d].", nickname, tracked_id))
        return true
    end

    return false
end

local function refresh_leaders_from_dialog(text)
    if text == nil or text == "" then
        return false
    end

    text = cp1251_to_utf8(text)
    local new_nick = {}
    local new_org = {}
    local parsed = 0

    for line in string.gmatch(text, "[^\r\n]+") do
        local nickname, organization = string.match(line, "^([^\t]+)\t([^\t]+)")
        if nickname ~= nil and organization ~= nil and nickname ~= "Имя" then
            nickname = trim(nickname)
            organization = trim(organization)

            if nickname ~= "" then
                parsed = parsed + 1
                table.insert(new_nick, nickname)
                table.insert(new_org, leader_org_id_from_name(organization))
            end
        end
    end

    if parsed == 0 then
        return false
    end

    leaders_nick = new_nick
    leaders_org = new_org
    leaders_id = {}

    for _ = 1, #leaders_nick do
        table.insert(leaders_id, -1)
    end

    save_leaders()
    sync_online_ids()
    message(string.format("Список лидеров обновлён из диалога /leaders. Записей: %d.", parsed))

    return true
end

function sampOnServerMessage(color, text)
    if config == nil or color ~= -65281 or not config.checker.admin_checker_auto_update then
        return
    end

    local local_id = nil
    local local_name = nil
    local ok, player_id = sampGetPlayerIdByCharHandle(PLAYER_PED)
    if ok then
        local_id = player_id
        local_name = sampGetPlayerNickname(local_id)
    end

    local nickname, tracked_id, level = string.match(text, "^([%w_]+)%[(%d+)%]%s*%(([%w]+)%s+lvl%)")
    tracked_id = tonumber(tracked_id)
    level = normalize_admin_level(level)

    if nickname == nil or tracked_id == nil or level == "-1" or same_name(local_name, nickname) then
        return
    end

    local index = find_index_by_name(admins_nick, nickname)
    if index == nil then
        upsert_admin(nickname, level, tracked_id)
        message(string.format("Администратор %s уровня, %s, добавлен в чекер.", tostring(level), nickname))
    else
        local old_level = normalize_admin_level(admins_lvl[index])
        local new_level = level

        admins_id[index] = tracked_id

        if old_level ~= new_level then
            admins_lvl[index] = new_level
            save_admins()
            message("Уровень администратора " .. nickname .. " обновлён.")
        end
    end
end

function sampOnServerMessage(color, text)
    if config == nil or config.checker.source_updates_enabled == false or not config.checker.admin_checker_auto_update then
        return
    end

    local local_name = nil
    local ok, player_id = sampGetPlayerIdByCharHandle(PLAYER_PED)
    if ok then
        local_name = cp1251_to_utf8(sampGetPlayerNickname(player_id))
    end

    update_admin_from_line(text, local_name)
end

function sampOnShowDialog(dialog_id, style, title, button1, button2, text)
    local raw_title = tostring(title or '')
    local parsed_title = cp1251_to_utf8(raw_title)
    local is_leaders_dialog = string.find(parsed_title, 'Лидеры', 1, true) or string.find(raw_title, 'Лидеры', 1, true)
    if style == 5 and dialog_id == 424 and string.find(parsed_title, "Лидеры", 1, true) then
        refresh_leaders_from_dialog(text)
    end
end

message = function(text)
    text = tostring(text or "")

    if string.find(text, "Standalone%-") then
        text = "Команды: /ac"
    elseif string.find(text, "ImGui Р", 1, true) then
        text = "ImGui не найден. GUI и перенос мышкой отключены."
    elseif string.find(text, "ADV-RP.RU ADM CHECKER by Casual Alvarez Р", 1, true) then
        text = "Команды: /ac"
    end

    sampAddChatMessage(utf8_to_cp1251("{D9A657}[ADV-RP] {E8E8E8}" .. text), -1)
end

leader_org_name = function(org_id)
    org_id = tonumber(org_id) or -1

    if org_id == 1 then
        return "Правительство"
    elseif org_id == 2 then
        return "МВД"
    elseif org_id == 3 then
        return "МО"
    elseif org_id == 4 then
        return "МЗ"
    elseif org_id == 5 then
        return "СМИ"
    elseif org_id >= 6 and org_id <= 10 then
        return "Банда"
    elseif org_id >= 11 and org_id <= 13 then
        return "Мафия"
    end

    return "Организация"
end

leader_org_id_from_name = function(org_name)
    local value = string.lower(tostring(org_name or ""))

    if string.find(value, "президент") or string.find(value, "губернат") then
        return 1
    elseif string.find(value, "полиции") or string.find(value, "мвд") or string.find(value, "фбр") then
        return 2
    elseif string.find(value, "военно") or string.find(value, "минобор") then
        return 3
    elseif string.find(value, "здраво") or string.find(value, "мгц") or string.find(value, "клиник") then
        return 4
    elseif string.find(value, "сми") or string.find(value, "news") or string.find(value, "радио") or string.find(value, "телевиз") then
        return 5
    elseif string.find(value, "ballas") or string.find(value, "rifa") or string.find(value, "vagos") or string.find(value, "grove") or string.find(value, "ацтек") then
        return 6
    elseif string.find(value, "mafia") or string.find(value, "мафи") or string.find(value, "cosa nostra") or string.find(value, "yakuza") or string.find(value, "русская мафия") then
        return 11
    end

    return -1
end

checker_help = function()
    message("Использование: /checker [admin/leader/friend] [add/remove] [id/ник] [lvl/org]")
    message("Служебное: /checker reload, /checker status")
    message("Настройки: /checker set [leaders/friends/admins/autoupdate] [on/off]")
    message("Оверлей: /checker set [x/y/font/fontsize] [значение]")
    message("GUI: /checkerui")
end

checker_status = function()
    message("Версия скрипта: " .. APP_VERSION)
    message(string.format(
        "Лидеры=%s, друзья=%s, админы=%s, автообновление=%s",
        tostring(config.checker.leaders_checker_status),
        tostring(config.checker.friends_checker_status),
        tostring(config.checker.admins_checker_status),
        tostring(config.checker.admin_checker_auto_update)
    ))

    message(string.format(
        "Оверлей: x=%s y=%s, шрифт=%s, размер=%s",
        tostring(config.overlay.xpos),
        tostring(config.overlay.ypos),
        tostring(config.overlay.font),
        tostring(config.overlay.font_size)
    ))
end

parse_admin_line = function(text)
    if text == nil or text == "" then
        return nil, nil, nil
    end

    local parsed_text = cp1251_to_utf8(text)
    local nickname, tracked_id, level = string.match(parsed_text, "([%w_]+)%[(%d+)%]%s*%((S%d)%s+lvl%)")
    if nickname == nil then
        nickname, tracked_id, level = string.match(parsed_text, "([%w_]+)%[(%d+)%]%s*%((%d+)%s+lvl%)")
    end

    tracked_id = tonumber(tracked_id)
    level = normalize_admin_level(level)

    if nickname == nil or tracked_id == nil or level == "-1" then
        return nil, nil, nil
    end

    return nickname, tracked_id, level
end

update_admin_from_line = function(text, local_name)
    local nickname, tracked_id, level = parse_admin_line(text)
    if nickname == nil or same_name(local_name, nickname) then
        return false
    end

    local index = find_index_by_name(admins_nick, nickname)
    if index == nil then
        upsert_admin(nickname, level, tracked_id)
        message(string.format("В чекер добавлен администратор %s [%d], уровень %s.", nickname, tracked_id, level))
        return true
    end

    local old_level = normalize_admin_level(admins_lvl[index])
    local old_id = tonumber(admins_id[index]) or -1
    admins_id[index] = tracked_id

    if old_level ~= level then
        admins_lvl[index] = level
        save_admins()
        message(string.format("Обновлён уровень администратора %s: %s -> %s.", nickname, old_level, level))
        return true
    end

    if old_id ~= tracked_id then
        save_admins()
        message(string.format("Обновлён ID администратора %s: [%d].", nickname, tracked_id))
        return true
    end

    return false
end

refresh_leaders_from_dialog = function(text)
    if text == nil or text == "" then
        return false
    end

    local parsed_text = cp1251_to_utf8(text)
    local new_nick = {}
    local new_org = {}
    local new_org_name = {}
    local parsed = 0

    for line in string.gmatch(parsed_text, "[^\r\n]+") do
        local nickname, organization = string.match(line, "^([^\t]+)\t([^\t]+)")
        if nickname ~= nil and organization ~= nil then
            nickname = trim(nickname)
            organization = trim(organization)

            if nickname ~= "" and nickname ~= "Имя" then
                parsed = parsed + 1
                table.insert(new_nick, nickname)
                table.insert(new_org, leader_org_id_from_name(organization))
                table.insert(new_org_name, organization)
            end
        end
    end

    if parsed == 0 then
        return false
    end

    leaders_nick = new_nick
    leaders_org = new_org
    leaders_org_name = new_org_name
    leaders_id = {}

    for _ = 1, #leaders_nick do
        table.insert(leaders_id, -1)
    end

    save_leaders()
    sync_online_ids()
    message(string.format("Список лидеров обновлён из диалога /leaders. Записей: %d.", parsed))
    return true
end

function sampOnPlayerJoin(player_id, _, _, nickname)
    nickname = cp1251_to_utf8(nickname)

    for index, tracked_name in ipairs(admins_nick) do
        if same_name(tracked_name, nickname) then
            admins_id[index] = player_id

            if sampIsLocalPlayerSpawned() then
                local level = normalize_admin_level(admins_lvl[index])

                if level == "S1" or level == "S2" or level == "S3" then
                    message(string.format("Подключился ютубер-администратор %s уровня, %s[%d].", level, nickname, player_id))
                elseif level == "7" or level == "6" then
                    message(string.format("Подключился главный администратор, %s[%d].", nickname, player_id))
                elseif level == "5" then
                    message(string.format("Подключился зам. главного администратора, %s[%d].", nickname, player_id))
                elseif level == "1" or level == "2" or level == "3" or level == "4" then
                    message(string.format("Подключился администратор %s уровня, %s[%d].", level, nickname, player_id))
                else
                    message(string.format("Подключился администратор %s[%d].", nickname, player_id))
                end
            end

            break
        end
    end

    for index, tracked_name in ipairs(leaders_nick) do
        if same_name(tracked_name, nickname) then
            leaders_id[index] = player_id

            if sampIsLocalPlayerSpawned() then
                message(string.format("Подключился лидер %s, %s[%d].", normalize_leader_org_title(leaders_org_name[index], leaders_org[index]), nickname, player_id))
            end

            break
        end
    end

    for index, tracked_name in ipairs(friends_nick) do
        if same_name(tracked_name, nickname) then
            friends_id[index] = player_id

            if sampIsLocalPlayerSpawned() then
                message(string.format("%s[%d] подключился.", nickname, player_id))
            end

            break
        end
    end
end

function sampOnPlayerQuit(player_id, _)
    for index, tracked_id in ipairs(admins_id) do
        if tracked_id == player_id then
            admins_id[index] = -1
            message(string.format("Администратор %s[%d] отключился.", admins_nick[index], player_id))
            break
        end
    end

    for index, tracked_id in ipairs(leaders_id) do
        if tracked_id == player_id then
            leaders_id[index] = -1
            message(string.format("Лидер %s[%d] отключился.", leaders_nick[index], player_id))
            break
        end
    end

    for index, tracked_id in ipairs(friends_id) do
        if tracked_id == player_id then
            friends_id[index] = -1
            message(string.format("%s[%d] отключился.", friends_nick[index], player_id))
            break
        end
    end
end

function sampOnServerMessage(color, text)
    if config == nil or not config.checker.admin_checker_auto_update then
        return
    end

    local parsed_text = cp1251_to_utf8(text)
    if string.find(parsed_text, "Админы онлайн", 1, true) then
        start_admin_refresh()
        return
    end

    local local_name = nil
    local ok, player_id = sampGetPlayerIdByCharHandle(PLAYER_PED)
    if ok then
        local_name = cp1251_to_utf8(sampGetPlayerNickname(player_id))
    end

    update_admin_from_line(text, local_name)

    if admin_refresh_active then
        local nickname = parse_admin_line(text)
        if nickname ~= nil then
            admin_refresh_seen_nicks[string.lower(nickname)] = true
            admin_refresh_last_line_at = os.clock()
        end
    end
end

function sampOnShowDialog(dialog_id, style, title, button1, button2, text)
    if config == nil or config.checker.source_updates_enabled == false then
        return
    end

    local raw_title = tostring(title or '')
    local parsed_title = cp1251_to_utf8(raw_title)
    local is_leaders_dialog = string.find(parsed_title, 'Лидеры', 1, true) or string.find(raw_title, 'Лидеры', 1, true)

    if style == 5 and dialog_id == 424 and is_leaders_dialog then
        refresh_leaders_from_dialog(text)
    elseif style == 5 and dialog_id == 0 and string.find(parsed_title, "S уровня", 1, true) then
        refresh_s_admins_from_dialog(text)
    end
end

function sampev.onServerMessage(color, text)
    return sampOnServerMessage(color, text)
end

function sampev.onShowDialog(dialog_id, style, title, button1, button2, text)
    return sampOnShowDialog(dialog_id, style, title, button1, button2, text)
end

function sampev.onPlayerJoin(player_id, color, is_npc, nickname)
    return sampOnPlayerJoin(player_id, color, is_npc, nickname)
end

function sampev.onPlayerQuit(player_id, reason)
    return sampOnPlayerQuit(player_id, reason)
end

message = function(text)
    text = tostring(text or "")

    if string.find(text, "Standalone%-") then
        text = "Команды: /ac"
    elseif string.find(text, "ImGui Р", 1, true) then
        text = "ImGui не найден. GUI и перенос мышкой отключены."
    elseif string.find(text, "ADV-RP.RU ADM CHECKER by Casual Alvarez Р", 1, true) then
        text = "Команды: /ac"
    end

    sampAddChatMessage(utf8_to_cp1251("{D9A657}[ADM] {E8E8E8}" .. text), -1)
end

message = function(text)
    text = tostring(text or "")

    if string.find(text, "Standalone%-") then
        text = "Команды: /ac"
    elseif text == "ADV-RP.RU ADM CHECKER by Casual Alvarez. GUI: /checkerui" or text == "ADV-RP.RU ADM CHECKER by Casual Alvarez. GUI: /acmenu" then
        text = "GUI: /acmenu"
    elseif string.find(text, "ImGui Р", 1, true) then
        text = "ImGui не найден. GUI отключён."
    elseif string.find(text, "ADV-RP.RU ADM CHECKER by Casual Alvarez Р", 1, true) then
        text = "Команды: /ac"
    end

    sampAddChatMessage(utf8_to_cp1251("{D9A657}[ADM] {E8E8E8}" .. text), -1)
end

admin_role_title = function(level)
    level = normalize_admin_level(level)

    if level == "7" then
        return "Красный Администратор"
    elseif level == "6" then
        return "Главный Администратор"
    elseif level == "5" then
        return "Заместитель Главного Администратора"
    elseif level == "4" then
        return "Модератор"
    elseif level == "3" then
        return "Младший модератор"
    elseif level == "2" or level == "1" then
        return "Хелпер"
    elseif level == "S1" or level == "S2" or level == "S3" then
        return "YouTube"
    end

    return "Администратор"
end

local function build_overlay_line(number, nickname, player_id, color_prefix, suffix)
    local parts = {}

    if color_prefix ~= nil and color_prefix ~= "" then
        table.insert(parts, color_prefix)
    end

    if config.overlay.show_numbering ~= false then
        table.insert(parts, tostring(number) .. ". ")
    end

    table.insert(parts, nickname)

    if config.overlay.show_ids ~= false then
        table.insert(parts, " [" .. tostring(player_id) .. "]")
    end

    if suffix ~= nil and suffix ~= "" then
        table.insert(parts, suffix)
    end

    return table.concat(parts)
end

draw_leaders = function(x, y)
    local count = 0
    local line_height = renderGetFontDrawHeight(font)

    draw_line("Лидеры в сети:", x, y, 0xFAFFFFFF)
    y = y + 0.5

    for index, player_id in ipairs(leaders_id) do
        if player_id ~= -1 and is_leader_org_visible(normalize_leader_org_title(leaders_org_name[index], leaders_org[index])) then
            count = count + 1

            local nickname = format_display_nickname(leaders_nick[index])
            local player_color = sampGetPlayerColor(player_id)
            local _, red, green, blue = explode_argb(player_color)
            red, green, blue = normalize_rgb(red, green, blue)

            local line = build_overlay_line(count, nickname, player_id, string.format("{%02X%02X%02X}", red, green, blue), "")
            if sampIsPlayerPaused(player_id) then
                line = line .. " {FF0000}[AFK]"
            end

            y = y + line_height
            if player_has_character(player_id) then
                line = line .. " {808080}[#]"
            end

            draw_line(line, x, y, 0xFFFFFFFF)
        end
    end

    if count == 0 then
        y = y + line_height
        draw_line("Лидеров в сети нет", x, y, 0x64FFFFFF)
    end

    return y
end

draw_friends = function(x, y, add_gap)
    local count = 0
    local line_height = renderGetFontDrawHeight(font)

    if add_gap then
        y = y + line_height * 1.3
    end

    draw_line("Друзья в сети:", x, y, 0xFAFFFFFF)
    y = y + 0.5

    for index, player_id in ipairs(friends_id) do
        if player_id ~= -1 then
            count = count + 1

            local nickname = format_display_nickname(friends_nick[index])
            local player_color = sampGetPlayerColor(player_id)
            local _, red, green, blue = explode_argb(player_color)
            red, green, blue = normalize_rgb(red, green, blue)

            local line = build_overlay_line(count, nickname, player_id, string.format("{%02X%02X%02X}", red, green, blue), "")
            if sampIsPlayerPaused(player_id) then
                line = line .. " {FF0000}[AFK]"
            end

            y = y + line_height
            if player_has_character(player_id) then
                line = line .. " {808080}[#]"
            end

            draw_line(line, x, y, 0xFFFFFFFF)
        end
    end

    if count == 0 then
        y = y + line_height
        draw_line("Друзей в сети нет", x, y, 0x64FFFFFF)
    end

    return y
end

draw_admins = function(x, y, add_gap)
    local count = 0
    local line_height = renderGetFontDrawHeight(font)

    if add_gap then
        y = y + line_height * 1.3
    end

    draw_line("Администраторы в сети:", x, y, 0xFAFFFFFF)
    y = y + 0.5

    for index, player_id in ipairs(admins_id) do
        if player_id ~= -1 then
            count = count + 1

            local nickname = admins_nick[index]
            local level = admins_lvl[index]
            local line_color = admin_level_color(level)
            local display_nickname = format_display_nickname(nickname)
            local suffix = build_admin_suffix(index, level)

            if is_youtube_level(level) then
                display_nickname = format_youtube_nickname(nickname, level)
            end

            local line = build_overlay_line(count, display_nickname, player_id, "", suffix)
            if sampIsPlayerPaused(player_id) then
                line = line .. " {FF0000}[AFK]"
            end

            y = y + line_height
            if player_has_character(player_id) then
                line = line .. " {808080}[#]"
            end

            if is_youtube_level(level) then
                draw_line(line, x, y, 0xFFFFFFFF)
            else
                draw_line(line, x, y, line_color)
            end
        end
    end

    if count == 0 then
        y = y + line_height
        draw_line("Администраторов в сети нет", x, y, 0x64FFFFFF)
    end

    return y
end


release_game_input = function()
    if showCursor ~= nil then
        pcall(showCursor, false, false)
    end
    if lockPlayerControl ~= nil then
        pcall(lockPlayerControl, false)
    end
    if sampToggleCursor ~= nil then
        pcall(sampToggleCursor, false)
    end
end

sync_imgui_input = function()
    if not imgui_loaded then
        return
    end

    local should_process = (checker_window ~= nil and checker_window.v) or (help_window ~= nil and help_window.v)
    imgui.Process = should_process
    imgui.ShowCursor = should_process

    if not should_process then
        release_game_input()
    end
end

toggle_checker_window = function()
    if not imgui_loaded or checker_window == nil then
        message("ImGui недоступен.")
        return
    end

    checker_window.v = not checker_window.v
    sync_imgui_input()

    if checker_window.v then
        checker_window_just_opened = true
        refresh_gui_buffers()
    else
        checker_window_just_opened = false
        overlay_move_mode.v = false
        overlay_drag_active = false
        overlay_drag_saved = false
        sync_imgui_input()
    end
end

draw_admin_editor = function()
    imgui.BeginChild("admins_list", imgui.ImVec2(420, 520), true)
    imgui.Text("Список")
    imgui.Separator()

    if imgui.Button("Добавить нового##admin_add_new", imgui.ImVec2(-1, 28)) then
        select_admin(-1)
    end
    imgui.Separator()

    for index = 1, #admins_nick do
        if imgui.Selectable(admin_list_label(index), selected_admin.v == index - 1) then
            select_admin(index - 1)
        end
    end

    imgui.EndChild()
    imgui.SameLine()
    imgui.BeginChild("admins_edit", imgui.ImVec2(0, 520), true)
    imgui.Text("Карточка")
    imgui.Separator()

    if selected_admin.v >= 0 and admins_nick[selected_admin.v + 1] ~= nil then
        local idx = selected_admin.v + 1
        imgui.Text("Ник: " .. format_display_nickname(admins_nick[idx]))
        imgui.Text("Уровень: " .. admin_level_text(admins_lvl[idx]))
        imgui.Text("Должность: " .. get_admin_role_title(idx, admins_lvl[idx]))
        imgui.Text((tonumber(admins_id[idx]) or -1) ~= -1 and "Статус: онлайн" or "Статус: оффлайн")
        if draw_inline_toggle("Оповещать в чат", "##admin_notify_selected", admins_notify[idx] ~= false) then
            admins_notify[idx] = not (admins_notify[idx] ~= false)
            save_admins()
        end
        if draw_inline_toggle("Звук", "##admin_sound_notify_selected", admins_sound_notify[idx] == true) then
            admins_sound_notify[idx] = not (admins_sound_notify[idx] == true)
            if admins_sound_notify[idx] == true then
                config.checker.sound_notify_enabled = true
                config.checker.sound_notify_admins = true
                save_config()
            end
            save_admins()
        end
        if draw_inline_toggle("Не обновлять", "##admin_locked_selected", admins_locked[idx] == true) then
            admins_locked[idx] = not (admins_locked[idx] == true)
            save_admins()
        end
        imgui.Separator()
    else
        imgui.Text("Выберите запись слева.")
        imgui.Separator()
    end

    imgui.Text("Ник")
    imgui.InputText("##admin_name", admin_name_buffer)
    imgui.Text("Уровень")
    imgui.InputText("##admin_level", admin_level_buffer)
    imgui.Text("Должность")
    imgui.InputText("##admin_role", admin_role_buffer)
    imgui.Spacing()

    if imgui.Button("Сохранить", imgui.ImVec2(-1, 32)) then
        local nickname = trim(admin_name_buffer.v)

        if nickname ~= "" then
            upsert_admin(nickname, admin_level_buffer.v, -1, admin_role_buffer.v)
            sync_online_ids()
            local sorted_index = find_index_by_name(admins_nick, nickname)

            if sorted_index ~= nil then
                select_admin(sorted_index - 1)
            end
        end
    end

    if imgui.Button("Удалить", imgui.ImVec2(-1, 32)) then
        if selected_admin.v >= 0 and admins_nick[selected_admin.v + 1] ~= nil then
            remove_admin(admins_nick[selected_admin.v + 1])
            sync_online_ids()
            select_admin(-1)
        end
    end

    imgui.EndChild()
end

draw_leader_editor = function()
    imgui.BeginChild("leaders_list", imgui.ImVec2(420, 520), true)
    imgui.Text("Список")
    imgui.Separator()

    if imgui.Button("Добавить нового##leader_add_new", imgui.ImVec2(-1, 28)) then
        select_leader(-1)
    end
    imgui.Separator()

    for index = 1, #leaders_nick do
        if imgui.Selectable(leader_list_label(index), selected_leader.v == index - 1) then
            select_leader(index - 1)
        end
    end

    imgui.EndChild()
    imgui.SameLine()
    imgui.BeginChild("leaders_edit", imgui.ImVec2(0, 520), true)
    imgui.Text("Карточка")
    imgui.Separator()

    if selected_leader.v >= 0 and leaders_nick[selected_leader.v + 1] ~= nil then
        local idx = selected_leader.v + 1
        imgui.Text("Ник: " .. format_display_nickname(leaders_nick[idx]))
        imgui.Text("Фракция: " .. normalize_leader_org_title(leaders_org_name[idx], leaders_org[idx]))
        imgui.Text((tonumber(leaders_id[idx]) or -1) ~= -1 and "Статус: онлайн" or "Статус: оффлайн")
        if draw_inline_toggle("Оповещать в чат", "##leader_notify_selected", leaders_notify[idx] ~= false) then
            leaders_notify[idx] = not (leaders_notify[idx] ~= false)
            save_leaders()
        end
        if draw_inline_toggle("Звук", "##leader_sound_notify_selected", leaders_sound_notify[idx] == true) then
            leaders_sound_notify[idx] = not (leaders_sound_notify[idx] == true)
            if leaders_sound_notify[idx] == true then
                config.checker.sound_notify_enabled = true
                config.checker.sound_notify_leaders = true
                save_config()
            end
            save_leaders()
        end
        imgui.Separator()
    else
        imgui.Text("Выберите запись слева.")
        imgui.Separator()
    end

    imgui.Text("Ник")
    imgui.InputText("##leader_name", leader_name_buffer)
    imgui.Text("Фракция")
    imgui.InputText("##leader_org", leader_org_buffer)
    imgui.Spacing()

    if imgui.Button("Сохранить", imgui.ImVec2(-1, 32)) then
        local nickname = trim(leader_name_buffer.v)

        if nickname ~= "" then
            local existing_index = find_index_by_name(leaders_nick, nickname)
            local org_title = trim(leader_org_buffer.v)
            local org_id = tonumber(org_title) or leader_org_id_from_name(org_title)
            upsert_leader(nickname, org_id, -1, org_title)
            sync_online_ids()

            if existing_index ~= nil then
                select_leader(existing_index - 1)
            else
                select_leader(#leaders_nick - 1)
            end
        end
    end

    if imgui.Button("Удалить", imgui.ImVec2(-1, 32)) then
        if selected_leader.v >= 0 and leaders_nick[selected_leader.v + 1] ~= nil then
            remove_leader(leaders_nick[selected_leader.v + 1])
            sync_online_ids()
            select_leader(-1)
            set_buffer(leader_name_buffer, "")
            set_buffer(leader_org_buffer, "")
        end
    end

    imgui.EndChild()
end

draw_friend_editor = function()
    imgui.BeginChild("friends_list", imgui.ImVec2(420, 520), true)
    imgui.Text("Список")
    imgui.Separator()

    if imgui.Button("Добавить нового##friend_add_new", imgui.ImVec2(-1, 28)) then
        select_friend(-1)
    end
    imgui.Separator()

    for index = 1, #friends_nick do
        if imgui.Selectable(friend_list_label(index), selected_friend.v == index - 1) then
            select_friend(index - 1)
        end
    end

    imgui.EndChild()
    imgui.SameLine()
    imgui.BeginChild("friends_edit", imgui.ImVec2(0, 520), true)
    imgui.Text("Карточка")
    imgui.Separator()

    if selected_friend.v >= 0 and friends_nick[selected_friend.v + 1] ~= nil then
        local idx = selected_friend.v + 1
        imgui.Text("Ник: " .. format_display_nickname(friends_nick[idx]))
        imgui.Text(is_best_friend(idx) and "Тип: лучший друг" or "Тип: друг")
        imgui.Text((tonumber(friends_id[idx]) or -1) ~= -1 and "Статус: онлайн" or "Статус: оффлайн")
        if draw_inline_toggle("Оповещать в чат", "##friend_notify_selected", friends_notify[idx] ~= false) then
            friends_notify[idx] = not (friends_notify[idx] ~= false)
            save_friends()
        end
        if draw_inline_toggle("Звук", "##friend_sound_notify_selected", friends_sound_notify[idx] == true) then
            friends_sound_notify[idx] = not (friends_sound_notify[idx] == true)
            if friends_sound_notify[idx] == true then
                config.checker.sound_notify_enabled = true
                config.checker.sound_notify_friends = true
                save_config()
            end
            save_friends()
        end
        imgui.Separator()
    else
        imgui.Text("Выберите запись слева.")
        imgui.Separator()
    end

    imgui.Text("Ник")
    imgui.InputText("##friend_name", friend_name_buffer)
    if draw_inline_toggle("Лучший друг", "##friend_best_toggle", friend_best_toggle.v) then
        friend_best_toggle.v = not friend_best_toggle.v
    end
    imgui.Spacing()

    if imgui.Button("Сохранить", imgui.ImVec2(-1, 32)) then
        local nickname = trim(friend_name_buffer.v)

        if nickname ~= "" then
            local existing_index = find_index_by_name(friends_nick, nickname)
            upsert_friend(nickname, -1, friend_best_toggle.v)
            sync_online_ids()

            if existing_index ~= nil then
                select_friend(existing_index - 1)
            else
                select_friend(#friends_nick - 1)
            end
        end
    end

    if imgui.Button("Удалить", imgui.ImVec2(-1, 32)) then
        if selected_friend.v >= 0 and friends_nick[selected_friend.v + 1] ~= nil then
            remove_friend(friends_nick[selected_friend.v + 1])
            sync_online_ids()
            select_friend(-1)
            set_buffer(friend_name_buffer, "")
        end
    end

    imgui.EndChild()
end

local function draw_toggle_switch(id, value)
    local draw_list = imgui.GetWindowDrawList()
    local pos = imgui.GetCursorScreenPos()
    local width = 34
    local height = 18
    local radius = height / 2
    local enabled = value == true
    local bg_color = enabled and 0xAA303030 or 0xAA2A2A2A
    local knob_color = enabled and 0xFF3030FF or 0xFF707070
    local knob_x = enabled and (pos.x + width - radius) or (pos.x + radius)
    local knob_y = pos.y + radius

    draw_list:AddRectFilled(imgui.ImVec2(pos.x, pos.y), imgui.ImVec2(pos.x + width, pos.y + height), bg_color, radius)
    draw_list:AddCircleFilled(imgui.ImVec2(knob_x, knob_y), radius - 1, knob_color, 24)

    imgui.InvisibleButton(id, imgui.ImVec2(width, height))
    return imgui.IsItemClicked()
end

local function draw_toggle_row(label, value)
    imgui.Text(label)
    imgui.SameLine(250)
    return draw_toggle_switch("##toggle_" .. label, value)
end

draw_inline_toggle = function(label, id, value)
    local clicked = draw_toggle_switch(id, value)
    imgui.SameLine()
    imgui.Text(label)
    return clicked
end

draw_settings_editor = function()
    imgui.BeginChild("settings_left", imgui.ImVec2(500, 520), true)
    imgui.Text("Общее")
    imgui.Separator()

    if draw_toggle_row("Показывать лидеров", config.checker.leaders_checker_status) then
        config.checker.leaders_checker_status = not config.checker.leaders_checker_status
        save_config()
    end

    if draw_toggle_row("Показывать друзей", config.checker.friends_checker_status) then
        config.checker.friends_checker_status = not config.checker.friends_checker_status
        save_config()
    end

    if draw_toggle_row("Показывать администраторов", config.checker.admins_checker_status) then
        config.checker.admins_checker_status = not config.checker.admins_checker_status
        save_config()
    end

    if draw_toggle_row("Обновления из источников", config.checker.source_updates_enabled) then
        config.checker.source_updates_enabled = not config.checker.source_updates_enabled
        save_config()
    end

    if draw_toggle_row("Автообновление админов из /admins", config.checker.admin_checker_auto_update) then
        config.checker.admin_checker_auto_update = not config.checker.admin_checker_auto_update
        save_config()
    end

    if draw_toggle_row("Уведомлять о скрытых лидерах", config.checker.notify_hidden_leader_events) then
        config.checker.notify_hidden_leader_events = not config.checker.notify_hidden_leader_events
        save_config()
    end

    imgui.Text("Уведомления о друзьях")
    imgui.SameLine(330)
    local all_active = config.checker.friend_notify_mode == "all"
    if all_active then
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.73, 0.24, 0.20, 0.90))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.82, 0.29, 0.24, 0.95))
        imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.65, 0.20, 0.17, 1.00))
    end
    if imgui.Button("Все##friend_notify_all", imgui.ImVec2(70, 24)) then
        config.checker.friend_notify_mode = "all"
        save_config()
    end
    if all_active then
        imgui.PopStyleColor(3)
    end
    imgui.SameLine()
    local best_active = config.checker.friend_notify_mode == "best"
    if best_active then
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.73, 0.24, 0.20, 0.90))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.82, 0.29, 0.24, 0.95))
        imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.65, 0.20, 0.17, 1.00))
    end
    if imgui.Button("Лучшие##friend_notify_best", imgui.ImVec2(90, 24)) then
        config.checker.friend_notify_mode = "best"
        save_config()
    end
    if best_active then
        imgui.PopStyleColor(3)
    end

    if draw_toggle_row("Показывать уровень админа", config.overlay.admin_show_level) then
        config.overlay.admin_show_level = not config.overlay.admin_show_level
        save_config()
    end

    if draw_toggle_row("Показывать должность", config.overlay.admin_show_role) then
        config.overlay.admin_show_role = not config.overlay.admin_show_role
        save_config()
    end

    if draw_toggle_row("Показывать фон чекера", config.overlay.show_background) then
        config.overlay.show_background = not config.overlay.show_background
        save_config()
    end

    if draw_toggle_row("Перемещать чекер мышкой", overlay_move_mode.v) then
        overlay_move_mode.v = not overlay_move_mode.v
        overlay_drag_active = false
        overlay_drag_saved = false
    end

    imgui.Separator()
    imgui.Text("Фракции лидеров")
    imgui.BeginChild("leader_org_filters", imgui.ImVec2(0, 320), true)

    local leader_org_options = collect_leader_org_options()
    if #leader_org_options == 0 then
        imgui.Text("Список появится после /leaders")
    else
        if imgui.Button("Все", imgui.ImVec2(90, 24)) then
            set_all_leader_orgs_visible(true)
        end
        imgui.SameLine()
        if imgui.Button("Скрыть все", imgui.ImVec2(110, 24)) then
            set_all_leader_orgs_visible(false)
        end
        imgui.SameLine()
        if imgui.Button("Инвертировать", imgui.ImVec2(120, 24)) then
            invert_leader_org_visibility()
        end

        imgui.Separator()
        imgui.Columns(2, "leader_org_columns", false)

        for _, org_title in ipairs(leader_org_options) do
            if imgui.Checkbox(org_title, imgui.ImBool(is_leader_org_visible(org_title))) then
                set_leader_org_visible(org_title, not is_leader_org_visible(org_title))
            end
            imgui.NextColumn()
        end

        imgui.Columns(1)
    end

    imgui.EndChild()
    imgui.EndChild()
    imgui.SameLine()
    imgui.BeginChild("settings_right", imgui.ImVec2(0, 520), true)
    imgui.Text("Шрифт")
    imgui.Separator()
    local font_items = table.concat(FONT_OPTIONS, "\0") .. "\0\0"
    imgui.Combo("##font_selector", selected_font_index, font_items)

    imgui.BeginChild("font_size_controls", imgui.ImVec2(0, 100), true)
    imgui.Text("Размер")

    if imgui.Button("Меньше", imgui.ImVec2(150, 30)) then
        font_size_value.v = math.max(6, font_size_value.v - 1)
    end

    imgui.SameLine()

    if imgui.Button("Больше", imgui.ImVec2(150, 30)) then
        font_size_value.v = math.min(20, font_size_value.v + 1)
    end

    imgui.Text("Текущий размер: " .. tostring(font_size_value.v))
    imgui.EndChild()

    if imgui.Button("Применить", imgui.ImVec2(-1, 32)) then
        local font_index = math.max(1, math.min(#FONT_OPTIONS, selected_font_index.v + 1))
        config.overlay.font = FONT_OPTIONS[font_index]
        config.overlay.font_size = math.max(6, math.min(20, font_size_value.v))
        save_config()
        reload_font()
        refresh_gui_buffers()
    end

    if imgui.Button("Обновить списки", imgui.ImVec2(-1, 32)) then
        load_all_lists()
        sync_online_ids()
    end

    if imgui.Button("Сохранить позицию", imgui.ImVec2(-1, 32)) then
        save_config()
    end

    imgui.EndChild()
end

draw_settings_editor = function()
    imgui.BeginChild("settings_left", imgui.ImVec2(500, 520), true)
    imgui.Text(utf8_to_cp1251("Общее"))
    imgui.Separator()

    if draw_toggle_row(utf8_to_cp1251("Показывать лидеров"), config.checker.leaders_checker_status) then
        config.checker.leaders_checker_status = not config.checker.leaders_checker_status
        save_config()
    end

    if draw_toggle_row(utf8_to_cp1251("Показывать друзей"), config.checker.friends_checker_status) then
        config.checker.friends_checker_status = not config.checker.friends_checker_status
        save_config()
    end

    if draw_toggle_row(utf8_to_cp1251("Показывать администраторов"), config.checker.admins_checker_status) then
        config.checker.admins_checker_status = not config.checker.admins_checker_status
        save_config()
    end

    if draw_toggle_row(utf8_to_cp1251("Автообновление админов из /admins"), config.checker.admin_checker_auto_update) then
        config.checker.admin_checker_auto_update = not config.checker.admin_checker_auto_update
        save_config()
    end

    if draw_toggle_row(utf8_to_cp1251("Уведомлять о скрытых лидерах"), config.checker.notify_hidden_leader_events) then
        config.checker.notify_hidden_leader_events = not config.checker.notify_hidden_leader_events
        save_config()
    end

    imgui.Text(utf8_to_cp1251("Уведомления о друзьях"))
    imgui.SameLine(330)
    local all_active = config.checker.friend_notify_mode == "all"
    if all_active then
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.73, 0.24, 0.20, 0.90))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.82, 0.29, 0.24, 0.95))
        imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.65, 0.20, 0.17, 1.00))
    end
    if imgui.Button(utf8_to_cp1251("Все##friend_notify_all"), imgui.ImVec2(56, 22)) then
        config.checker.friend_notify_mode = "all"
        save_config()
    end
    if all_active then
        imgui.PopStyleColor(3)
    end
    imgui.SameLine()
    local best_active = config.checker.friend_notify_mode == "best"
    if best_active then
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.73, 0.24, 0.20, 0.90))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.82, 0.29, 0.24, 0.95))
        imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.65, 0.20, 0.17, 1.00))
    end
    if imgui.Button(utf8_to_cp1251("Лучшие##friend_notify_best"), imgui.ImVec2(72, 22)) then
        config.checker.friend_notify_mode = "best"
        save_config()
    end
    if best_active then
        imgui.PopStyleColor(3)
    end

    if draw_toggle_row(utf8_to_cp1251("Показывать уровень админа"), config.overlay.admin_show_level) then
        config.overlay.admin_show_level = not config.overlay.admin_show_level
        save_config()
    end

    if draw_toggle_row(utf8_to_cp1251("Показывать должность"), config.overlay.admin_show_role) then
        config.overlay.admin_show_role = not config.overlay.admin_show_role
        save_config()
    end

    if draw_toggle_row(utf8_to_cp1251("Показывать фон чекера"), config.overlay.show_background) then
        config.overlay.show_background = not config.overlay.show_background
        save_config()
    end

    if draw_toggle_row(utf8_to_cp1251("Перемещать чекер мышкой"), overlay_move_mode.v) then
        overlay_move_mode.v = not overlay_move_mode.v
        overlay_drag_active = false
        overlay_drag_saved = false
    end

    imgui.Separator()
    imgui.Text(utf8_to_cp1251("Фракции лидеров"))
    imgui.BeginChild("leader_org_filters", imgui.ImVec2(0, 320), true)

    local leader_org_options = collect_leader_org_options()
    if #leader_org_options == 0 then
        imgui.Text(utf8_to_cp1251("Список появится после /leaders"))
    else
        if imgui.Button(utf8_to_cp1251("Все"), imgui.ImVec2(90, 24)) then
            set_all_leader_orgs_visible(true)
        end
        imgui.SameLine()
        if imgui.Button(utf8_to_cp1251("Скрыть все"), imgui.ImVec2(110, 24)) then
            set_all_leader_orgs_visible(false)
        end

        imgui.Separator()
        imgui.Columns(2, "leader_org_columns_clean", false)

        local split_index = math.ceil(#leader_org_options / 2)
        for index = 1, split_index do
            local org_title = leader_org_options[index]
            if org_title and imgui.Checkbox(utf8_to_cp1251(org_title), imgui.ImBool(is_leader_org_visible(org_title))) then
                set_leader_org_visible(org_title, not is_leader_org_visible(org_title))
            end
        end

        imgui.NextColumn()

        for index = split_index + 1, #leader_org_options do
            local org_title = leader_org_options[index]
            if org_title and imgui.Checkbox(utf8_to_cp1251(org_title), imgui.ImBool(is_leader_org_visible(org_title))) then
                set_leader_org_visible(org_title, not is_leader_org_visible(org_title))
            end
        end

        imgui.Columns(1)
    end

    imgui.EndChild()
    imgui.EndChild()
    imgui.SameLine()
    imgui.BeginChild("settings_right", imgui.ImVec2(0, 520), true)
    imgui.Text(utf8_to_cp1251("Шрифт"))
    imgui.Separator()
    local font_items = table.concat(FONT_OPTIONS, "\0") .. "\0\0"
    imgui.Combo("##font_selector", selected_font_index, font_items)

    imgui.BeginChild("font_size_controls", imgui.ImVec2(0, 100), true)
    imgui.Text(utf8_to_cp1251("Размер"))

    if imgui.Button(utf8_to_cp1251("Меньше"), imgui.ImVec2(150, 30)) then
        font_size_value.v = math.max(6, font_size_value.v - 1)
    end

    imgui.SameLine()

    if imgui.Button(utf8_to_cp1251("Больше"), imgui.ImVec2(150, 30)) then
        font_size_value.v = math.min(20, font_size_value.v + 1)
    end

    imgui.Text(utf8_to_cp1251("Текущий размер: ") .. tostring(font_size_value.v))
    imgui.EndChild()

    if imgui.Button(utf8_to_cp1251("Применить"), imgui.ImVec2(-1, 32)) then
        local font_index = math.max(1, math.min(#FONT_OPTIONS, selected_font_index.v + 1))
        config.overlay.font = FONT_OPTIONS[font_index]
        config.overlay.font_size = math.max(6, math.min(20, font_size_value.v))
        save_config()
        reload_font()
        refresh_gui_buffers()
    end

    if imgui.Button(utf8_to_cp1251("Обновить списки"), imgui.ImVec2(-1, 32)) then
        load_all_lists()
        sync_online_ids()
    end

    if imgui.Button(utf8_to_cp1251("Сохранить позицию"), imgui.ImVec2(-1, 32)) then
        save_config()
    end

    imgui.EndChild()
end

draw_settings_editor = function()
    imgui.BeginChild("settings_left", imgui.ImVec2(500, 520), true)
    imgui.Text("Общее")
    imgui.Separator()

    if draw_toggle_row("Показывать лидеров", config.checker.leaders_checker_status) then
        config.checker.leaders_checker_status = not config.checker.leaders_checker_status
        save_config()
    end

    if draw_toggle_row("Показывать друзей", config.checker.friends_checker_status) then
        config.checker.friends_checker_status = not config.checker.friends_checker_status
        save_config()
    end

    if draw_toggle_row("Показывать администраторов", config.checker.admins_checker_status) then
        config.checker.admins_checker_status = not config.checker.admins_checker_status
        save_config()
    end

    if draw_toggle_row("Автообновление админов из /admins", config.checker.admin_checker_auto_update) then
        config.checker.admin_checker_auto_update = not config.checker.admin_checker_auto_update
        save_config()
    end

    if draw_toggle_row("Уведомлять о скрытых лидерах", config.checker.notify_hidden_leader_events) then
        config.checker.notify_hidden_leader_events = not config.checker.notify_hidden_leader_events
        save_config()
    end

    imgui.Text("Уведомления о друзьях")
    imgui.SameLine(330)
    local all_active = config.checker.friend_notify_mode == "all"
    if all_active then
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.73, 0.24, 0.20, 0.90))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.82, 0.29, 0.24, 0.95))
        imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.65, 0.20, 0.17, 1.00))
    end
    if imgui.Button("Все##friend_notify_all", imgui.ImVec2(56, 22)) then
        config.checker.friend_notify_mode = "all"
        save_config()
    end
    if all_active then
        imgui.PopStyleColor(3)
    end
    imgui.SameLine()
    local best_active = config.checker.friend_notify_mode == "best"
    if best_active then
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.73, 0.24, 0.20, 0.90))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.82, 0.29, 0.24, 0.95))
        imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.65, 0.20, 0.17, 1.00))
    end
    if imgui.Button("Лучшие##friend_notify_best", imgui.ImVec2(72, 22)) then
        config.checker.friend_notify_mode = "best"
        save_config()
    end
    if best_active then
        imgui.PopStyleColor(3)
    end

    if draw_toggle_row("Показывать уровень админа", config.overlay.admin_show_level) then
        config.overlay.admin_show_level = not config.overlay.admin_show_level
        save_config()
    end

    if draw_toggle_row("Показывать должность", config.overlay.admin_show_role) then
        config.overlay.admin_show_role = not config.overlay.admin_show_role
        save_config()
    end

    if draw_toggle_row("Показывать фон чекера", config.overlay.show_background) then
        config.overlay.show_background = not config.overlay.show_background
        save_config()
    end

    if draw_toggle_row("Перемещать чекер мышкой", overlay_move_mode.v) then
        overlay_move_mode.v = not overlay_move_mode.v
        overlay_drag_active = false
        overlay_drag_saved = false
    end

    imgui.Separator()
    imgui.Text("Фракции лидеров")
    imgui.BeginChild("leader_org_filters", imgui.ImVec2(0, 320), true)

    local leader_org_options = collect_leader_org_options()
    if #leader_org_options == 0 then
        imgui.Text("Список появится после /leaders")
    else
        if imgui.Button("Все", imgui.ImVec2(90, 24)) then
            set_all_leader_orgs_visible(true)
        end
        imgui.SameLine()
        if imgui.Button("Скрыть все", imgui.ImVec2(110, 24)) then
            set_all_leader_orgs_visible(false)
        end

        imgui.Separator()
        local column_count = 4
        imgui.Columns(column_count, "leader_org_columns_clean", false)

        local chunk_size = math.ceil(#leader_org_options / column_count)
        for column = 1, column_count do
            local start_index = ((column - 1) * chunk_size) + 1
            local end_index = math.min(#leader_org_options, column * chunk_size)
            for index = start_index, end_index do
                local org_title = leader_org_options[index]
                if org_title and imgui.Checkbox(org_title, imgui.ImBool(is_leader_org_visible(org_title))) then
                    set_leader_org_visible(org_title, not is_leader_org_visible(org_title))
                end
            end
            if column < column_count then
                imgui.NextColumn()
            end
        end

        imgui.Columns(1)
    end

    imgui.EndChild()
    imgui.EndChild()
    imgui.SameLine()
    imgui.BeginChild("settings_right", imgui.ImVec2(0, 520), true)
    imgui.Text("Шрифт")
    imgui.Separator()
    local font_items = table.concat(FONT_OPTIONS, "\0") .. "\0\0"
    imgui.Combo("##font_selector", selected_font_index, font_items)

    imgui.BeginChild("font_size_controls", imgui.ImVec2(0, 100), true)
    imgui.Text("Размер")

    if imgui.Button("Меньше", imgui.ImVec2(150, 30)) then
        font_size_value.v = math.max(6, font_size_value.v - 1)
    end

    imgui.SameLine()

    if imgui.Button("Больше", imgui.ImVec2(150, 30)) then
        font_size_value.v = math.min(20, font_size_value.v + 1)
    end

    imgui.Text("Текущий размер: " .. tostring(font_size_value.v))
    imgui.EndChild()

    if imgui.Button("Применить", imgui.ImVec2(-1, 32)) then
        local font_index = math.max(1, math.min(#FONT_OPTIONS, selected_font_index.v + 1))
        config.overlay.font = FONT_OPTIONS[font_index]
        config.overlay.font_size = math.max(6, math.min(20, font_size_value.v))
        save_config()
        reload_font()
        refresh_gui_buffers()
    end

    if imgui.Button("Обновить списки", imgui.ImVec2(-1, 32)) then
        load_all_lists()
        sync_online_ids()
    end

    if imgui.Button("Сохранить позицию", imgui.ImVec2(-1, 32)) then
        save_config()
    end

    imgui.EndChild()
end

draw_settings_editor = function()
    imgui.BeginChild("settings_top_left", imgui.ImVec2(760, 300), true)
    imgui.Text("Общее")
    imgui.Separator()
    imgui.Columns(2, "settings_general_columns", false)

    if draw_toggle_row("Показывать лидеров", config.checker.leaders_checker_status) then
        config.checker.leaders_checker_status = not config.checker.leaders_checker_status
        save_config()
    end

    if draw_toggle_row("Показывать друзей", config.checker.friends_checker_status) then
        config.checker.friends_checker_status = not config.checker.friends_checker_status
        save_config()
    end

    if draw_toggle_row("Показывать администраторов", config.checker.admins_checker_status) then
        config.checker.admins_checker_status = not config.checker.admins_checker_status
        save_config()
    end

    if draw_toggle_row("Автообновление админов из /admins", config.checker.admin_checker_auto_update) then
        config.checker.admin_checker_auto_update = not config.checker.admin_checker_auto_update
        save_config()
    end

    if draw_toggle_row("Уведомлять о скрытых лидерах", config.checker.notify_hidden_leader_events) then
        config.checker.notify_hidden_leader_events = not config.checker.notify_hidden_leader_events
        save_config()
    end

    if draw_toggle_row("Уведомление о админах", config.checker.notify_admin_events) then
        config.checker.notify_admin_events = not config.checker.notify_admin_events
        save_config()
    end

    if draw_toggle_row("Уведомление о лидерах", config.checker.notify_leader_events) then
        config.checker.notify_leader_events = not config.checker.notify_leader_events
        save_config()
    end

    imgui.NextColumn()

    if draw_toggle_row("Уведомление о друзьях", config.checker.notify_friend_events) then
        config.checker.notify_friend_events = not config.checker.notify_friend_events
        save_config()
    end

    imgui.Text("Оповещения друзей")
    imgui.SameLine()
    local all_active = config.checker.friend_notify_mode == "all"
    if all_active then
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.73, 0.24, 0.20, 0.90))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.82, 0.29, 0.24, 0.95))
        imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.65, 0.20, 0.17, 1.00))
    end
    if imgui.Button("Все##friend_notify_all", imgui.ImVec2(44, 22)) then
        config.checker.friend_notify_mode = "all"
        save_config()
    end
    if all_active then
        imgui.PopStyleColor(3)
    end
    imgui.SameLine()
    local best_active = config.checker.friend_notify_mode == "best"
    if best_active then
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.73, 0.24, 0.20, 0.90))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.82, 0.29, 0.24, 0.95))
        imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.65, 0.20, 0.17, 1.00))
    end
    if imgui.Button("Лучшие##friend_notify_best", imgui.ImVec2(68, 22)) then
        config.checker.friend_notify_mode = "best"
        save_config()
    end
    if best_active then
        imgui.PopStyleColor(3)
    end

    if draw_toggle_row("Показывать уровень админа", config.overlay.admin_show_level) then
        config.overlay.admin_show_level = not config.overlay.admin_show_level
        save_config()
    end

    if draw_toggle_row("Показывать должность", config.overlay.admin_show_role) then
        config.overlay.admin_show_role = not config.overlay.admin_show_role
        save_config()
    end

    if draw_toggle_row("Показывать фон чекера", config.overlay.show_background) then
        config.overlay.show_background = not config.overlay.show_background
        save_config()
    end

    if draw_toggle_row("Показывать нумерацию", config.overlay.show_numbering) then
        config.overlay.show_numbering = not config.overlay.show_numbering
        save_config()
    end

    if draw_toggle_row("Показывать ID", config.overlay.show_ids) then
        config.overlay.show_ids = not config.overlay.show_ids
        save_config()
    end

    if draw_toggle_row("Перемещать чекер мышкой", overlay_move_mode.v) then
        overlay_move_mode.v = not overlay_move_mode.v
        overlay_drag_active = false
        overlay_drag_saved = false
    end

    imgui.Columns(1)
    imgui.EndChild()

    imgui.SameLine()

    imgui.BeginChild("settings_top_right", imgui.ImVec2(0, 300), true)
    imgui.Text("Шрифт")
    imgui.Separator()
    local font_items = table.concat(FONT_OPTIONS, "\0") .. "\0\0"
    if imgui.Combo("##font_selector", selected_font_index, font_items) then
        local font_index = math.max(1, math.min(#FONT_OPTIONS, selected_font_index.v + 1))
        config.overlay.font = FONT_OPTIONS[font_index]
        save_config()
        reload_font()
    end

    imgui.Text("Размер: " .. tostring(font_size_value.v))
    imgui.SameLine(120)
    if imgui.Button("Меньше", imgui.ImVec2(120, 24)) then
        font_size_value.v = math.max(6, font_size_value.v - 1)
        config.overlay.font_size = font_size_value.v
        save_config()
        reload_font()
    end
    imgui.SameLine()
    if imgui.Button("Больше", imgui.ImVec2(120, 24)) then
        font_size_value.v = math.min(20, font_size_value.v + 1)
        config.overlay.font_size = font_size_value.v
        save_config()
        reload_font()
    end

    if imgui.Button("Обновить списки", imgui.ImVec2(-1, 28)) then
        if config.checker.source_updates_enabled == false then
            message("Обновление из источников отключено.")
        else
            refresh_server_lists()
        end
    end

    imgui.Separator()
    imgui.Text("Звуковое оповещение")
    if draw_inline_toggle("Звук при подключении", "##sound_notify_enabled", config.checker.sound_notify_enabled) then
        config.checker.sound_notify_enabled = not config.checker.sound_notify_enabled
        save_config()
    end
    imgui.Text("Кого озвучивать:")
    if draw_inline_toggle("Админы", "##sound_notify_admins", config.checker.sound_notify_admins) then
        config.checker.sound_notify_admins = not config.checker.sound_notify_admins
        save_config()
    end
    imgui.SameLine(130)
    if draw_inline_toggle("Лидеры", "##sound_notify_leaders", config.checker.sound_notify_leaders) then
        config.checker.sound_notify_leaders = not config.checker.sound_notify_leaders
        save_config()
    end
    imgui.SameLine(260)
    if draw_inline_toggle("Друзья", "##sound_notify_friends", config.checker.sound_notify_friends) then
        config.checker.sound_notify_friends = not config.checker.sound_notify_friends
        save_config()
    end
    imgui.EndChild()

    imgui.BeginChild("leader_org_filters_full", imgui.ImVec2(0, 340), true)
    imgui.Text("Фракции лидеров")
    imgui.Separator()

    local leader_org_options = collect_leader_org_options()
    if #leader_org_options == 0 then
        imgui.Text("Список появится после /leaders")
    else
        if imgui.Button("Все", imgui.ImVec2(90, 24)) then
            set_all_leader_orgs_visible(true)
        end
        imgui.SameLine()
        if imgui.Button("Скрыть все", imgui.ImVec2(110, 24)) then
            set_all_leader_orgs_visible(false)
        end

        imgui.Separator()
        local column_count = 4
        imgui.Columns(column_count, "leader_org_columns_ordered", false)
        local chunk_size = math.ceil(#leader_org_options / column_count)

        for column = 1, column_count do
            local start_index = ((column - 1) * chunk_size) + 1
            local end_index = math.min(#leader_org_options, column * chunk_size)

            for index = start_index, end_index do
                local org_title = leader_org_options[index]
                if org_title and draw_inline_toggle(org_title, "##leader_org_" .. tostring(index), is_leader_org_visible(org_title)) then
                    set_leader_org_visible(org_title, not is_leader_org_visible(org_title))
                end
            end

            if column < column_count then
                imgui.NextColumn()
            end
        end

        imgui.Columns(1)
    end
    imgui.EndChild()
end


draw_help_window = function()
    if not imgui_loaded or help_window == nil or not help_window.v then
        return
    end

    imgui.SetNextWindowSize(imgui.ImVec2(560, 430), imgui.Cond.FirstUseEver)
    imgui.Begin("ADM Checker: команды", help_window)
    imgui.Text("ADV-RP.RU ADM CHECKER by Casual Alvarez")
    imgui.Separator()
    imgui.Text("/ac")
    imgui.Text("/acmenu")
    imgui.Text("/achelp")
    imgui.Spacing()
    imgui.Text("/ac reload")
    imgui.Text("/ac status")
    imgui.Spacing()
    imgui.Text("/ac set leaders on/off")
    imgui.Text("/ac set friends on/off")
    imgui.Text("/ac set admins on/off")
    imgui.Text("/ac set sources on/off")
    imgui.Text("/ac set autoupdate on/off")
    imgui.Text("/ac set x значение")
    imgui.Text("/ac set y значение")
    imgui.Text("/ac set font название")
    imgui.Text("/ac set fontsize число")
    imgui.Spacing()
    imgui.Text("/ac admin add id/ник lvl")
    imgui.Text("/ac admin remove id/ник")
    imgui.Text("/ac leader add id/ник org")
    imgui.Text("/ac leader remove id/ник")
    imgui.Text("/ac friend add id/ник")
    imgui.Text("/ac friend remove id/ник")
    imgui.Separator()
    imgui.Text("Кнопка в меню: Обновить списки = /leaders, /admins, /adms")
    imgui.End()

    if not help_window.v then
        sync_imgui_input()
    end
end

toggle_help_window = function()
    if not imgui_loaded or help_window == nil then
        message("ImGui недоступен.")
        return
    end

    help_window.v = not help_window.v
    sync_imgui_input()
end


draw_gui_page_buttons = function()
    local pages = {
        "Настройки",
        "Админы",
        "Лидеры",
        "Друзья"
    }

    local available_width = imgui.GetContentRegionAvailWidth()
    local button_width = math.floor((available_width - 18) / 4)

    for index, label in ipairs(pages) do
        if index > 1 then
            imgui.SameLine()
        end

        if imgui.Button(label, imgui.ImVec2(button_width, 30)) then
            gui_page.v = index - 1
        end
    end
end

imguiOnDrawFrame = function()
    if not imgui_loaded or config == nil then
        return
    end

    draw_help_window()

    if checker_window == nil or not checker_window.v then
        return
    end

    if checker_window_just_opened then
        local screen_x, screen_y = getScreenResolution()
        local window_width = math.max(900, screen_x - 20)
        local window_height = math.max(690, screen_y - 24)
        imgui.SetNextWindowPos(imgui.ImVec2(screen_x / 2, screen_y / 2), imgui.Cond.Always, imgui.ImVec2(0.5, 0.5))
        imgui.SetNextWindowSize(imgui.ImVec2(window_width, window_height), imgui.Cond.Always)
        checker_window_just_opened = false
    end

    imgui.SetNextWindowSize(imgui.ImVec2(1260, 800), imgui.Cond.FirstUseEver)
    imgui.Begin("Advance-RP AdminChecker", checker_window)
    imgui.Text(APP_TITLE)
    imgui.SameLine()
    imgui.TextDisabled("/acmenu")
    draw_gui_page_buttons()
    imgui.Separator()

    if gui_page.v == 0 then
        draw_settings_editor()
    elseif gui_page.v == 1 then
        draw_admin_editor()
    elseif gui_page.v == 2 then
        draw_leader_editor()
    else
        draw_friend_editor()
    end
    imgui.End()

    if not checker_window.v then
        checker_window_just_opened = false
        overlay_move_mode.v = false
        overlay_drag_active = false
        overlay_drag_saved = false
        sync_imgui_input()
    end
end

checker_help = function()
    message("Использование: /ac [admin/leader/friend] [add/remove] [id/ник] [lvl/org]")
    message("Служебное: /ac reload, /ac status, /ac update")
    message("Настройки: /ac set [leaders/friends/admins/sources/autoupdate] [on/off]")
    message("Оверлей: /ac set [x/y/font/fontsize] [значение]")
    message("GUI: /acmenu")
end

checker_status = function()
    message(string.format(
        "Лидеры=%s, друзья=%s, админы=%s, источники=%s, автообновление=%s",
        tostring(config.checker.leaders_checker_status),
        tostring(config.checker.friends_checker_status),
        tostring(config.checker.admins_checker_status),
        tostring(config.checker.source_updates_enabled),
        tostring(config.checker.admin_checker_auto_update)
    ))

    message(string.format(
        "Оверлей: x=%s y=%s, шрифт=%s, размер=%s",
        tostring(config.overlay.xpos),
        tostring(config.overlay.ypos),
        tostring(config.overlay.font),
        tostring(config.overlay.font_size)
    ))
end

refresh_s_admins_from_dialog = function(text)
    if text == nil or text == "" then
        return false
    end

    local parsed_text = cp1251_to_utf8(text)
    local parsed = 0

    for line in string.gmatch(parsed_text, "[^\r\n]+") do
        local nickname, level = string.match(line, "^([^\t]+)\t([^\t]+)")
        if nickname ~= nil and level ~= nil then
            nickname = trim(nickname)
            level = normalize_admin_level(trim(level))

            if nickname ~= "" and nickname ~= "Ник" and is_youtube_level(level) then
                upsert_admin(nickname, level, nil)
                parsed = parsed + 1
            end
        end
    end

    if parsed == 0 then
        return false
    end

    sync_online_ids()
    message(string.format("Список S-администраторов обновлён из диалога /adms. Записей: %d.", parsed))
    return true
end

parse_admin_line = function(text)
    if text == nil or text == "" then
        return nil, nil, nil
    end

    local parsed_text = cp1251_to_utf8(text)
    local nickname, tracked_id, level = string.match(parsed_text, "([%w_]+)%[(%d+)%]%s*%((S?%d+)%s+lvl%)")
    if nickname == nil then
        nickname, tracked_id, level = string.match(parsed_text, "([%w_]+)%[(%d+)%]%s*%((S%d)%s+lvl%)")
    end

    tracked_id = tonumber(tracked_id)
    level = normalize_admin_level(level)

    if nickname == nil or tracked_id == nil or level == "-1" then
        return nil, nil, nil
    end

    return nickname, tracked_id, level
end

update_admin_from_line = function(text, local_name)
    local nickname, tracked_id, level = parse_admin_line(text)
    if nickname == nil or same_name(local_name, nickname) then
        return false
    end

    local index = find_index_by_name(admins_nick, nickname)
    if index ~= nil and admins_locked[index] == true then
        return false
    end

    if index == nil then
        upsert_admin(nickname, level, tracked_id)
        message(string.format("В чекер добавлен администратор %s [%d], уровень %s.", nickname, tracked_id, level))
        return true
    end

    local old_level = normalize_admin_level(admins_lvl[index])
    local old_id = tonumber(admins_id[index]) or -1
    admins_id[index] = tracked_id

    if old_level ~= level then
        admins_lvl[index] = level
        save_admins()
        message(string.format("Обновлён уровень администратора %s: %s -> %s.", nickname, old_level, level))
        return true
    end

    if old_id ~= tracked_id then
        save_admins()
        message(string.format("Обновлён ID администратора %s: [%d].", nickname, tracked_id))
        return true
    end

    return false
end

refresh_leaders_from_dialog = function(text)
    if text == nil or text == "" then
        return false
    end

    local parsed_text = cp1251_to_utf8(text)
    local new_nick = {}
    local new_org = {}
    local new_org_name = {}
    local parsed = 0

    for line in string.gmatch(parsed_text, "[^\r\n]+") do
        local nickname, organization = string.match(line, "^([^\t]+)\t([^\t]+)")
        if nickname ~= nil and organization ~= nil then
            nickname = trim(nickname)
            organization = trim(organization)

            if nickname ~= "" and nickname ~= "Имя" then
                parsed = parsed + 1
                table.insert(new_nick, nickname)
                table.insert(new_org, leader_org_id_from_name(organization))
                table.insert(new_org_name, organization)
            end
        end
    end

    if parsed == 0 then
        return false
    end

    leaders_nick = new_nick
    leaders_org = new_org
    leaders_org_name = new_org_name
    leaders_id = {}

    for _ = 1, #leaders_nick do
        table.insert(leaders_id, -1)
    end

    save_leaders()
    sync_online_ids()
    message(string.format("Список лидеров обновлён из диалога /leaders. Записей: %d.", parsed))
    return true
end

function sampOnPlayerJoin(player_id, _, _, nickname)
    nickname = cp1251_to_utf8(nickname)

    for index, tracked_name in ipairs(admins_nick) do
        if same_name(tracked_name, nickname) then
            admins_id[index] = player_id

            if sampIsLocalPlayerSpawned() then
                local level = normalize_admin_level(admins_lvl[index])
                local role_title = get_admin_role_title(index, level)
                local display_name = format_display_nickname(nickname)

                if is_youtube_level(level) and role_title == "YouTube" then
                    message(string.format("%s %s %s подключился к серверу.", role_title, level, display_name))
                else
                    message(string.format("%s %s подключился к серверу.", role_title, display_name))
                end
            end

            break
        end
    end

    for index, tracked_name in ipairs(leaders_nick) do
        if same_name(tracked_name, nickname) then
            leaders_id[index] = player_id

            if sampIsLocalPlayerSpawned() then
                local org_title = normalize_leader_org_title(leaders_org_name[index], leaders_org[index])
                if should_notify_leader_org(org_title) then
                    message(string.format("Лидер %s %s подключился к серверу.", org_title, format_display_nickname(nickname)))
                end
            end

            break
        end
    end

    for index, tracked_name in ipairs(friends_nick) do
        if same_name(tracked_name, nickname) then
            friends_id[index] = player_id

            if sampIsLocalPlayerSpawned() and should_notify_friend(index) then
                local display_name = format_display_nickname(nickname)
                if is_best_friend(index) then
                    message(string.format("Лучший друг %s подключился к серверу.", display_name))
                else
                    message(string.format("Друг %s подключился к серверу.", display_name))
                end
            end

            break
        end
    end
end

function sampOnPlayerQuit(player_id, _)
    for index, tracked_id in ipairs(admins_id) do
        if tracked_id == player_id then
            admins_id[index] = -1
            local level = normalize_admin_level(admins_lvl[index])
            local role_title = get_admin_role_title(index, level)
            local display_name = format_display_nickname(admins_nick[index])

            if is_youtube_level(level) and role_title == "YouTube" then
                message(string.format("%s %s %s[%d] отключился.", role_title, level, display_name, player_id))
            else
                message(string.format("%s %s[%d] отключился.", role_title, display_name, player_id))
            end
            break
        end
    end

    for index, tracked_id in ipairs(leaders_id) do
        if tracked_id == player_id then
            leaders_id[index] = -1
            local org_title = normalize_leader_org_title(leaders_org_name[index], leaders_org[index])
            if should_notify_leader_org(org_title) then
                message(string.format("Лидер %s %s покинул сервер.", org_title, format_display_nickname(leaders_nick[index])))
            end
            break
        end
    end

    for index, tracked_id in ipairs(friends_id) do
        if tracked_id == player_id then
            friends_id[index] = -1
            if should_notify_friend(index) then
                local display_name = format_display_nickname(friends_nick[index])
                if is_best_friend(index) then
                    message(string.format("Лучший друг %s покинул сервер.", display_name))
                else
                    message(string.format("Друг %s покинул сервер.", display_name))
                end
            end
            break
        end
    end
end

refresh_s_admins_from_dialog = function(text)
    if text == nil or text == "" then
        return false
    end

    local parsed_text = cp1251_to_utf8(text)
    local parsed = 0
    local added = {}
    local seen = {}
    local removed = {}

    for line in string.gmatch(parsed_text, "[^\r\n]+") do
        local nickname, level = string.match(line, "^([^\t]+)\t([^\t]+)")
        if nickname ~= nil and level ~= nil then
            nickname = trim(nickname)
            level = normalize_admin_level(trim(level))

            if nickname ~= "" and nickname ~= "Ник" and is_youtube_level(level) then
                local key = string.lower(nickname)
                local existing_index = find_index_by_name(admins_nick, nickname)
                local was_known = existing_index ~= nil
                seen[key] = true
                if existing_index == nil or admins_locked[existing_index] ~= true then
                    upsert_admin(nickname, level, nil)
                end
                parsed = parsed + 1

                if not was_known then
                    table.insert(added, {
                        nickname = nickname,
                        level = level
                    })
                end
            end
        end
    end

    if parsed == 0 then
        return false
    end

    for index = #admins_nick, 1, -1 do
        local level = normalize_admin_level(admins_lvl[index])
        local nickname = admins_nick[index]
        local key = string.lower(nickname or "")

        if is_youtube_level(level) and admins_locked[index] ~= true and not seen[key] then
            table.insert(removed, {
                nickname = nickname,
                level = level
            })
            table.remove(admins_nick, index)
            table.remove(admins_lvl, index)
            table.remove(admins_id, index)
            table.remove(admins_role, index)
            table.remove(admins_notify, index)
            table.remove(admins_locked, index)
            table.remove(admins_sound_notify, index)
        end
    end

    if #removed > 0 then
        save_admins()
    end

    sync_online_ids()

    for _, item in ipairs(added) do
        message(string.format("В чекер добавлен S-администратор %s, уровень %s.", format_display_nickname(item.nickname), tostring(item.level)))
    end

    for _, item in ipairs(removed) do
        message(string.format("S-администратор %s удалён из чекера: его нет в /adms.", format_display_nickname(item.nickname)))
    end

    message(string.format("Список S-администраторов обновлён из диалога /adms. Записей: %d, новых: %d, удалено: %d.", parsed, #added, #removed))
    return true
end

refresh_leaders_from_dialog = function(text)
    if text == nil or text == "" then
        return false
    end

    local parsed_text = cp1251_to_utf8(text)
    local old_notify = {}
    local old_sound_notify = {}
    local old_known = {}
    for index, nickname in ipairs(leaders_nick) do
        local key = string.lower(nickname)
        old_notify[key] = leaders_notify[index] ~= false
        old_sound_notify[key] = leaders_sound_notify[index] == true
        old_known[key] = {
            nickname = nickname,
            organization = normalize_leader_org_title(leaders_org_name[index], leaders_org[index])
        }
    end

    local new_nick = {}
    local new_org = {}
    local new_org_name = {}
    local new_notify = {}
    local new_sound_notify = {}
    local new_seen = {}
    local added = {}
    local removed = {}
    local parsed = 0

    for line in string.gmatch(parsed_text, "[^\r\n]+") do
        local nickname, organization = string.match(line, "^([^\t]+)\t([^\t]+)")
        if nickname ~= nil and organization ~= nil then
            nickname = trim(nickname)
            organization = trim(organization)

            if is_valid_leader_row(nickname, organization) then
                local key = string.lower(nickname)
                parsed = parsed + 1
                new_seen[key] = true
                table.insert(new_nick, nickname)
                table.insert(new_org, leader_org_id_from_name(organization))
                table.insert(new_org_name, organization)
                table.insert(new_notify, old_known[key] ~= nil and old_notify[key] == true or true)
                table.insert(new_sound_notify, old_known[key] ~= nil and old_sound_notify[key] == true or false)

                if old_known[key] == nil then
                    table.insert(added, {
                        nickname = nickname,
                        organization = organization
                    })
                end
            end
        end
    end

    if parsed == 0 then
        return false
    end

    for key, item in pairs(old_known) do
        if not new_seen[key] then
            table.insert(removed, item)
        end
    end

    leaders_nick = new_nick
    leaders_org = new_org
    leaders_org_name = new_org_name
    leaders_notify = new_notify
    leaders_sound_notify = new_sound_notify
    leaders_id = {}

    for _ = 1, #leaders_nick do
        table.insert(leaders_id, -1)
    end

    save_leaders()
    sync_online_ids()

    for _, item in ipairs(added) do
        message(string.format("В чекер добавлен лидер %s, фракция: %s.", format_display_nickname(item.nickname), item.organization))
    end

    for _, item in ipairs(removed) do
        message(string.format("Лидер %s удалён из чекера: его нет в /leaders.", format_display_nickname(item.nickname)))
    end

    message(string.format("Список лидеров обновлён из диалога /leaders. Записей: %d, новых: %d, удалено: %d.", parsed, #added, #removed))
    return true
end

function sampOnPlayerJoin(player_id, _, _, nickname)
    nickname = cp1251_to_utf8(nickname)

    for index, tracked_name in ipairs(admins_nick) do
        if same_name(tracked_name, nickname) then
            admins_id[index] = player_id

            if sampIsLocalPlayerSpawned() then
                local level = normalize_admin_level(admins_lvl[index])
                local role_title = get_admin_role_title(index, level)
                local display_name = format_display_nickname(nickname)

                if should_notify_admin(index) then
                    if is_youtube_level(level) and role_title == "YouTube" then
                        message(string.format("%s %s %s подключился к серверу.", role_title, level, display_name))
                    else
                        message(string.format("%s %s подключился к серверу.", role_title, display_name))
                    end
                end

                if should_sound_notify_admin(index) then
                    play_join_notification_sound("admin")
                end
            end

            break
        end
    end

    for index, tracked_name in ipairs(leaders_nick) do
        if same_name(tracked_name, nickname) then
            leaders_id[index] = player_id

            if sampIsLocalPlayerSpawned() then
                local org_title = normalize_leader_org_title(leaders_org_name[index], leaders_org[index])
                if should_notify_leader(index) then
                    message(string.format("Лидер %s %s подключился к серверу.", org_title, format_display_nickname(nickname)))
                end
                if should_sound_notify_leader(index) then
                    play_join_notification_sound("leader")
                end
            end

            break
        end
    end

    for index, tracked_name in ipairs(friends_nick) do
        if same_name(tracked_name, nickname) then
            friends_id[index] = player_id

            if sampIsLocalPlayerSpawned() then
                local display_name = format_display_nickname(nickname)
                if should_notify_friend(index) then
                    if is_best_friend(index) then
                        message(string.format("Лучший друг %s подключился к серверу.", display_name))
                    else
                        message(string.format("Друг %s подключился к серверу.", display_name))
                    end
                end
                if should_sound_notify_friend(index) then
                    play_join_notification_sound("friend")
                end
            end

            break
        end
    end
end

function sampOnPlayerQuit(player_id, _)
    for index, tracked_id in ipairs(admins_id) do
        if tracked_id == player_id then
            admins_id[index] = -1
            if should_notify_admin(index) then
                local level = normalize_admin_level(admins_lvl[index])
                local role_title = get_admin_role_title(index, level)
                local display_name = format_display_nickname(admins_nick[index])

                if is_youtube_level(level) and role_title == "YouTube" then
                    message(string.format("%s %s %s[%d] отключился.", role_title, level, display_name, player_id))
                else
                    message(string.format("%s %s[%d] отключился.", role_title, display_name, player_id))
                end
            end
            break
        end
    end

    for index, tracked_id in ipairs(leaders_id) do
        if tracked_id == player_id then
            leaders_id[index] = -1
            if should_notify_leader(index) then
                local org_title = normalize_leader_org_title(leaders_org_name[index], leaders_org[index])
                message(string.format("Лидер %s %s покинул сервер.", org_title, format_display_nickname(leaders_nick[index])))
            end
            break
        end
    end

    for index, tracked_id in ipairs(friends_id) do
        if tracked_id == player_id then
            friends_id[index] = -1
            if should_notify_friend(index) then
                local display_name = format_display_nickname(friends_nick[index])
                if is_best_friend(index) then
                    message(string.format("Лучший друг %s покинул сервер.", display_name))
                else
                    message(string.format("Друг %s покинул сервер.", display_name))
                end
            end
            break
        end
    end
end

function sampOnServerMessage(color, text)
    if config == nil or not config.checker.admin_checker_auto_update then
        return
    end

    local parsed_text = cp1251_to_utf8(text)
    if string.find(parsed_text, "Админы онлайн", 1, true) then
        start_admin_refresh()
        return
    end

    local local_name = nil
    local ok, player_id = sampGetPlayerIdByCharHandle(PLAYER_PED)
    if ok then
        local_name = cp1251_to_utf8(sampGetPlayerNickname(player_id))
    end

    update_admin_from_line(text, local_name)

    if admin_refresh_active then
        local nickname = parse_admin_line(text)
        if nickname ~= nil then
            admin_refresh_seen_nicks[string.lower(nickname)] = true
            admin_refresh_last_line_at = os.clock()
        end
    end
end

function sampOnShowDialog(dialog_id, style, title, button1, button2, text)
    local raw_title = tostring(title or '')
    local parsed_title = cp1251_to_utf8(raw_title)
    local is_leaders_dialog = string.find(parsed_title, 'Лидеры', 1, true) or string.find(raw_title, 'Лидеры', 1, true)
    local handled_refresh_dialog = false

    if style == 5 and dialog_id == 424 and is_leaders_dialog then
        refresh_leaders_from_dialog(text)
        handled_refresh_dialog = true
    elseif style == 5 and dialog_id == 0 and string.find(parsed_title, "Администраторы S уровня", 1, true) then
        refresh_s_admins_from_dialog(text)
        handled_refresh_dialog = true
    end

    if auto_close_refresh_dialogs and handled_refresh_dialog then
        lua_thread.create(function()
            wait(80)
            close_current_dialog_safely()
        end)
    end
end

function main()
    while not isSampAvailable() do
        wait(200)
    end

    while sampGetGamestate() ~= 3 do
        wait(500)
    end

    if not is_target_server() then
        unload_on_wrong_server()
        return
    end

    if doesFileExist("moonloader\\lib\\MoonImGui.dll") and doesFileExist("moonloader\\lib\\imgui.lua") then
        imgui = require("imgui")
        imgui.OnDrawFrame = imguiOnDrawFrame
        imgui.Process = false
        imgui.ShowCursor = false
        imgui_loaded = true
        init_imgui_state()
    end

    ensure_environment()
    load_config()
    load_all_lists()
    reload_font()
    refresh_gui_buffers()

    sampRegisterChatCommand("ac", checker_command)
    sampRegisterChatCommand("acmenu", toggle_checker_window)
    sampRegisterChatCommand("achelp", toggle_help_window)
    sampRegisterChatCommand("acupdate", checker_update_command)
    sync_online_ids()
    message(STARTUP_SEPARATOR)
    message("ADV-RP.RU ADM CHECKER by Casual Alvarez v" .. APP_VERSION)
    if imgui_loaded then
        message("Команды: /ac | /acmenu | /achelp | /acupdate")
    else
        message("ImGui не найден. GUI, /acmenu и /achelp отключены. Обновление: /acupdate")
    end
    message(STARTUP_SEPARATOR)
    lua_thread.create(function()
        wait(1500)
        check_script_update(true, false)
    end)

    while true do
        wait(0)

        if sampGetGamestate() ~= 3 then
            clear_online_ids()
        else
            if not is_target_server() then
                unload_on_wrong_server()
                return
            end

            if os.clock() - last_sync > 5 then
                sync_online_ids()
                last_sync = os.clock()
            end

            if admin_refresh_active and os.clock() - admin_refresh_last_line_at > 1.2 then
                finalize_admin_refresh()
            end

            if not isPauseMenuActive() then
                draw_overlay()
            end

            handle_overlay_drag()
        end
    end
end
