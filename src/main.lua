
FORCE_LAPSE_EXPLOIT = false
FORCE_P2JB_EXPLOIT = false
SHOW_DEBUG_NOTIFICATIONS = true

LUA_LOADER_VERSION = "@@VERSION@@"


options = {
    enable_signal_handler = true,
    run_loader_with_gc_disabled = false,
}

WRITABLE_PATH = "/av_contents/content_tmp/"
LOG_FILE = WRITABLE_PATH .. "loader_log.txt"
log_fd = io.open(LOG_FILE, "w")

game_name = nil
eboot_base = nil
libc_base = nil
libkernel_base = nil

gadgets = nil
eboot_addrofs = nil
libc_addrofs = nil

native_cmd_handler = nil
native_invoke = nil

kernel_offset = nil

old_print = print
function print(...)
    
    local out = prepare_arguments(...) .. "\n"
    
    old_print(out) -- print to stdout

    if client_fd and native_invoke then
        syscall.write(client_fd, out, #out) -- print to socket
    end

    log_fd:write(out) -- print to file
    log_fd:flush()
end

package.path = package.path .. ";/savedata0/?.lua"

require "globals"
require "offsets"
require "misc"
require "bit32"
require "hash"
require "uint64"
require "struct"
require "lua"
require "memory"
require "ropchain"
require "syscall"
require "signal"
require "native"
require "thread"
require "kernel_offset"
require "kernel"
require "gpu"

require "elf_loader"



function run_lua_code(lua_code)

    assert(client_fd)

    local script, err = loadstring(lua_code)
    if err then
        local err_msg = "error loading script: " .. err
        syscall.write(client_fd, err_msg, #err_msg)
        return
    end

    local env = {
        print = function(...)
            local out = prepare_arguments(...) .. "\n"
            syscall.write(client_fd, out, #out)
        end,
        printf = function(fmt, ...)
            local out = string.format(fmt, ...) .. "\n"
            syscall.write(client_fd, out, #out)
        end
    }

    setmetatable(env, { __index = _G })
    setfenv(script, env)

    err = run_with_coroutine(script)

    -- pass error to client
    if err then
        syscall.write(client_fd, err, #err)
    end

end

function remote_lua_loader(port)

    assert(port)

    local enable = memory.alloc(4)
    local sockaddr_in = memory.alloc(16)
    local addrlen = memory.alloc(8)
    local tmp = memory.alloc(8)

    local command_magic = 0xffffffff
    local maxsize = 500 * 1024  -- 500kb
    local buf = memory.alloc(maxsize)

    local sock_fd = syscall.socket(AF_INET, SOCK_STREAM, 0):tonumber()
    if sock_fd < 0 then
        error("socket() error: " .. get_error_string())
    end

    memory.write_dword(enable, 1)
    if syscall.setsockopt(sock_fd, SOL_SOCKET, SO_REUSEADDR, enable, 4):tonumber() < 0 then
        error("setsockopt() error: " .. get_error_string())
    end

    local function htons(port)
        return bit32.bor(bit32.lshift(port, 8), bit32.rshift(port, 8)) % 0x10000
    end

    memory.write_byte(sockaddr_in + 1, AF_INET)
    memory.write_word(sockaddr_in + 2, htons(port))
    memory.write_dword(sockaddr_in + 4, INADDR_ANY)

    if syscall.bind(sock_fd, sockaddr_in, 16):tonumber() < 0 then
        error("bind() error: " .. get_error_string())
    end
 
    if syscall.listen(sock_fd, 3):tonumber() < 0 then
        error("listen() error: " .. get_error_string())
    end

    local current_ip = get_current_ip()
    local network_str = nil
    
    if current_ip then
        network_str = string.format("%s:%d", current_ip, port)
    else
        network_str = string.format("port %d", port)
    end

    --notify(string.format("remote lua loader\nrunning on %s %s\nlistening on %s", PLATFORM, FW_VERSION, network_str))

    local fake_client_coroutine = coroutine.create(function()
        send_lua_to_localhost(9026, kernel_exploit_lua)
        send_lua_to_localhost(9026, "autoload.lua")
    end)

    local fake_client_started = false

    while true do

        print("[+] waiting for new connection...")
        
        if not fake_client_started then
            fake_client_started = true
            coroutine.resume(fake_client_coroutine)
        end

        memory.write_dword(addrlen, 16)

        client_fd = syscall.accept(sock_fd, sockaddr_in, addrlen):tonumber()  
        
        -- need to reinit the socket after rest mode
        while client_fd < 0 do
            print("accept() error: " .. get_error_string())
            
            syscall.close(sock_fd)
            
            sock_fd = syscall.socket(AF_INET, SOCK_STREAM, 0):tonumber()
            if sock_fd < 0 then
                error("socket() error: " .. get_error_string())
            end

            memory.write_dword(enable, 1)
            if syscall.setsockopt(sock_fd, SOL_SOCKET, SO_REUSEADDR, enable, 4):tonumber() < 0 then
                error("setsockopt() error: " .. get_error_string())
            end

            memory.write_byte(sockaddr_in + 1, AF_INET)
            memory.write_word(sockaddr_in + 2, htons(port))
            memory.write_dword(sockaddr_in + 4, INADDR_ANY)

            if syscall.bind(sock_fd, sockaddr_in, 16):tonumber() < 0 then
                error("bind() error: " .. get_error_string())
            end
         
            if syscall.listen(sock_fd, 3):tonumber() < 0 then
                error("listen() error: " .. get_error_string())
            end
            
            print("[+] waiting for new connection...")
            
            memory.write_dword(addrlen, 16)

            client_fd = syscall.accept(sock_fd, sockaddr_in, addrlen):tonumber()  
        end
 
        syscall.read(client_fd, tmp, 8)
        local size = memory.read_qword(tmp):tonumber()
        
        -- printf("[+] accepted new connection client fd %d", client_fd)

        if size > 0 and size < maxsize then
            
            local cur_size = size
            local cur_buf = buf
            
            while cur_size > 0 do
                local read_size = syscall.read(client_fd, cur_buf, cur_size):tonumber()
                if read_size < 0 then
                    error("read() error: " .. get_error_string())
                end
                cur_buf = cur_buf + read_size
                cur_size = cur_size - read_size
            end
            
            local lua_code = memory.read_buffer(buf, size)

            -- printf("[+] accepted lua code with size %d (%s)", #lua_code, hex(#lua_code))
            
            if options.enable_signal_handler then
                signal.set_sink_fd(client_fd)
            end
            run_lua_code(lua_code)

            syscall.close(client_fd)

        elseif size == command_magic then
            local command_tmp = memory.alloc(4)
            syscall.read(client_fd, command_tmp, 1)
            local command = memory.read_dword(command_tmp):tonumber()
            
            if command == 0 then
                signal.clear()
                options.enable_signal_handler = false
                local msg = "command: Disabled signal handler"
                syscall.write(client_fd, msg, #msg)
            elseif command == 1 then
                signal.register()
                options.enable_signal_handler = true
                local msg = "command: Enabled signal handler"
                syscall.write(client_fd, msg, #msg)
            else
                local err = string.format("error: invalid command %d\n", command)
                syscall.write(client_fd, err, #err)
            end
            
            syscall.close(client_fd)
        else
            local err = string.format("error: lua code exceed maxsize " ..
                "(given %s maxsize %s)\n", hex(size), hex(maxsize))
            syscall.write(client_fd, err, #err)
            syscall.close(client_fd)
        end

        client_fd = nil

        -- init kernel r/w class if exploit state exists
        if not kernel.rw_initialized then
            initialize_kernel_rw()
        end
    end

    syscall.close(sock_fd)
end


old_error = error
function error(msg)
    if type(msg) == "table" then
        msg = table.concat(msg, "\n")
    end

    if not msg or msg == "" then
        msg = "Unknown error"
    end

    send_ps_notification("Error:\n" .. msg)

    old_error(msg)
end

function send_lua_to_localhost(port, file)
    
    local file_path = get_savedata_path() .. file

    -- Read the lua file
    local lua_code = file_read(file_path)
    if not lua_code then
        error("Failed to read " .. file_path)
    end
    
    -- Create socket
    local sockfd = syscall.socket(AF_INET, SOCK_STREAM, 0):tonumber()
    if sockfd < 0 then
        error("socket creation failed: " .. get_error_string())
    end
    
    -- Setup address
    local sockaddr = memory.alloc(16)
    memory.write_byte(sockaddr + 1, AF_INET)        -- sin_family
    memory.write_word(sockaddr + 2, htons(port))    -- sin_port
    memory.write_dword(sockaddr + 4, 0x0100007f)    -- 127.0.0.1 in network byte order
    
    -- Connect to localhost
    local connect_result = syscall.connect(sockfd, sockaddr, 16):tonumber()
    if connect_result < 0 then
        syscall.close(sockfd)
        error("connect failed: " .. get_error_string())
    end
    
    -- Send size in little-endian qword
    local size_buf = memory.alloc(8)
    local lua_size = #lua_code
    memory.write_byte(size_buf + 0, bit32.band(lua_size, 0xFF))
    memory.write_byte(size_buf + 1, bit32.band(bit32.rshift(lua_size, 8), 0xFF))
    memory.write_byte(size_buf + 2, bit32.band(bit32.rshift(lua_size, 16), 0xFF))
    memory.write_byte(size_buf + 3, bit32.band(bit32.rshift(lua_size, 24), 0xFF))
    memory.write_byte(size_buf + 4, 0)
    memory.write_byte(size_buf + 5, 0)
    memory.write_byte(size_buf + 6, 0)
    memory.write_byte(size_buf + 7, 0)
    
    syscall.write(sockfd, size_buf, 8)
    
    -- Send the lua code
    local code_buf = memory.alloc(#lua_code)
    memory.write_buffer(code_buf, lua_code)
    local bytes_sent = syscall.write(sockfd, code_buf, #lua_code):tonumber()
    
    return bytes_sent > 0
end

function get_savedata_path()
    local path = "/savedata0/"
    if is_jailbroken() then
        path = "/mnt/sandbox/" .. get_title_id() .. "_000/savedata0/"
    end
    return path
end

function htons(port)
    return bit32.bor(bit32.lshift(port, 8), bit32.rshift(port, 8)) % 0x10000
end

function main()

    -- setup limited read & write primitives
    lua.setup_primitives()
    print("[+] lua r/w primitives achieved")

    syscall.init()
    print("[+] syscall initialized")

    native.register()
    print("[+] native handler registered")

    print("[+] arbitrary r/w primitives achieved")

    -- resolve required syscalls for remote lua loader
    -- note: syscall resolved here will also be available in the payloads
    syscall.resolve({
        read = 0x3,
        write = 0x4,
        open = 0x5,
        close = 0x6,
        getuid = 0x18,
        kill = 0x25,
        accept = 0x1e,
        pipe = 0x2a,
        mprotect = 0x4a,
        socket = 0x61,
        connect = 0x62,
        bind = 0x68,
        setsockopt = 0x69,
        listen = 0x6a,
        getsockopt = 0x76,
        netgetiflist = 0x7d,
        sysctl = 0xca,
        nanosleep = 0xf0,
        sigaction = 0x1a0,
        thr_self = 0x1b0,
        dlsym = 0x24f,
        dynlib_load_prx = 0x252,
        dynlib_unload_prx = 0x253,
        is_in_sandbox = 0x249,
    })

    -- setup signal handler
    if options.enable_signal_handler then
        signal.register()
        print("[+] signal handler registered")
    end

    FW_VERSION = get_version()

    send_ps_notification(string.format("\n\nPS5 Lua Autoloader %s by PLK\n\n%s %s\nGame: %s\n\n", LUA_LOADER_VERSION, string.upper(PLATFORM), FW_VERSION, game_name))

    if PLATFORM ~= "ps5" then
        notify(string.format("This only works on ps5 (current %s %s)", PLATFORM, FW_VERSION))
        return
    end

    if FORCE_P2JB_EXPLOIT then
        kernel_exploit_lua = "p2jb.lua"
    elseif FORCE_LAPSE_EXPLOIT then
        kernel_exploit_lua = "lapse.lua"
    elseif tonumber(FW_VERSION) <= 7.61 then
        kernel_exploit_lua = "umtx.lua"
    elseif tonumber(FW_VERSION) <= 10.01 then
        kernel_exploit_lua = "lapse.lua"
    elseif tonumber(FW_VERSION) <= 12.70 then
        kernel_exploit_lua = "p2jb.lua"
    else
        notify(string.format("Unsupported firmware version (%s %s)", PLATFORM, FW_VERSION))
        return
    end

    IS_KEXP = (kernel_exploit_lua == "p2jb.lua")

    thread.init()

    kernel_offset = get_kernel_offset()

    local run_loader = function()
        local port = 9026
        remote_lua_loader(port)
    end

    if options.run_loader_with_gc_disabled then
        run_nogc(run_loader) -- stable but exhaust memory
    else
        run_loader() -- less stable but doesnt exhaust memory
    end

    notify("finished")

    sleep(10000000)
end

function entry()
    local err = run_with_coroutine(main)
    if err then
        notify(err)
        print(err)
    end
end

entry()
