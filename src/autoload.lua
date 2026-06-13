
-- autoload.lua
-- Launches elfldr and sends the unified autoloader payload.




elf_sender = {}
elf_sender.__index = elf_sender


syscall.resolve(
    {
        sendto = 133
    }
)







function elf_sender:load_from_file(filepath)

    if file_exists(filepath) then
        print("Loading elf from:", filepath)

    else
        print("[-] File not found:", filepath)
        send_ps_notification("[-] File not found: \n" .. filepath)
    end

    local self = setmetatable({}, elf_sender)
    self.filepath = filepath
    self.elf_data = file_read(filepath)
    self.elf_size = #self.elf_data

    print("elf size:", self.elf_size)
    return self
end

function elf_sender:sceNetSend(sockfd, buf, len, flags, addr, addrlen)
    return syscall.sendto(sockfd, buf, len, flags, addr, addrlen):tonumber()
end
function elf_sender:sceNetSocket(domain, type, protocol)
    return syscall.socket(domain, type, protocol):tonumber()
end
function elf_sender:sceNetSocketClose(sockfd)
    return syscall.close(sockfd):tonumber()
end
function elf_sender:htons(port)
    return bit32.bor(bit32.lshift(port, 8), bit32.rshift(port, 8)) % 0x10000
end

function elf_sender:send_to_localhost(port)

    local sockfd = elf_sender:sceNetSocket(2, 1, 0) -- AF_INET=2, SOCK_STREAM=1
    print("Socket fd:", sockfd)
    assert(sockfd >= 0, "socket creation failed")
    local enable = memory.alloc(4)
    memory.write_dword(enable, 1)
    syscall.setsockopt(sockfd, 1, 2, enable, 4) -- SOL_SOCKET=1, SO_REUSEADDR=2

    local sockaddr = memory.alloc(16)

    memory.write_byte(sockaddr + 0, 16)
    memory.write_byte(sockaddr + 1, 2) -- AF_INET
    memory.write_word(sockaddr + 2, elf_sender:htons(port))

    memory.write_byte(sockaddr + 4, 0x7F) -- 127
    memory.write_byte(sockaddr + 5, 0x00) -- 0
    memory.write_byte(sockaddr + 6, 0x00) -- 0
    memory.write_byte(sockaddr + 7, 0x01) -- 1

    local buf = memory.alloc(#self.elf_data)
    memory.write_buffer(buf, self.elf_data)

    local total_sent = elf_sender:sceNetSend(sockfd, buf, #self.elf_data, 0, sockaddr, 16)
    elf_sender:sceNetSocketClose(sockfd)
    if total_sent < 0 then
        print("[-] error sending elf data to localhost")
        send_ps_notification("error sending elf data to localhost")
        return
    end
    print(string.format("Successfully sent %d bytes to loader", total_sent))
end




function wait_for_elfldr()
    local loader_active = false
    for i = 1, 50 do
        if is_port_open(9021) then
            loader_active = true
            break
        end
        sleep(200, "ms")
    end

    if not loader_active then
        print("[ERROR] autoloader: elf_loader is not active")
        send_ps_notification("[ERROR] autoloader:\nelf_loader is not active")
    else
        print("[+] autoloader: elf_loader is active")
    end
end


function main()
    if not is_jailbroken() then
        send_ps_notification("Jailbreak failed.\nClosing game...")
        syscall.kill(syscall.getpid(), 15)
        return
    end




    if not IS_KEXP then
        start_elf_loader()
    end


    wait_for_elfldr()

    local payload_name = "@@UNIFIED_AUTOLOADER_FILE@@"
    local payload_path = get_savedata_path() .. payload_name


    if not file_exists(payload_path) then
        print("[-] Payload not found: " .. payload_name)
        send_ps_notification("[-] Payload not found:\n" .. payload_name)
        return
    end

    print("Loading payload from: " .. payload_path)


    elf_sender:load_from_file(payload_path):send_to_localhost(9021)

    local msg = "Successfully loaded unified autoloader"
    print(msg)
    if SHOW_DEBUG_NOTIFICATIONS then
        send_ps_notification(msg)
    end
    send_ps_notification("Loader finished!\n\nClosing game...")
    syscall.kill(syscall.getpid(), 15)
end


main()
