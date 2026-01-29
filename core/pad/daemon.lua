--[[
pad daemon - background event loop

Runs an epoll-based loop with:
  - clipboard timerfd (every 2s)
  - vacuum timerfd (every 1h)
  - (future) inotify file watch, unix socket, websocket listener
]]

local ffi = require("ffi")
local epoll = require("dep.epoll")

ffi.cdef[[
  int fork(void);
  int setsid(void);
  int getpid(void);
  int close(int fd);
  int open(const char *pathname, int flags, int mode);
  int dup2(int oldfd, int newfd);

  int timerfd_create(int clockid, int flags);

  struct timespec {
    long tv_sec;
    long tv_nsec;
  };
  struct itimerspec {
    struct timespec it_interval;
    struct timespec it_value;
  };
  int timerfd_settime(int fd, int flags, const struct itimerspec *new_value, struct itimerspec *old_value);

  int kill(int pid, int sig);
]]

local mod = {}

-- paths

local function pad_dir()
  return os.getenv("PAD_DIR") or (os.getenv("HOME") .. "/.pad")
end

function mod.pid_path()
  return pad_dir() .. "/pad.pid"
end

function mod.log_path()
  return pad_dir() .. "/pad.log"
end

-- pid file

function mod.write_pid()
  local f = io.open(mod.pid_path(), "w")
  if not f then error("pad: could not write PID file") end
  f:write(tostring(ffi.C.getpid()))
  f:close()
end

function mod.read_pid()
  local f = io.open(mod.pid_path(), "r")
  if not f then return nil end
  local pid = tonumber(f:read("*a"))
  f:close()
  return pid
end

function mod.clear_pid()
  os.remove(mod.pid_path())
end

function mod.is_running()
  local pid = mod.read_pid()
  if not pid then return false end
  -- signal 0 = check if process exists
  return ffi.C.kill(pid, 0) == 0
end

-- timerfd

local CLOCK_MONOTONIC = 1

local function create_timer(interval_sec)
  local fd = ffi.C.timerfd_create(CLOCK_MONOTONIC, 0)
  assert(fd >= 0, "pad: timerfd_create failed")
  local spec = ffi.new("struct itimerspec")
  spec.it_interval.tv_sec = interval_sec
  spec.it_interval.tv_nsec = 0
  spec.it_value.tv_sec = interval_sec
  spec.it_value.tv_nsec = 0
  assert(ffi.C.timerfd_settime(fd, 0, spec, nil) == 0, "pad: timerfd_settime failed")
  return fd
end

local timer_buf = ffi.new("uint64_t[1]")

local function drain_timer(fd)
  ffi.C.read(fd, timer_buf, 8)
end

-- daemonize

local function daemonize(log_path)
  local pid = ffi.C.fork()
  if pid > 0 then os.exit(0) end
  if pid < 0 then error("pad: fork failed") end
  ffi.C.setsid()
  -- redirect stdout/stderr to log
  local log_fd = ffi.C.open(log_path, 0x241, 0x1A4) -- O_WRONLY|O_CREAT|O_APPEND, 0644
  if log_fd >= 0 then
    ffi.C.dup2(log_fd, 1) -- stdout
    ffi.C.dup2(log_fd, 2) -- stderr
    ffi.C.close(log_fd)
  end
  -- close stdin
  ffi.C.close(0)
end

-- log helper (writes to stderr, which is redirected to log file in daemon mode)

local function log(msg)
  io.stderr:write(os.date("%Y-%m-%d %H:%M:%S") .. " " .. msg .. "\n")
  io.stderr:flush()
end

-- main loop

function mod.run(pad, clipboard, foreground)
  if mod.is_running() then
    io.stderr:write("pad: daemon already running (pid " .. mod.read_pid() .. ")\n")
    return false
  end

  if not foreground then
    daemonize(mod.log_path())
  end

  mod.write_pid()
  log("pad daemon started (pid " .. ffi.C.getpid() .. ")")

  local ep = epoll.new()
  local last_clip_hash = nil

  -- detect clipboard tool once at startup
  local clip_tool = clipboard and clipboard.detect()

  -- clipboard timer (every 2s)
  if clip_tool then
    local clip_fd = create_timer(2)
    ep:add(clip_fd, function()
      drain_timer(clip_fd)
      local content, tool = clipboard.read()
      if content then
        local hash = pad.hash(content)
        if hash ~= last_clip_hash then
          last_clip_hash = hash
          local id, h = pad.ingest(content, { source = "clipboard", metadata = { clipboard_tool = tool } })
          log("clipboard -> [" .. id .. "] " .. h)
        end
      end
    end)
    log("clipboard watch enabled (" .. clip_tool.name .. ", 2s interval)")
  else
    log("clipboard watch disabled (no clipboard tool found)")
  end

  -- vacuum timer (every 1h)
  local vacuum_fd = create_timer(3600)
  ep:add(vacuum_fd, function()
    drain_timer(vacuum_fd)
    pad.recalculate_coldness()
    log("vacuum: coldness recalculated")
  end)
  log("vacuum timer enabled (1h interval)")

  -- run
  log("entering event loop")
  ep:loop()
end

-- stop

function mod.stop()
  local pid = mod.read_pid()
  if not pid then
    io.stderr:write("pad: no daemon running\n")
    return false
  end
  if ffi.C.kill(pid, 0) ~= 0 then
    io.stderr:write("pad: stale PID file (process " .. pid .. " not running)\n")
    mod.clear_pid()
    return false
  end
  ffi.C.kill(pid, 15) -- SIGTERM
  mod.clear_pid()
  io.stderr:write("pad: daemon stopped (pid " .. pid .. ")\n")
  return true
end

-- status

function mod.status()
  local pid = mod.read_pid()
  if not pid then
    io.stderr:write("pad: no daemon running\n")
    return false
  end
  if ffi.C.kill(pid, 0) ~= 0 then
    io.stderr:write("pad: stale PID file (process " .. pid .. " not running)\n")
    mod.clear_pid()
    return false
  end
  io.stderr:write("pad: daemon running (pid " .. pid .. ")\n")
  return true
end

return mod
