-- CONFIG
local DEBUG_MODE = false
-- CONFIG

local timer = require("timer")
local http = require('coro-http')
local json = require('json')
local sp = require("serpent")
local querystring = require("querystring")

local color = {
    foreground = {
        black = "[30m",
        dark_red = "[31m",
        dark_green = "[32m",
        dark_yellow = "[33m",
        dark_blue = "[34m",
        dark_magenta = "[35m",
        dark_cyan = "[36m",
        gray = "[37m",
        light_gray = "[90m",
        red = "[91m",
        green = "[92m",
        yellow = "[93m",
        blue = "[94m",
        magenta = "[95m",
        cyan = "[96m",
        white = "[97m",
    },
}

local log_lvl = {
    debug = {
        name="DEBUG",
        color="[95m",
        color_dark="[35m",
        text_color = "[96m",
        display_func = function(msg)
            return DEBUG_MODE
        end
    },
    info = {
        name="Info",
        color="[92m",
        color_dark="[32m",
        text_color = "[97m"
    },
    warn = {
        name="Warn",
        color="[93m",
        color_dark="[33m",
        text_color = "[93m"
    },
    error = {
        name="Error",
        color="[91m",
        color_dark="[31m",
        text_color = "[33m"
    }
}

local max_width = 0

for k,v in pairs(log_lvl) do
    if v.name:len()+2 > max_width then
        max_width = v.name:len()+2
    end
end

local function log(txt, lvl, separate)
    if not lvl.display_func or (lvl.display_func and lvl.display_func()) then
        local name_margin = max_width-(lvl.name:len()+2)
        if type(txt) == "string" then
            print('[97m'..os.date("%Y/%m/%d %H:%M:%S")..'[0m | '..lvl.color_dark..'['..lvl.color..lvl.name..lvl.color_dark..']'..string.rep(" ", name_margin)..'[0m | '..lvl.text_color..txt..'[0m')
        elseif type(txt) == "table" then
            for k,v in ipairs(txt) do
                if k == 1 then
                    print('[97m'..os.date("%Y/%m/%d %H:%M:%S")..'[0m | '..lvl.color_dark..'['..lvl.color..lvl.name..lvl.color_dark..']'..string.rep(" ", name_margin)..'[0m | '..lvl.text_color..v..'[0m')
                else
                    print('[90m'..'┗'..string.rep("━", os.date("%Y/%m/%d %H:%M:%S"):len()-2)..'>'..'[0m | '..lvl.color_dark..'['..lvl.color..lvl.name..lvl.color_dark..']'..string.rep(" ", name_margin)..'[0m | '..lvl.text_color..v..'[0m')
                end
            end
        end
        if separate then
            print("\x1b[19C | \x1b["..max_width.."C | ")
        end
    end
end

if DEBUG_MODE then
    log("Debug Mode is enabled!", log_lvl.debug)
    log({"This is a multi-line log test", "Hello", "World"}, log_lvl.debug)
else
    log("Debug Mode is disabled!", log_lvl.info)
end

local function decodeArg(arg)
    return querystring.urldecode(arg)
end

