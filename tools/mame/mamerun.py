#!/usr/bin/env python3
"""Boot a ProDOS volume in headless MAME (apple2gs) and read memory.

Runs until any --wait condition holds (a little-endian u16 at ADDR
equals VALUE) or --seconds of emulated time pass, then dumps the
requested ranges, the 40-column text screen and the CPU registers.
Prints one JSON object on stdout.

Input injection (run() only): `triggers` maps a name to (addr, value);
each time the u16 at addr becomes equal to value counts as one
occurrence. An input fires `at` frames after occurrence `n` (default 1)
of trigger `after` (default "ready"; "start" counts from frame 0). An
input is one of
    {"at": n, "key": "s"}                  type text (natural keyboard)
    {"at": n, "coded": "{DOWN}{ENTER}"}    natural keyboard with MAME key codes
    {"at": n, "button": 1}                 mouse button 0 down (1) / up (0)
    {"at": n, "move": [dx, dy], "frames": k}  k frames of mouse deltas
    {"at": n, "snap": "name"}              dump SHR memory as dumps["shr_name"]
    {"at": n, "press": "Command / Open Apple", "port": ":macadb:KEY3",
     "value": 1}                           hold (1) or release (0) a key field
    {"at": n, "save": "name"}              save a MAME state "name" (state_dir)
    {"at": n, "poke": [addr, v], "frames": k}  write the u16 v at addr, k frames
    {"at": n, "seek": [x, y, ax, ay], "frames": k}  move the mouse a step a
                                           frame, k frames, toward the cursor
                                           position (x, y) the program keeps
                                           as u16s at ax and ay (a step every
                                           6 frames, so it reads each one)
run(..., state_dir=D, load_state="name") starts from a saved state; frames
then count from the load.
run(..., find=(OFFSET, U32)): a program the GS/OS Loader placed (bank-
aligned segments) is found by a u32 signature at OFFSET of a bank, checked
in every bank twice a second until it turns up; wait and dump addresses
from REL (0x1000000) up are then that bank + (address - REL), and a wait
on one is false until then. result["bank"] is the bank found.
Mouse deltas drive the ADB mouse's analog X/Y fields.

    mamerun.py --image build/abi.po --wait 0x022110=0xAB15 \
        --dump abi_val:0x022002:268 --settle 120

The interactive counterpart, with the claudebridge Lua bridge, is
tools/mame/run-mame.sh.
"""
import argparse
import json
import os
import subprocess
import sys
import tempfile

REL = 0x1000000                           # run(find=...): bank-relative addresses
AMPLE = os.path.expanduser("~/Library/Application Support/Ample")
ROMPATH = os.path.join(AMPLE, "roms")


def parse_int(s):
    return int(s, 0)


