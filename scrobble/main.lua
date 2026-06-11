-- An over-engineered last.fm scrobbler for mpv player
-- last.fm scrobbler for mpv
-- derived from https://github.com/l29ah/w3crapcli/blob/master/last.fm/mpv-lastfm.lua
--
-- Usage:
-- put this file in ~/.config/mpv/scripts/scroble/
-- put lastfm.conf in ~/.config/mpv/script-opts/
-- put https://github.com/hauzer/scrobbler somewhere in your PATH
-- run `scrobbler add-user` and follow the instructions
-- create a shortcut for overrides in input.conf if you want to use this feature (e.g., O script-binding scrobble/create-override)

-- TODO(squero): LOVE TRACK /w uosc support!!
-- TODO(squero): skip scrobbling current track with a key press (what about now-playing?)
-- TODO(squero): Support video formats for music videos (partially)

local mp = require 'mp'
local utils = require 'mp.utils'
require 'mp.options'
dkjson = require("lib/dkjson")

local options = {
    username = "change username in script-opts/lastfm.conf",
    scrobble_paths = "change scrobble_paths in script-opts/lastfm.conf",
    scrobble_threshold = "change scrobble_threshold in script-opts/lastfm.conf",
    artist_blacklist = "change artist_blacklist in script-opts/lastfm.conf",
    track_blacklist = "change track_blacklist in script-opts/lastfm.conf",
    fuzzy_metadata_search = "change fuzzy_metadata_search in script-opts/lastfm.conf",
    enforce_overrides = false,
    only_album_artist = "change only_album_artist in script-opts/lastfm.conf",
    scrobbler_path = "scrobbler"
}

read_options(options, 'lastfm')

local function expand_path(path)
    if path == nil or path == "" then return "scrobbler" end
    return mp.command_native({"expand-path", path})
end

local scrobbler_binary = expand_path(options.scrobbler_path)

function trim(s)
    return s:match("^%s*(.-)%s*$")
end

function contains(text, substring)
    return string.find(text, substring) ~= nil
end

function starts_with(str, prefix)
    return string.sub(str, 1, string.len(prefix)) == prefix
end

function parseCSV(input)
    local result = {}
    for element in string.gmatch(input, '([^,]+)') do
        table.insert(result, trim(element))
    end
    return result
end

function escape_pattern(str)
    return str:gsub("([%.%+%-%*%?%[%]%(%)%$%^%{%}])", "%%%1")
end

function remove_substring(input, toRemove)
    -- Use gsub to replace the substring with an empty string
    return input:gsub(escape_pattern(toRemove), "")
end

function normalize_path(input)
    return mp.command_native({"normalize-path", input})
end

function get_file_extension(filename)
    return filename and filename:match("%.([^%.]+)$") or "No file path available"
end

function is_absolute_path(path)
    -- Check for Windows absolute path (e.g., C:\path\to\file)
    if path:gsub("/", "\\"):match("^[a-zA-Z]:\\") then
        return true
    end

    -- Check for Unix-like absolute path (e.g., /path/to/file)
    if path:sub(1, 1) == "/" then
        return true
    end

    return false
end

function get_absolute_path(path, filename, working_dir)
    local absolute_path = nil

    if is_absolute_path(path) then
        absolute_path = path
    else
        absolute_path = (working_dir or ".") .. "/" .. path
    end

    return remove_substring(absolute_path, filename)
end

function createFile(path, filename, content)
    local filePath = path .. '/' .. filename
    
    -- Check if the file already exists
    local file = io.open(filePath, "r")
    if file then
        file:close()
        return false, "Error: File already exists."
    end

    -- Create and write to the file
    file = io.open(filePath, "w")
    if file then
        file:write(content)
        file:close()
        return true
    else
        return false, "Error: Unable to create file."  -- Return false if there was an error
    end
end

function get_meta_table(property)
    local count = mp.get_property_number(property .. "/list/count")
    if count and count > 0 then
        local m = {}
        for i = 0, count - 1 do
            local p = property .. "/list/"..i.."/"
            local key = mp.get_property(p.."key")
            local value = mp.get_property(p.."value")
            if key then m[key:lower()] = value end
        end
        return m
    end
    return nil
end

function log_to_file(msg)
    local log_path = mp.command_native({"expand-path", "~~/lastfm.log"})
    local f = io.open(log_path, "a")
    if f then
        f:write(os.date("%Y-%m-%d %H:%M:%S") .. " " .. msg .. "\n")
        f:close()
    end
    mp.msg.info(msg)
end

