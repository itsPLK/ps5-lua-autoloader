
--
-- syscall class
--
-- helper for managing & resolving syscalls
--

syscall = {}

function syscall.init()

    syscall.collect_info()

    print("[+] libkernel base @ " .. hex(libkernel_base))
    print("[+] platform @ " .. PLATFORM)

    if PLATFORM == "ps4" then  -- ps4 requires valid syscall wrapper, which we can scrape from libkernel .text
        local libkernel_text = memory.read_buffer(libkernel_base, 0x40000)
        -- mov rax, <num>; mov r10, rcx; syscall
        local matches = find_pattern(libkernel_text, "48 c7 c0 ? ? ? ? 49 89 ca 0f 05")
        syscall.syscall_wrapper = {}
        for i,offset in ipairs(matches) do
            local num = uint64.unpack(libkernel_text:sub(offset+3, offset+6))
            syscall.syscall_wrapper[num:tonumber()] = libkernel_base + offset - 1
        end
    elseif PLATFORM == "ps5" then -- can be any syscall wrapper in libkernel
        local gettimeofday = memory.read_qword(libc_addrofs.gettimeofday_import)
        syscall.syscall_address = gettimeofday + 7  -- +7 is to skip "mov rax, <num>" instruction
    else
        errorf("invalid platform %s", PLATFORM)
    end

    syscall.do_sanity_check()
end

function syscall.collect_info()

    -- ref: https://github.com/shadps4-emu/shadPS4/blob/0bdd21b4e49c25955b16a3651255381b4a60f538/src/core/module.h#L32
    local INIT_PROC_ADDR_OFFSET = 0x128
    local SEGMENTS_OFFSET = 0x160
    
    local sceKernelGetModuleInfoFromAddr = fcall(libc_addrofs.sceKernelGetModuleInfoFromAddr)
    
    local addr_inside_libkernel = memory.read_qword(libc_addrofs.gettimeofday_import)
    local mod_info = memory.alloc(0x300)

    local ret = sceKernelGetModuleInfoFromAddr(addr_inside_libkernel, 1, mod_info):tonumber()
    if ret ~= 0 then
        error("sceKernelGetModuleInfoFromAddr() error: " .. hex(ret))
    end
    
    libkernel_base = memory.read_qword(mod_info + SEGMENTS_OFFSET)

    -- credit to flatz for this technique
    local init_proc_addr = memory.read_qword(mod_info + INIT_PROC_ADDR_OFFSET)
    local delta = (init_proc_addr - libkernel_base):tonumber()
    
    if delta == 0x0 then
        PLATFORM = "ps4"
    elseif delta == 0x10 then
        PLATFORM = "ps5"
    else
        error("failed to determine PLATFORM")
    end
end

function syscall.resolve(list)
    for name, num in pairs(list) do
        if not syscall[name] then
            if PLATFORM == "ps4" then
                if syscall.syscall_wrapper[num] then
                    syscall[name] = fcall(syscall.syscall_wrapper[num], num)
                else
                    errorf("syscall wrapper for %s (%d) not found in libkernel", name, num)
                end
            elseif PLATFORM == "ps5" then
                syscall[name] = fcall(syscall.syscall_address, num)
            end
        end
    end
end

function syscall.do_sanity_check()

    syscall.resolve({
        getpid = 20,
    })

    local pid = syscall.getpid()
    if not (pid and pid.h == 0 and pid.l ~= 0) then
        error("syscall test failed")
    end
end