LUA = r"""
local waits = {%(waits)s}
local dumps = {%(dumps)s}
local max_frames = %(max_frames)d
local settle = %(settle)d
local occurrence = %(occurrence)d
local seen, was_true = 0, false
local triggers = {%(triggers)s}
local inputs = {%(inputs)s}
local frame, hit_frame, hit, ready_frame = 0, nil, nil, nil
local profile, prof = %(profile)s, {}
local window = {%(window)s}            -- profile and taps only in [from, to) frames
local taps, tapped = {%(taps)s}, false
local function in_window(f) return #window == 0 or (f >= window[1] and f < window[2]) end
local function taps_on()
    local sp = manager.machine.devices[":maincpu"].spaces["program"]
    for _, t in ipairs(taps) do
        t.r, t.w = t.r or 0, t.w or 0
        t.hr = sp:install_read_tap(t[2], t[3], t[1] .. "_r", function(o, d, m) t.r = t.r + 1 end)
        t.hw = sp:install_write_tap(t[2], t[3], t[1] .. "_w", function(o, d, m)
            t.w = t.w + 1
            if t[4] and t.w <= t[4] then        -- log the first writes: frame, PB:PC, address, data
                local cpu = manager.machine.devices[":maincpu"]
                print(string.format("MAMERUN-WLOG %%s %%d %%02x%%04x %%06x %%x", t[1], frame,
                    cpu.state["PB"].value, cpu.state["PC"].value, o, d))
            end
        end)
    end
    tapped = true
end
local function taps_off()
    for _, t in ipairs(taps) do t.hr:remove(); t.hw:remove() end
    tapped = false
end
local load_state, loading = %(load_state)s, false
local traces = {%(traces)s}
local garbage = %(garbage)s
local garbage_top = %(garbage_top)d
local find, base = %(find)s, nil
local REL = 0x1000000
local function at(a)
    if a < REL then return a end
    if base == nil then return nil end
    return base + a - REL
end
local smx, smy = 128, 128               -- the mouse fields' values (seek)
local function field(port, name) return manager.machine.ioport.ports[port].fields[name] end
local function mem() return manager.machine.devices[":maincpu"].spaces["program"] end
local function hex(a, n)
    local m, t = mem(), {}
    for i = 0, n - 1 do t[#t + 1] = string.format("%%02x", m:read_u8(a + i)) end
    return table.concat(t)
end
local function apply(i)
    local kind, a = i[2], i[3]
    if kind == "key" then manager.machine.natkeyboard:post(a)
    elseif kind == "coded" then manager.machine.natkeyboard:post_coded(a)
    elseif kind == "btn" then field(":macadb:MOUSE0", "Mouse Button 0"):set_value(a)
    elseif kind == "mx" then smx = a; field(":macadb:MOUSE1", "Mouse X"):set_value(a)
    elseif kind == "my" then smy = a; field(":macadb:MOUSE2", "Mouse Y"):set_value(a)
    elseif kind == "seek" then
        local x, y, ax, ay = a:match("^(%%d+)|(%%d+)|(%%d+)|(%%d+)$")
        if frame %% 6 ~= 0 then return end  -- let the program read each step
        local cx, cy = mem():read_u16(tonumber(ax)), mem():read_u16(tonumber(ay))
        local dx, dy = tonumber(x) - cx, tonumber(y) - cy
        if dx ~= 0 then smx = (smx + (dx > 0 and 1 or -1)) %% 256; field(":macadb:MOUSE1", "Mouse X"):set_value(smx) end
        if dy ~= 0 then smy = (smy + (dy > 0 and 1 or -1)) %% 256; field(":macadb:MOUSE2", "Mouse Y"):set_value(smy) end
    elseif kind == "press" then
        local port, name, v = a:match("^(.-)|(.-)|(%%d+)$")
        field(port, name):set_value(tonumber(v))
    elseif kind == "save" then
        manager.machine:save(a)
    elseif kind == "poke" then
        local addr, v = a:match("^(%%d+)|(%%d+)$")
        mem():write_u16(tonumber(addr), tonumber(v))
    elseif kind == "snap" then
        print("MAMERUN-DUMP shr_" .. a .. " e12000 " .. hex(0xE12000, 0x8000))
    end
end
local function text_screen()
    local m, rows = mem(), {}
    for r = 0, 23 do
        local base = 0x400 + 0x80 * (r %% 8) + 0x28 * (r // 8)
        local t = {}
        for c = 0, 39 do
            local b = m:read_u8(base + c) & 0x7f
            if b < 0x20 then b = b + 0x40 end
            t[#t + 1] = string.char(b)
        end
        rows[#rows + 1] = (table.concat(t):gsub("%%s+$", ""))
    end
    return rows
end
local function report(status)
    local cpu = manager.machine.devices[":maincpu"]
    print("MAMERUN-STATUS " .. status .. " " .. frame .. " " .. tostring(hit))
    for _, d in ipairs(dumps) do
        local a = at(d[2])
        if a ~= nil then
            print("MAMERUN-DUMP " .. d[1] .. " " .. string.format("%%06x", a) .. " " .. hex(a, d[3]))
        end
    end
    for i, row in ipairs(text_screen()) do print("MAMERUN-TEXT " .. (i - 1) .. "|" .. row) end
    for a, n in pairs(prof) do print(string.format("MAMERUN-PROF %%06x %%d", a, n)) end
    if tapped then taps_off() end
    for _, t in ipairs(taps) do print("MAMERUN-TAP " .. t[1] .. " " .. (t.r or 0) .. " " .. (t.w or 0)) end
    for _, r in ipairs({"PC", "PB", "DB", "D", "S", "A", "X", "Y", "P", "E"}) do
        local ok, v = pcall(function() return cpu.state[r].value end)
        if ok then print("MAMERUN-REG " .. r .. " " .. string.format("%%x", v)) end
    end
    manager.machine:exit()
end
emu.register_frame_done(function()
    if load_state then                      -- load first; count from there
        if not loading then
            loading = true
            manager.machine:load(load_state)
        else
            load_state = nil
        end
        return
    end
    frame = frame + 1
    if find and base == nil and frame %% 30 == 0 then
        local m = mem()
        for b = 2, (garbage_top >> 16) - 1 do
            if m:read_u32((b << 16) + find[1]) == find[2] then
                base = b << 16
                print("MAMERUN-BANK " .. b .. " " .. frame)
                break
            end
        end
    end
    for _, t in ipairs(traces) do
        local v = mem():read_u16(t[2])
        if v ~= t.last then
            t.last = v
            print("MAMERUN-TRACE " .. t[1] .. " " .. frame .. " " .. v)
        end
    end
    if #taps > 0 then
        if in_window(frame) and not tapped then taps_on()
        elseif tapped and not in_window(frame) then taps_off() end
    end
    if profile and in_window(frame) then
        local cpu = manager.machine.devices[":maincpu"]
        local a = (cpu.state["PB"].value << 16) | cpu.state["PC"].value
        prof[a] = (prof[a] or 0) + 1
    end
    if frame == 1 and garbage then
        -- a real machine's RAM at power-on: not zeroes. Banks $02 up and
        -- bank 0's $0800-$1FFF (the engine's direct page and stack).
        local m, x = mem(), garbage
        local function fill(a, b)
            for at = a, b - 4, 4 do
                x = (x * 1103515245 + 12345) & 0xFFFFFFFF
                m:write_u32(at, x)
            end
        end
        fill(0x0800, 0x2000)
        fill(0x020000, garbage_top)
    end
    if frame == 1 and #inputs > 0 then
        field(":macadb:MOUSE1", "Mouse X"):set_value(128)
        field(":macadb:MOUSE2", "Mouse Y"):set_value(128)
    end
    for name, t in pairs(triggers) do
        local now = mem():read_u16(t[1]) == t[2]
        if now and not t.was then
            t.frames = t.frames or {}
            t.frames[#t.frames + 1] = frame
            print("MAMERUN-TRIGGER " .. name .. " " .. #t.frames .. " " .. frame)
        end
        t.was = now
    end
    for _, i in ipairs(inputs) do
        local t = triggers[i[4]]
        local f = t and t.frames and t.frames[i[5]]
        if i[4] == "start" then f = 0 end
        if f ~= nil and frame - f == i[1] then apply(i) end
    end
    if hit_frame == nil then
        local now = false
        for _, w in ipairs(waits) do
            local a = at(w[1])
            if a ~= nil and mem():read_u16(a) == w[2] then
                now = true
                hit = string.format("0x%%06x", w[1])
                break
            end
        end
        if now and not was_true then
            seen = seen + 1
            if seen >= occurrence then hit_frame = frame end
        end
        was_true = now
    end
    if hit_frame ~= nil and frame >= hit_frame + settle then
        report("hit")
    elseif frame >= max_frames then
        report("timeout")
    end
end)
"""