function subprocess_async(args, callback)
    local cmd = {
        name = "subprocess",
        args = args,
        playback_only = false,
        capture_stdout = true,
        capture_stderr = true
    }
    mp.command_native_async(cmd, function(success, res, error)
        if not success or res == nil then
            local err_msg = "Error executing subprocess: " .. tostring(error)
            log_to_file(err_msg)
            if callback then callback(nil, nil, -1, err_msg) end
            return
        end
        if res.status ~= 0 then
            local err_msg = "Subprocess failed with status " .. tostring(res.status)
            if res.stderr and #res.stderr > 0 then
                err_msg = err_msg .. " | stderr: " .. res.stderr
            end
            log_to_file(err_msg)
        end
        if callback then callback(res.stdout, res.stderr, res.status, nil) end
    end)
end

local artist, album, title, length, song_play_time, last_playing_track, tim

local function get_scrobble_args(command, artist, title, album, length, song_play_time)
    local args = { scrobbler_binary, command }
    if album and #album > 0 then
        table.insert(args, "--album=" .. album)
    end
    if length then
        local len_num = tonumber(length)
        if len_num then
            table.insert(args, "--duration=" .. math.floor(len_num) .. "s")
        end
    end
    table.insert(args, "--")
    table.insert(args, options.username)
    table.insert(args, artist)
    table.insert(args, title)
    if song_play_time then
        table.insert(args, song_play_time)
    end
    return args
end

-- Function to scrobble the current track
local function scrobble()
    local log_msg = string.format("Scrobbling current track: %s - %s [%s]", tostring(artist), tostring(title), tostring(album))
    log_to_file(log_msg)
    mp.osd_message(log_msg)

    if options.username:find("change username") then
        log_to_file("Username not configured in script-opts/lastfm.conf!")
        return
    end

    local args = get_scrobble_args("scrobble", artist, title, album, length, song_play_time)
    subprocess_async(args, function(stdout, stderr, status, err_msg)
        if status == 0 then
            log_to_file("Scrobble successful: " .. (stdout or ""))
        else
            log_to_file("Scrobble failed. Status: " .. tostring(status))
        end
    end)
end

function scrobble_blacklist_check(metadata, blacklist)
    local skip_scrobble = false

    for _, element in ipairs(blacklist) do
        if element == nil or #element == 0 then
            goto continue
        end
        if metadata ~= element then
            goto continue
        else
            mp.msg.warn(string.format("%s is in blacklist, skipping scrobbling.", element))
            skip_scrobble = true
            break
        end
        ::continue::
    end

    return skip_scrobble
end

function enqueue() -- Implement blacklisting here
    if artist and title then
        if #options.artist_blacklist > 0 then
            if scrobble_blacklist_check(artist, parseCSV(options.artist_blacklist)) then return end
        elseif #options.track_blacklist > 0 then
            if scrobble_blacklist_check(title, parseCSV(options.track_blacklist)) then return end
        end
        if tim then 
            tim:kill() 
        end
        
        local threshold = tonumber(options.scrobble_threshold) or 50
        local len_num = tonumber(length)
        local timeout
        if len_num and len_num > 0 then
            timeout = math.min(240, len_num / (100 / threshold))
        else
            timeout = 240
        end
        
        mp.msg.info(string.format("Now playing: %s - %s [%s]", tostring(artist), tostring(title), tostring(album)))
        mp.osd_message(string.format("Now playing: %s - %s [%s]", tostring(artist), tostring(title), tostring(album)))
        
        if not options.username:find("change username") then
            local args = get_scrobble_args("now-playing", artist, title, album, length)
            subprocess_async(args, function(stdout, stderr, status, err_msg)
                if status == 0 then
                    log_to_file("Initial now-playing sent successfully")
                else
                    log_to_file("Initial now-playing failed. Status: " .. tostring(status))
                end
            end)
        end

        last_playing_track = artist .. title
        tim = mp.add_timeout(timeout, scrobble)
    else
        mp.msg.error("Metadata missing (artist or title), cannot enqueue scrobble.")
    end
end

function on_pause_change(name, value)
    if value == true and tim then
        tim:stop() -- stop the timer when paused
    end

    if value == false and tim then
        tim:resume() -- resume the timer when played
        
        if artist and title and not options.username:find("change username") then
            local args = get_scrobble_args("now-playing", artist, title, album, length)
            subprocess_async(args, function(stdout, stderr, status, err_msg)
                if status == 0 then
                    log_to_file("Resume now-playing sent successfully")
                else
                    log_to_file("Resume now-playing failed. Status: " .. tostring(status))
                end
            end)
        end
    end