local fail_payload = ""
local fail_headers = {
   {"Content-Length", tostring(#fail_payload)}, -- Must always be set if a payload is returned
   {"Content-Type", "text/plain"}, -- Type of the response's payload (res_payload)
   {"Connection", "close"}, -- Whether to keep the connection alive, or close it
   {"Access-Control-Allow-Origin", "*"},
   code = 400,
   reason = "No Key",
}

local websocket_storage = {}
local websocket_status = {}
local websocket_buffer = {}

local socket_msg_queue = {}
local function awaitSocketMsg(key_name, msg_type, timeout_seconds)
    local timeout = os.time() + timeout_seconds
    while true do
        local last_msg = socket_msg_queue[1]
        if last_msg then
            table.remove(socket_msg_queue, 1)
            if (key_name == last_msg.key) and (msg_type == last_msg.data.type or not msg_type) then
                socket_msg_queue = {}
                return last_msg
            end
        end
        if os.time() >= timeout then
            socket_msg_queue = {}
            return nil
        end
        timer.sleep(200)
    end
end

local ip_response, ip_body = http.request("GET", "http://icanhazip.com")
ip_body	=ip_body:gsub("\n", "")

-- HTTP STUFF

local server = http.createServer("0.0.0.0", 15192, function (req, body)
    local args = json.decode(body)
    if not args or (args and not args.key or args.key == "") then
        local fail_payload = "Invalid Body"
        local fail_headers = {
            {"Content-Length", tostring(#fail_payload)}, -- Must always be set if a payload is returned
            {"Content-Type", "text/plain"}, -- Type of the response's payload (res_payload)
            {"Connection", "close"},
            {"Access-Control-Allow-Origin", "*"}, -- Whether to keep the connection alive, or close it
            code = 400,
            reason = "Invalid Body",
        }
        return fail_headers, fail_payload
    end
    if args.type == "request_history" then
        log("History Requested: "..args.key, log_lvl.info)
        local connection = websocket_storage[args.key]
        local json_data = json.encode({type="request_history"})
        if connection then
            websocket_status[args.key] = "building_history"
            websocket_buffer[args.key] = {}
            connection.write({
                fin = true,
                len = #json_data,
                mask = true,
                opcode = 1,
                payload = json_data,
                rsv1 = false,
                rsv2= false,
                rsv3 = false
            })
            local history_data = awaitSocketMsg(args.key, "response_history", 6)
            websocket_status[args.key] = "none"
            websocket_buffer[args.key] = {}

            if history_data then
                local json_payload = json.encode(history_data.data)

                local json_res_headers = {
                    {"Content-Length", tostring(#json_payload)}, -- Must always be set if a payload is returned
                    {"Content-Type", "application/json"}, -- Type of the response's payload (res_payload)
                    {"Connection", "close"}, -- Whether to keep the connection alive, or close it
                    {"Access-Control-Allow-Origin", "*"},
                    code = 200,
                    reason = "OK",
                }

                log("("..args.key..") Sent Data: "..(#json_payload).." B", log_lvl.info)
                --log("("..args.key..") JSON Payload: "..json_payload, log_lvl.debug)
                return json_res_headers, json_payload
            else
                local fail_payload = "No Connection"
                local fail_headers = {
                    {"Content-Length", tostring(#fail_payload)}, -- Must always be set if a payload is returned
                    {"Content-Type", "text/plain"}, -- Type of the response's payload (res_payload)
                    {"Connection", "close"},
                    {"Access-Control-Allow-Origin", "*"}, -- Whether to keep the connection alive, or close it
                    code = 400,
                    reason = "No Connection",
                }
                log("History request timed out ("..args.key..")", log_lvl.error)
                return fail_headers, fail_payload
            end
        else
            log("Connection '"..args.key.."' doesn't exist!", log_lvl.error)
            local fail_payload = "No Connection"
            local fail_headers = {
                {"Content-Length", tostring(#fail_payload)}, -- Must always be set if a payload is returned
                {"Content-Type", "text/plain"}, -- Type of the response's payload (res_payload)
                {"Connection", "close"},
                {"Access-Control-Allow-Origin", "*"}, -- Whether to keep the connection alive, or close it
                code = 400,
                reason = "No Connection",
            }
            return fail_headers, fail_payload
        end
    end
end)

log("Web Server started on: http://"..ip_body..":"..(15192), log_lvl.info)

-- WEBSOCKET STUFF
local app = require('weblit-app')
local websocket = require("weblit-websocket")

local heartbeat_response = json.encode({type="sv_heartbeat", content=""})

app
    .bind({
        port = 15191,
        host = "0.0.0.0",
    })
    .logging(DEBUG_MODE)

    .use(require('weblit-logger'))
    .use(require('weblit-auto-headers'))
    .use(require('weblit-etag-cache'))

    .websocket(
    {
        path="/"
    }, 
    function(req, read, write)
        local key_value = ""
        if req.query and req.query.key then
            key_value = decodeArg(req.query.key)
        else
            return
        end
        log(color.foreground.green.."("..key_value..") New Websocket Client connected", log_lvl.info)

        if websocket_storage[key_value] then
            log("("..key_value..") Websocket Connection already exists and will be overriden", log_lvl.warn)
            websocket_storage[key_value].write()
        end
        
        websocket_storage[key_value] = {
            read=read,
            write=write,
            req=req
        }
        websocket_status[key_value] = "none"
        websocket_buffer[key_value] = {}
        

        for msg in read do
            local data = json.decode(msg.payload)
            if data then
                log({"("..key_value..") Received request: "..(data.type), "Status: "..websocket_status[key_value]}, log_lvl.debug)
                if websocket_status[key_value] == "none" then
                    socket_msg_queue[#socket_msg_queue+1] = {data=data, key=key_value}
                elseif websocket_status[key_value] == "building_history" then
                    if data.type == "response_history_finish" then
                        socket_msg_queue[#socket_msg_queue+1] = {data={data=websocket_buffer[key_value], type="response_history"}, key=key_value}
                    elseif data.type == "response_history" then
                        websocket_buffer[key_value][#websocket_buffer[key_value]+1] = data.data
                    end
                end
                if data.type == "mc_heartbeat" then
                    log("Received heartbeat", log_lvl.debug)
                    write({
                        fin = true,
                        len = #heartbeat_response,
                        mask = true,
                        opcode = 1,
                        payload = heartbeat_response,
                        rsv1 = false,
                        rsv2= false,
                        rsv3 = false
                    })
                end
            end
        end

        websocket_storage[key_value] = nil
        websocket_status[key_value] = "none"
        websocket_buffer[key_value] = {}
        log(color.foreground.red.."("..key_value..") Websocket Connection Ended", log_lvl.info)

        write()
    end)

    .start()
    log("Websocket Server started on: ws://"..ip_body..":"..(15191).." or ".."ws://localhost:"..(15191), log_lvl.info)

--# WEBSCOEKT STUFF END