def expand_inputs(inputs):
    """Turn input specs into (frame, kind, value, trigger, n) events. Mouse
    fields are absolute 8-bit values that start at 128; the ADB mouse
    reports the change, so a move becomes one small step per frame."""
    events, mx, my = [], 128, 128
    order = sorted(inputs, key=lambda i: (i.get("after", "ready"), i.get("n", 1), i["at"]))
    for i in order:
        at, trig, n = i["at"], i.get("after", "ready"), i.get("n", 1)
        if "key" in i:
            events.append((at, "key", i["key"], trig, n))
        elif "button" in i:
            events.append((at, "btn", int(i["button"]), trig, n))
        elif "coded" in i:
            events.append((at, "coded", i["coded"], trig, n))
        elif "snap" in i:
            events.append((at, "snap", i["snap"], trig, n))
        elif "save" in i:
            events.append((at, "save", i["save"], trig, n))
        elif "seek" in i:
            for k in range(i.get("frames", 1)):
                events.append((at + k, "seek", "%d|%d|%d|%d" % tuple(i["seek"]), trig, n))
        elif "poke" in i:
            for k in range(i.get("frames", 1)):
                events.append((at + k, "poke", "%d|%d" % tuple(i["poke"]), trig, n))
        elif "press" in i:
            events.append((at, "press", f'{i["port"]}|{i["press"]}|{int(i.get("value", 1))}', trig, n))
        elif "move" in i:
            dx, dy = i["move"]
            for k in range(i.get("frames", 1)):
                mx, my = (mx + dx) % 256, (my + dy) % 256
                if dx:
                    events.append((at + k, "mx", mx, trig, n))
                if dy:
                    events.append((at + k, "my", my, trig, n))
    return events