end

function parse_artist_work(input)
    -- Use string.match to capture the artist and album
    local artist, album = input:match("^(.-)%s*-%s*(.+)$")
    
    -- Check if both artist and album were found
    if artist and album then
        return artist, album
    else
        return nil, nil -- Return nil if the format is incorrect
    end
end

function scrobble_whitelist_check(track_path, scrobble_paths)
    local should_scrobble = false

    for _, ipath in ipairs(scrobble_paths) do
        if ipath == nil or #ipath == 0 then
            goto continue
        end
        if is_absolute_path(ipath) then
            if not starts_with(track_path, ipath) then
                goto continue
            else
                should_scrobble = true
                break
            end
        else
            if not contains(track_path, ipath) then
                goto continue
            else
                should_scrobble = true
                break
            end
        end
        ::continue::
    end
    return should_scrobble
end

function table_includes(table, value)
    for _, v in ipairs(table) do
        if v == value then  -- Check if the current value matches the target value
            return true
        end
    end
    return false
end

function read_file(filePath)
    local file, err = io.open(filePath, "r")  -- Open the file in read mode
    if not file then
        return nil, "Error opening file: " .. err  -- Return nil and error message if file cannot be opened
    end

    local content = file:read("*all")  -- Read the entire content of the file
    file:close()  -- Close the file
    return content  -- Return the content of the file
end

function modify_metadata(override_json)
    if not override_json then return end
    if override_json["artist"] and #override_json["artist"] > 0 then
        artist = override_json["artist"]
    end

    if override_json["album"] and #override_json["album"] > 0 then
        album = override_json["album"]
    end

    if override_json["title"] and #override_json["title"] > 0 then
        title = override_json["title"]
    end
end

function new_track(name)
    -- PRE-FETCH ALL PROPERTIES AT ONCE TO AVOID DEADLOCKS
    local path = mp.get_property("path")
    local filename = mp.get_property("filename")
    local filename_no_ext = mp.get_property("filename/no-ext")
    local working_dir = mp.get_property("working-directory")
    local duration = mp.get_property_number("duration")
    local chapter_count = mp.get_property_number("chapter-list/count")
    local chapter_index = mp.get_property_number("chapter")
    local filtered_metadata = get_meta_table("filtered-metadata")
    local metadata = get_meta_table("metadata")
    local chapter_metadata = get_meta_table("chapter-metadata")

    -- Kill any existing timer and reset state for the new track
    if tim then 
        tim:kill() 
    end
    artist, album, title, length, song_play_time = nil, nil, nil, nil, nil

    if filename == nil then
        return
    end

    -- Pre-calculate track_dir and track_path using pre-fetched properties
    local track_path = get_absolute_path(path, filename, working_dir)

    if skip_path_check ~= filename then
        if #options.scrobble_paths > 0 then
            local scrobble_paths = parseCSV(options.scrobble_paths)
    
            -- Check if media path is in whitelist
            if not scrobble_whitelist_check(track_path, scrobble_paths) then
                mp.msg.warn("Path is not in allow list, skipping scrobbling.")
                return
            end

            skip_path_check = filename
        end
    end

    -- Mark the scrobble time of the track
    song_play_time = os.date("%Y-%m-%d.%H:%M")

    file_extension = get_file_extension(filename)

    -- options.enforce_overrides
    local override_file = (filename_no_ext or "unknown") .. ".override"
    local track_dir = track_path -- Since get_absolute_path returns dir path
    
    local files_in_directory = utils.readdir(track_dir, "files")
    if files_in_directory and table_includes(files_in_directory, override_file) then
        local file_content = read_file(track_dir .. "/" .. override_file)
        if file_content then
            override_json = utils.parse_json(file_content)
            if override_json then modify_metadata(override_json) end
        end
    end

    -- fuzzy_metadata_search
    fuzzy_metadata_search = options.fuzzy_metadata_search
    if #fuzzy_metadata_search > 0 and fuzzy_metadata_search ~= "no" then
        if fuzzy_metadata_search == "yes" then
            artist, album = parse_artist_work(filename_no_ext)
        elseif fuzzy_metadata_search == "cue" then
            if file_extension == "cue" then
                artist, album = parse_artist_work(filename_no_ext)
            end
        end
    end

    if file_extension == "cue" or file_extension == "mkv" then
        if chapter_index == nil or chapter_index == -1 then
            return
        end

        if override_json and override_json["chapters"] then
            modify_metadata(override_json["chapters"][tostring(chapter_index)])
        end

        if chapter_count and chapter_index+1 < chapter_count then
            -- Note: chapter-list/N/time still needs a call, but it's less likely to deadlock than base properties
            local next_chapter_starts = mp.get_property_number(string.format("chapter-list/%d/time", chapter_index+1))
            local this_chapter_starts = mp.get_property_number(string.format("chapter-list/%d/time", chapter_index))
            if next_chapter_starts and this_chapter_starts then
                length = next_chapter_starts - this_chapter_starts
            end
        elseif duration then
            local this_chapter_starts = mp.get_property_number(string.format("chapter-list/%d/time", chapter_index))
            if this_chapter_starts then
                length = duration - this_chapter_starts
            end
        end

        if chapter_metadata then
            title = chapter_metadata["title"] or title
            artist = chapter_metadata["performer"] or artist
        end

        if not artist and filtered_metadata == nil then
            mp.msg.error("No metadata was found.")
            return
        end

        if filtered_metadata ~= nil then
            if not artist then
                artist = filtered_metadata["artist"]
            end
            if not album then
                album = filtered_metadata["album"]
            end
        end

        if override_json then
            if (override_json["enforce_overrides"] == "yes") or (override_json["enforce_overrides"] == "default" and options.enforce_overrides) then
                modify_metadata(override_json)
                if override_json["chapters"] then
                    modify_metadata(override_json["chapters"][tostring(chapter_index)])
                end
            end
        end
    else
        length = duration
    
        if metadata == nil and not override_json then
            return
        end
    
        local icy = metadata["icy-title"]
        if icy then
            artist, title = parse_artist_work(icy)
            album = nil
        else
            if length and tonumber(length) < 30 then return end -- last.fm doesn't allow scrobbling short tracks
            artist = filtered_metadata and filtered_metadata["artist"] or artist
            album_artist = filtered_metadata and (filtered_metadata["album_artist"] or filtered_metadata["album artist"])

            if album_artist then
                if #options.only_album_artist > 0 then
                    if options.only_album_artist == "yes" or options.only_album_artist == "must" then
                        artist = album_artist
                    end
                end
            else
                if options.only_album_artist == "must" then
                    mp.msg.warn("The Album_Artist metadata was not found, Mustn't scrobble.")
                    return
                end
            end

            album = filtered_metadata and filtered_metadata["album"] or album
            title = filtered_metadata and filtered_metadata["title"] or title
        end
        if override_json then
            if (override_json["enforce_overrides"] == "yes") or (override_json["enforce_overrides"] == "default" and options.enforce_overrides) then
                modify_metadata(override_json)
            end
        end
    end
    enqueue()