def lua_value(v):
    return f'"{v}"' if isinstance(v, str) else str(v)


def run(image, waits, dumps, seconds, settle, ramsize="8M", timeout=None,
        ready=None, inputs=(), occurrence=1, triggers=None, profile=False,
        state_dir=None, load_state=None, traces=(), garbage=None, zip=False, wav=None,
        image2=None, find=None, card="scsi", window=None, taps=()):
    """zip: emulate a 16 MHz ZipGS, as Ample's configuration does (the
    a2_config CPU type, set through a cfg file in MAME's working folder).
    garbage: a seed; RAM is filled with pseudo-random bytes at frame 1.
    wav: a path; MAME's sound output is recorded there (-wavwrite).
    image2: a second ProDOS volume, as the disk card's second drive.
    card: slot 7's disk card (MAME's name: scsi, hsscsi, cffa2, ...).
    window: (from, to) frames: profile and taps only then.
    taps: (name, start, end) address ranges whose CPU reads and writes are
    counted (byte accesses), in the window: result["taps"][name] = (r, w).
    A fourth element n logs the first n writes: result["wlog"] = [[name,
    frame, PB:PC (after the write), address, data], ...].
    traces: (name, addr) u16 values logged at each frame they change:
    result["traces"][name] = [(frame, value), ...]."""
    """occurrence: stop at the n-th time a wait condition becomes true
    (e.g. 2 to see a program finish a second time after a relaunch).
    ready: shorthand for triggers={"ready": ready}."""
    trig = dict(triggers or {})
    if ready is not None:
        trig["ready"] = ready
    lua = LUA % {
        "waits": ",".join(f"{{{a},{v}}}" for a, v in waits),
        "dumps": ",".join(f'{{"{n}",{a},{l}}}' for n, a, l in dumps),
        "max_frames": int(seconds * 60),
        "settle": settle,
        "profile": "true" if profile else "false",
        "window": f"{window[0]},{window[1]}" if window else "",
        "taps": ",".join(f'{{"{t[0]}",{t[1]},{t[2]}' + (f',{t[3]}' if len(t) > 3 else '') + '}' for t in taps),
        "load_state": f'"{load_state}"' if load_state else "nil",
        "traces": ",".join(f'{{"{n}",{a}}}' for n, a in traces),
        "garbage": str(garbage) if garbage else "nil",
        "garbage_top": int(ramsize.rstrip("M")) << 20,
        "find": f"{{{find[0]},{find[1]}}}" if find else "nil",
        "occurrence": occurrence,
        "triggers": ",".join(f'["{n}"]={{{a},{v}}}' for n, (a, v) in trig.items()),
        "inputs": ",".join(f'{{{f},"{k}",{lua_value(v)},"{t}",{n}}}'
                           for f, k, v, t, n in expand_inputs(inputs)),
    }
    with tempfile.NamedTemporaryFile("w", suffix=".lua", delete=False) as f:
        f.write(lua)
        lua_path = f.name
    cmd = ["mame", "apple2gs", "-rompath", ROMPATH, "-ramsize", ramsize,
           "-sl7", card,
           # A second disk goes on SCSI ID 5; MAME then names it hard1 and the
           # card's own disk (ID 6, the one it boots) hard2.
           *(["-hard1", os.path.abspath(image)] if not image2 else
             ["-sl7:scsi:scsibus:5", "harddisk", "-hard1", os.path.abspath(image2),
              "-hard2", os.path.abspath(image)] if card == "scsi" else
             # a CFFA's second drive is simply hard2
             ["-hard1", os.path.abspath(image), "-hard2", os.path.abspath(image2)]),
           "-video", "none", "-sound", "none", "-nothrottle",
           *(["-wavwrite", os.path.abspath(wav)] if wav else []),
           "-skip_gameinfo", "-noreadconfig", "-plugins",
           "-autoboot_script", lua_path, "-seconds_to_run", str(int(seconds) + 5)]
    if state_dir:
        cmd += ["-state_directory", os.path.abspath(state_dir)]
    if load_state:
        # the script loads it (MAME's -state skips the autoboot script); the
        # machine resumes at the state's time: let the frame limit end it
        cmd[cmd.index("-seconds_to_run") + 1] = "1000000"
    env = dict(os.environ, SDL_VIDEODRIVER="dummy", SDL_AUDIODRIVER="dummy")
    with tempfile.TemporaryDirectory() as cwd:   # keeps cfg/nvram out of the tree
        if zip:
            os.makedirs(os.path.join(cwd, "cfg"))
            with open(os.path.join(cwd, "cfg", "apple2gs.cfg"), "w") as f:
                f.write('<?xml version="1.0"?>\n<mameconfig version="10"><system name="apple2gs"><input>'
                        '<port tag=":a2_config" type="CONFIG" mask="7" defvalue="0" value="7" />'
                        '</input></system></mameconfig>\n')
        try:
            proc = subprocess.run(cmd, cwd=cwd, env=env, capture_output=True, text=True,
                                  timeout=timeout or seconds * 4 + 60)
            out = proc.stdout
        finally:
            os.unlink(lua_path)
    result = {"status": "no-output", "frame": None, "hit": None, "ready_frame": None,
              "dumps": {}, "text": [], "regs": {}}
    for line in out.splitlines():
        if line.startswith("MAMERUN-STATUS "):
            _, status, frame, hit = line.split(" ", 3)
            result.update(status=status, frame=int(frame), hit=None if hit == "nil" else hit)
        elif line.startswith("MAMERUN-TRIGGER "):
            _, name, n, f = line.split()
            result.setdefault("triggers", {}).setdefault(name, []).append(int(f))
            if name == "ready" and n == "1":
                result["ready_frame"] = int(f)
        elif line.startswith("MAMERUN-DUMP "):
            _, name, addr, data = line.split(" ", 3)
            result["dumps"][name] = {"addr": int(addr, 16), "hex": data}
        elif line.startswith("MAMERUN-TEXT "):
            result["text"].append(line.split("|", 1)[1])
        elif line.startswith("MAMERUN-REG "):
            _, reg, val = line.split(" ")
            result["regs"][reg] = int(val, 16)
        elif line.startswith("MAMERUN-BANK "):
            _, b, f = line.split()
            result["bank"], result["bank_frame"] = int(b), int(f)
        elif line.startswith("MAMERUN-TRACE "):
            _, name, f, v = line.split()
            result.setdefault("traces", {}).setdefault(name, []).append((int(f), int(v)))
        elif line.startswith("MAMERUN-WLOG "):
            result.setdefault("wlog", []).append(line.split()[1:])
        elif line.startswith("MAMERUN-TAP "):
            _, name, r, w = line.split()
            result.setdefault("taps", {})[name] = (int(r), int(w))
        elif line.startswith("MAMERUN-PROF "):
            _, addr, n = line.split()
            result.setdefault("profile", {})[addr] = int(n)
    # MAME's own messages (Lua errors among them), for diagnosis
    result["mame_errors"] = "\n".join(l for l in (out + proc.stderr).splitlines()
                                       if not l.startswith("MAMERUN-"))[-2000:]
    if result["status"] == "no-output":
        result["mame_output"] = out[-2000:]
    return result


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--image", required=True)
    ap.add_argument("--wait", action="append", default=[], metavar="ADDR=VALUE")
    ap.add_argument("--dump", action="append", default=[], metavar="NAME:ADDR:LEN")
    ap.add_argument("--seconds", type=float, default=30)
    ap.add_argument("--settle", type=int, default=0, help="frames to run after a hit")
    ap.add_argument("--profile", action="store_true",
                    help="sample PB:PC every frame; \"profile\" maps address -> samples")
    args = ap.parse_args()
    waits = [tuple(parse_int(x) for x in w.split("=")) for w in args.wait]
    dumps = []
    for d in args.dump:
        n, a, l = d.split(":")
        dumps.append((n, parse_int(a), parse_int(l)))
    json.dump(run(args.image, waits, dumps, args.seconds, args.settle, profile=args.profile),
              sys.stdout, indent=1)
    print()


if __name__ == "__main__":
    main()