end

function on_restart()
    audio_pts = mp.get_property_number("audio-pts")
    -- FIXME a better check for -loop'ing tracks
    if ((not audio_pts) or (audio_pts < 1)) then
        new_track()
    end
end

function prettify_json(input_table)
    -- Convert the table to a JSON string with pretty formatting
    local json_string, pos, err = dkjson.encode(input_table, { indent = true })
    
    -- Check for errors during encoding
    if err then
        return nil, "Error encoding JSON: " .. err
    end
    
    return json_string
end

function create_override()
    local path = mp.get_property("path")
    local filename = mp.get_property("filename")
    local filename_no_ext = mp.get_property("filename/no-ext")
    local working_dir = mp.get_property("working-directory")

    if filename == nil then
        mp.msg.error("No file has been loaded. Please try again in a moment")
        return
    end

    local file_extension = get_file_extension(filename)
    local absolute_path = get_absolute_path(path, filename, working_dir)

    -- Create the JSON-like table
    local override = {
        enforce_overrides = "default",
        artist = "",
        album = "",
        title = ""
    }

    -- Only include chapters if the file extension is "cue"
    if file_extension == "cue" then
        local chapter_count = mp.get_property_number("chapter-list/count")
        override.chapters = {}
        
        -- Populate the chapters based on the chapter count
        if chapter_count then
            for i = 0, chapter_count - 1 do
                override.chapters[tostring(i)] = {
                    artist = "",
                    album = "",
                    title = ""
                }
            end
        end
    end

    local override_json = prettify_json(override)
    createFile(absolute_path, override_file, override_json)
end

-- mp.observe_property("metadata/list/count", nil, new_track)
mp.register_event("file-loaded", new_track)
mp.observe_property("chapter", nil, new_track)
mp.register_event("playback-restart", on_restart)
mp.observe_property("pause", "bool", on_pause_change)
mp.add_key_binding(nil, 'create-override', create_override)
