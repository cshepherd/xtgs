# XT/GS: an 8088 PC environment for the Apple IIGS. Build driver.
#
#   make             build/xtgs.po: XTGS.SYSTEM + CORE + SVC, command P (probe)
#   make test-m0     boot it headless in MAME; judge the memory probe and the
#                    80x25 test frame (build/m0.png)
#   make test-cpu OP=xx   SingleStepTests vectors; make test-com   nasm .COM programs
#   make test-dos         independently sourced DOS utilities (third_party/)
#   make test-share       FreeDOS with a ProDOS folder as drive C: (docs/share.md);
#                         BOOT=1: FreeDOS booted from that folder, no disk image
#   make test-clock       the IIGS clock as the guest's date and time (docs/clock.md);
#                         DOS=1: under FreeDOS, with the timer's lost ticks made up
#   make test-minix       Minix 1.5's demonstration diskette (third_party/minix)
#                         booted to its shell (docs/minix.md; ZIP=1 at 16 MHz)
#   make test-psg         the Tandy's sound chip in MAME's recording (docs/sound.md)
#   make test-layout      the tests again with every bank and bank-$00 page moved
#   make test-gsos        launch XTGS.SYSTEM from GS/OS (needs a System 6 volume: SYSTEM6=)
#   make test-s16         the GS/OS application XTGS (src/gs): probe, .COM programs and
#                         sampled vectors under it, both layouts, and repeated launches;
#                         XTGS_FRONT=s16 does the same for any other target or tool
#   make finder           build/xtgs-finder.po: a System 6 volume that boots to the Finder,
#                         with the application and its icon in the folder XTGS, set to
#                         boot FreeDOS from the folder SHARED beside it (GW-BASIC in
#                         it) when opened
#   make boot-dos         boot the FreeDOS floppy image headless (command D);
#   make boot-shared      the same from the folder SHARED (command S)
#   make disk-image IMG=path   build/disk/disk.po: XT/GS and a PC diskette image,
#                         command D; make run-disk boots it in Ample's MAME
#   make minix-image      the same with the Minix diskette; make run-minix boots it
#   make games-image      build/boot/games.po: the release volume as a Tandy 1000 on
#                         an 8 MB disk with the games' folders of release/shared
#                         (GAMES: lsl2, outrun, arkanoid, keen1, mech; make run-games boots it;
#                         lsl-image and run-lsl are the same)
#   make release          build/release/xtgs-VERSION.po: the volume to hand out, an
#                         800K disk that boots from ProDOS 8 into FreeDOS and has
#                         the GS/OS application and its icon as well;
#                         make test-release boots copies of it both ways
#   make run         boot the image in Ample's MAME with the claudebridge plugin
#   make run-dos     boot FreeDOS from the folder SHARED interactively in Ample's MAME
#   make clean
#
# Toolchain: merlin32 (Brutal Deluxe, 1.1.10), cadius, Homebrew mame + Ample's
# ROM set (~/Library/Application Support/Ample/roms), python3. See CLAUDE.md
# for the Merlin32 rules and BOOTSTRAP.md for the plan.

B      := build
PY     := python3 -I
# XTGS_LAYOUT=alt (environment or command line) runs any test with every
# region away from its assembled bank and every bank-$$00 area away from its
# assembled page (tools/layout.py); `make test-layout` runs the set.
# The image carries the request, so each layout has its own.
export XTGS_LAYOUT
# XTGS_FRONT=s16 runs any test from GS/OS with the native front end
# (src/gs/xtgs16.s) instead of XTGS.SYSTEM: tools/make_image.sh then builds
# a GS/OS volume from the System 6 volume SYSTEM6 (not part of this tree),
# and the harness finds the layout as the run goes. `make test-s16`.
export XTGS_FRONT
SYSTEM6 ?= ../ddiigs/assets/system6.hdv
export SYSTEM6
PO     := $(B)/xtgs$(if $(XTGS_FRONT),-$(XTGS_FRONT),)$(if $(XTGS_LAYOUT),-$(XTGS_LAYOUT),).po

# merlin32 has no dependency output: every PUT file is listed here.
INCLUDES  := src/include/hw.s src/include/layout.s src/include/mailbox.s src/include/guest.s src/include/pc.s
SYS_SRCS  := src/sys/xtgs.s $(INCLUDES)
SVC_GEN   := src/svc/gen/font.s src/svc/gen/tables.s src/svc/gen/dostab.s src/svc/gen/t160.s src/svc/gen/egatab.s src/svc/gen/tdytab.s
SVC_SRCS  := src/svc/svc.s src/svc/video.s src/svc/gtext.s src/svc/ega.s src/svc/tandy.s src/svc/pcinit.s src/svc/bios.s src/svc/dos.s \
             src/svc/files.s src/svc/disk.s src/svc/ports.s src/svc/redir.s src/svc/keyboard.s src/svc/sound.s src/svc/clock.s src/svc/joystick.s src/svc/serial.s src/svc/mouse.s src/svc/xms.s src/svc/control.s src/svc/capture.s $(SVC_GEN) $(INCLUDES)
CORE_GEN  := src/core/gen/optab.s src/core/gen/eatab.s src/core/gen/alu.s src/core/gen/flagtab.s src/core/gen/egaw.s
CORE_SRCS := src/core/core.s src/core/probe.s src/core/run.s src/core/jit.s src/core/jit2.s src/core/cpu.s src/core/flags.s \
             src/core/ops_mov.s src/core/ops_ctrl.s src/core/ops_grp.s src/core/ops_str.s \
             src/core/ops_misc.s src/core/ega.s src/core/harness.s $(CORE_GEN) $(INCLUDES)

.PHONY: all image finder test-m0 test-cpu test-com test-dos test-share test-clock test-minix test-psg test-layout test-gsos test-s16 check-s16 bench boot-dos boot-shared run run-dos dos-image tandy-image run-tandy release run-release test-release lsl-image run-lsl games-image run-games games-ega-image run-games-ega test-joy test-mouse test-xms test-control test-serial disk-image run-disk clean lint minix-image run-minix

all: $(PO)

# ---- merlin32 ---------------------------------------------------------------
#
# One rule shape, from fgx's hard-won version: clear the stale diagnostic
# files first (merlin32 writes error_output.txt only on failure, so the
# previous failure's copy survives a success), capture the exit status,
# ALWAYS move the listing into build/ (it is the diagnosis), print the log
# and fail if it failed, publish the binary only then, and lint the listing
# for M/X width leaks.
#
#   $(call merlin,DIR,SOURCE,OUTNAME,TARGET)
define merlin
	@mkdir -p $(B)
	@rm -f $(1)/error_output.txt $(1)/_FileInformation.txt $(1)/$(3)_Output.txt $(B)/$(3).err
	@rc=0; (cd $(1) && merlin32 -V $(2)) > $(B)/$(3).log 2>&1 || rc=$$?; \
	 [ -f $(1)/$(3)_Output.txt ] && mv $(1)/$(3)_Output.txt $(B)/$(3).lst; \
	 [ -f $(1)/error_output.txt ] && mv $(1)/error_output.txt $(B)/$(3).err; \
	 rm -f $(1)/_FileInformation.txt; \
	 if [ $$rc -ne 0 ]; then echo "merlin32 $(2) failed:"; grep -E "Error|error|=>" $(B)/$(3).log | head -20; exit $$rc; fi; \
	 mv $(1)/$(3) $(4)
	@$(PY) tools/check_mx.py $(B)/$(3).lst
	@$(PY) tools/check_long.py $(filter %.s,$^)
endef

# Each link is assembled for the banks and bank-$$00 pages in
# src/include/layout.s (*.bin); tools/gen_reloc.py then appends the list of
# the bytes that hold one, which the loader fixes once it knows where
# everything is (docs/relocation.md). XTGS.SYSTEM's list is its own front
# page's, for the '+' test layout.
$(B)/xtgs.bin: $(SYS_SRCS)
	$(call merlin,src/sys,xtgs.s,xtgs,$@)

# The GS/OS front end (docs/relocation.md, stage 3): a relocatable S16 load
# file, which Merlin32 writes itself.
GS_SRCS   := src/gs/xtgs16.s src/include/hw.s src/include/layout.s src/include/mailbox.s
$(B)/xtgs16: $(GS_SRCS)
	$(call merlin,src/gs,xtgs16.s,xtgs16,$@)

# Its resource fork: the Finder icon (icon/, QuickDraw II icon records) in an
# rBundle that names the file XTGS, and the version (tools/gsos_rfork.py).
# cadius adds NAME#TTAAAA_ResourceFork.bin as the fork of NAME#TTAAAA.
# ICON_REMAP: the records use $9 for the red of the D, which the Finder's
# 640 mode draws as aqua (a pixel is a dithered pair there); $4 is its red.
# Empty for the records exactly as they are.
XTGS_VERSION := 1.0
ICONS        := icon/dos_32x32.qdicon.bin icon/dos_16x16.qdicon.bin
# FreeDOS for Mode B (the rule is with boot-dos): the floppy image, the
# folder with the same files that DOS boots from as C: (made with the image),
# and the GW-BASIC that tools/build_freedos.py puts in both when it is there.
FDIMG        := third_party/freedos/fd/freedos.img
FDDIR        := third_party/freedos/fd/SHARED
GWBASIC      := third_party/gwbasic/GWBASIC.EXE
ICON_REMAP   := 9=4
$(B)/xtgs16.rfork: $(ICONS) tools/gsos_rfork.py Makefile
	@mkdir -p $(B)
	$(PY) tools/gsos_rfork.py program --name XTGS --version $(XTGS_VERSION) \
	    $(foreach r,$(ICON_REMAP),--remap $(r)) \
	    --large icon/dos_32x32.qdicon.bin --small icon/dos_16x16.qdicon.bin -o $@

RELOC_DEPS := tools/gen_reloc.py tools/layout.py tools/symbols.py
$(B)/xtgs: $(B)/xtgs.bin $(RELOC_DEPS)
	$(PY) tools/gen_reloc.py sys $< $@

$(B)/svc.bin: $(SVC_SRCS)
	$(call merlin,src/svc,svc.s,svc,$@)

$(B)/core.bin: $(CORE_SRCS)
	$(call merlin,src/core,core.s,core,$@)

$(B)/svc: $(B)/svc.bin $(RELOC_DEPS)
	$(PY) tools/gen_reloc.py svc $< $@

$(B)/core: $(B)/core.bin $(RELOC_DEPS)
	$(PY) tools/gen_reloc.py core $< $@

# ---- generated sources ------------------------------------------------------

# (make 3.81 has no grouped targets: the first output is the rule, the rest depend on it)
src/svc/gen/font.s: tools/gen_tables.py third_party/font8x8/font8x8_basic.h
	$(PY) tools/gen_tables.py
src/svc/gen/tables.s src/svc/gen/dostab.s src/svc/gen/t160.s src/svc/gen/egatab.s src/svc/gen/tdytab.s: src/svc/gen/font.s

src/core/gen/optab.s: tools/gen_cpu.py
	$(PY) tools/gen_cpu.py
src/core/gen/eatab.s src/core/gen/alu.s src/core/gen/flagtab.s src/core/gen/egaw.s: src/core/gen/optab.s

# ---- images -----------------------------------------------------------------

$(PO): $(B)/xtgs $(B)/xtgs16 $(B)/xtgs16.rfork $(B)/gsos/Start16 $(B)/core $(B)/svc tools/make_image.sh tools/gsos_image.sh
	@mkdir -p $(B)/stage
	cp $(B)/xtgs $(B)/stage/XTGS.SYSTEM\#FF2000
	cp $(B)/xtgs16 $(B)/stage/XTGS\#B30000
	cp $(B)/xtgs16.rfork $(B)/stage/XTGS\#B30000_ResourceFork.bin
	cp $(B)/core $(B)/stage/CORE\#060000
	cp $(B)/svc  $(B)/stage/SVC\#060000
	printf 'P\r' > $(B)/stage/XTGS.CMD\#040000
	tools/make_image.sh $@ $(B)/stage/XTGS.SYSTEM\#FF2000 $(B)/stage/CORE\#060000 \
	    $(B)/stage/SVC\#060000 $(B)/stage/XTGS.CMD\#040000

image: $(PO)

# The same folder on a System 6 volume (named XTGS) that boots to the
# Finder, as a user has it: the application with its icon, to be
# double-clicked, and FreeDOS in the folder SHARED beside it (command S),
# so opening XTGS boots FreeDOS to C:\> with GWBASIC.EXE and the demo .BAS
# files there (docs/share.md): no disk image to load, and what DOS writes
# are ProDOS files. GW-BASIC is not fetched: without
# third_party/gwbasic/GWBASIC.EXE this fails rather than leave it out.
finder: $(B)/xtgs-finder.po
$(B)/xtgs-finder.po: $(B)/xtgs16 $(B)/xtgs16.rfork $(B)/core $(B)/svc $(FDIMG) tools/gsos_image.sh tools/gsos_rfork.py
	@[ -f "$(SYSTEM6)" ] || { echo "finder: no System 6 volume at $(SYSTEM6) (set SYSTEM6=)"; exit 1; }
	@[ -f $(GWBASIC) ] || { echo "finder: no $(GWBASIC) for the FreeDOS folder"; exit 1; }
	@mkdir -p $(B)/finder
	cp $(B)/xtgs16 $(B)/finder/XTGS\#B30000
	cp $(B)/xtgs16.rfork $(B)/finder/XTGS\#B30000_ResourceFork.bin
	cp $(B)/core $(B)/finder/CORE\#060000
	cp $(B)/svc  $(B)/finder/SVC\#060000
	rm -f $(B)/finder/DISK\#060000
	printf 'S\rC=SHARED\r' > $(B)/finder/XTGS.CMD\#040000
	tools/gsos_image.sh "$(SYSTEM6)" $@ - $(B)/finder/XTGS\#B30000 $(B)/finder/CORE\#060000 \
	    $(B)/finder/SVC\#060000 $(B)/finder/XTGS.CMD\#040000 $(FDDIR)

# ---- tests ------------------------------------------------------------------

test-m0: $(PO)
	$(PY) tools/judge_m0.py --image $< --listing $(B)/xtgs.lst --png $(B)/m0.png

# One opcode's SingleStepTests vectors (OP=00, or a group sub-opcode OP=80.3;
# COUNT limits how many). The image is built in build/vec/.
OP    ?= 00
COUNT ?=
test-cpu: $(PO)
	$(PY) tools/judge_cpu.py $(foreach o,$(OP),--op $(o)) $(if $(COUNT),--count $(COUNT),)

# The .COM programs in tests/com (nasm), each judged on its console output,
# exit code and screen (tests/com/NAME.json). COM=hello runs one.
COM ?=
test-com: $(PO)
	$(PY) tools/judge_com.py $(if $(COM),tests/com/$(COM).json,)

# The independently sourced DOS programs (third_party/, fetched by
# tools/fetch_dos.py). tests/dos/NAME.json names the binary and its checks.
test-dos: $(PO)
	$(PY) tools/fetch_dos.py
	$(PY) tools/judge_com.py $(if $(DOS),tests/dos/$(DOS).json,$(wildcard tests/dos/*.json))

# Relocation (docs/relocation.md). test-layout: the probe, the .COM programs
# and a spread of CPU vectors with every region away from its assembled bank
# and every bank-$$00 area away from its assembled page.
# test-gsos: a System 6 volume (SYSTEM6, not part of this tree) whose startup
# program launches XTGS.SYSTEM; GS/OS decides the banks.
LAYOUT_OPS ?= 00 A5 C4 CF FF.2
test-layout:
	$(MAKE) XTGS_LAYOUT=alt test-m0 test-com
	@for o in $(LAYOUT_OPS); do $(MAKE) XTGS_LAYOUT=alt test-cpu OP=$$o COUNT=300 || exit 1; done

$(B)/gsos/Start: tests/gsos/start.s
	@mkdir -p $(B)/gsos
	$(call merlin,tests/gsos,start.s,gsstart,$@)
$(B)/gsos/Start16: tests/gsos/start16.s
	@mkdir -p $(B)/gsos
	$(call merlin,tests/gsos,start16.s,gsstart16,$@)

test-gsos: $(B)/xtgs.po $(B)/gsos/Start tools/gsos_image.sh
	@[ -f "$(SYSTEM6)" ] || { echo "test-gsos: no System 6 volume at $(SYSTEM6) (set SYSTEM6=)"; exit 1; }
	printf 'P\r' > $(B)/gsos/XTGS.CMD\#040000
	tools/gsos_image.sh "$(SYSTEM6)" $(B)/gsos/gs.hdv $(B)/gsos/Start $(B)/stage/XTGS.SYSTEM\#FF2000 \
	    $(B)/stage/CORE\#060000 $(B)/stage/SVC\#060000 $(B)/gsos/XTGS.CMD\#040000
	$(PY) tools/check_gsos.py --image $(B)/gsos/gs.hdv --listing $(B)/xtgs.lst --png $(B)/gsos.png

# test-s16: the same System 6 volume, started into the GS/OS application
# (XTGS_FRONT=s16: tools/make_image.sh builds the GS/OS volume, mamerun finds
# the front page by its signature). The probe, the .COM programs and sampled
# vectors where the Memory Manager puts things, the same again with '+' (the
# synthesized directories, no region or page where it was assembled), then
# tools/check_s16.py: launch, quit and launch again in one boot.
test-s16:
	@[ -f "$(SYSTEM6)" ] || { echo "test-s16: no System 6 volume at $(SYSTEM6) (set SYSTEM6=)"; exit 1; }
	$(MAKE) XTGS_FRONT=s16 XTGS_LAYOUT= test-m0 test-com
	$(MAKE) XTGS_FRONT=s16 XTGS_LAYOUT=alt test-m0 test-com
	@for o in $(LAYOUT_OPS); do $(MAKE) XTGS_FRONT=s16 XTGS_LAYOUT= test-cpu OP=$$o COUNT=300 || exit 1; done
	$(MAKE) XTGS_FRONT=s16 XTGS_LAYOUT= check-s16
check-s16: $(PO)
	$(PY) tools/check_s16.py --image $(PO)

# Guest instructions a second, stock 2.8 MHz and 16 MHz ZipGS, from MAME's
# emulated frame count around each tests/bench/*.asm program (nasm).
bench: $(PO)
	$(PY) tools/bench.py

# Mode B: boot a real FreeDOS kernel (docs/mode-b.md). Builds the FreeDOS
# floppy and the folder with the same files (tools/build_freedos.py), then
# boots headless: boot-dos the floppy image (command D), boot-shared the
# folder as drive C: with no image (command S, docs/share.md).
$(FDIMG): tools/build_freedos.py tools/make_fat12.py tests/demo/egademo.asm tests/demo/tdydemo.asm tests/demo/tdysnd.asm tests/demo/joytest.asm tests/demo/mousetst.asm tests/demo/xmstest.asm $(wildcard $(GWBASIC))
	$(PY) tools/fetch_dos.py
	$(PY) tools/build_freedos.py
boot-dos: $(PO) $(FDIMG)
	VOLSIZE=4096KB $(PY) tools/boot_dos.py $(FDIMG) --seconds 120
boot-shared: $(PO) $(FDIMG)
	VOLSIZE=4096KB $(PY) tools/boot_dos.py $(FDDIR) --seconds 120

# The shared drive (docs/share.md): FreeDOS with the folder SHARE of the
# volume as C:, a batch file that reads, writes, renames and deletes there,
# and the volume checked afterwards. LETTER=E for another drive, FULL=1 to
# name the folder by its full pathname. BOOT=1 has no floppy: FreeDOS and
# the batch file are in the folder SHARED and DOS boots from it (command S).
test-share: $(PO) $(FDIMG)
	$(PY) tools/share_test.py $(if $(BOOT),--boot) $(if $(LETTER),--letter $(LETTER)) $(if $(FULL),--full)

# The IIGS clock as the guest's (docs/clock.md): tests/com/clock.asm under
# the stub DOS, or with DOS=1 under FreeDOS booted from a folder (command S),
# its answers held against this machine's clock.
test-clock: $(PO) $(FDIMG)
	$(PY) tools/clock_test.py $(if $(DOS),--dos)

# Minix 1.5 from its demonstration diskette (docs/minix.md): the boot menu,
# the date, a login and a shell that lists directories, with the 8259, the
# diskette controller and the 6845 as Minix drives them itself. MINIX= is
# the 360K image (third_party/minix, with its licence); ZIP=1 a 16 MHz
# ZipGS (a stock IIGS takes seven and a half emulated minutes).
MINIX        := third_party/minix/demo_dsk.ibm
test-minix: $(PO)
	$(PY) tools/minix_test.py $(MINIX) $(if $(ZIP),--zip) $(if $(CGA),--cga)

# The Tandy 1000's sound chip as it sounds (docs/sound.md): fourteen sounds
# from tests/snd/psgwav.asm recorded by MAME, their frequencies, levels,
# noise and timing measured (work files in build/psg/; KEEP=1 keeps the
# recording). The registers behind them are make test-com's psg.
test-psg: $(PO)
	$(PY) tools/psg_test.py

# ---- interactive ------------------------------------------------------------

run: $(PO)
	tools/mame/run-mame.sh $<

# dos-image: build/boot/boot.po, a bootable 4 MB ProDOS 8 volume (named
# XTGS) that boots XT/GS and FreeDOS from its folder SHARED (Mode B, command
# S) to the C:\> prompt, with GW-BASIC 3.23 and the demos there: type GWBASIC
# for the Ok prompt. No disk image is loaded, and DOS's files are ProDOS
# files in that folder. This is image-build only (no emulator), so it also
# serves a real IIGS - put the .po on a FloppyEmu/CFFA/SCSI volume.
# GW-BASIC 3.23 is included when third_party/gwbasic/GWBASIC.EXE is present.
dos-image: $(B)/boot/boot.po
$(B)/boot/boot.po: $(B)/xtgs $(B)/core $(B)/svc $(FDIMG) tools/make_image.sh
	@mkdir -p $(B)/boot
	rm -f $(B)/boot/DISK\#060000
	cp $(B)/xtgs $(B)/boot/XTGS.SYSTEM\#FF2000
	cp $(B)/core $(B)/boot/CORE\#060000
	cp $(B)/svc  $(B)/boot/SVC\#060000
	printf 'S\rC=SHARED\r' > $(B)/boot/XTGS.CMD\#040000
	VOLSIZE=4096KB tools/make_image.sh $@ \
	    $(B)/boot/XTGS.SYSTEM\#FF2000 $(B)/boot/CORE\#060000 $(B)/boot/SVC\#060000 \
	    $(B)/boot/XTGS.CMD\#040000 $(FDDIR)

# Boot that image (Mode B) interactively in Ample's MAME. See docs/mode-b.md.
run-dos: $(B)/boot/boot.po
	tools/mame/run-mame.sh $(B)/boot/boot.po

# tandy-image: build/boot/tandy.po, the same volume as a Tandy 1000
# (XTGS.CMD's line VIDEO=TANDY; docs/tandy.md): TDYSND and TDYDEMO at the
# prompt. run-tandy boots it in Ample's MAME.
tandy-image: $(B)/boot/tandy.po
$(B)/boot/tandy.po: $(B)/xtgs $(B)/core $(B)/svc $(FDIMG) tools/make_image.sh
	@mkdir -p $(B)/tandy
	cp $(B)/xtgs $(B)/tandy/XTGS.SYSTEM\#FF2000
	cp $(B)/core $(B)/tandy/CORE\#060000
	cp $(B)/svc  $(B)/tandy/SVC\#060000
	printf 'S\rC=SHARED\rVIDEO=TANDY\r' > $(B)/tandy/XTGS.CMD\#040000
	@mkdir -p $(B)/boot
	VOLSIZE=4096KB tools/make_image.sh $@ \
	    $(B)/tandy/XTGS.SYSTEM\#FF2000 $(B)/tandy/CORE\#060000 $(B)/tandy/SVC\#060000 \
	    $(B)/tandy/XTGS.CMD\#040000 $(FDDIR)

run-tandy: $(B)/boot/tandy.po
	tools/mame/run-mame.sh $(B)/boot/tandy.po

# release: build/release/xtgs-VERSION.po, the volume to hand out
# (tools/release_image.py; an 800K disk unless VOLSIZE says otherwise). It
# boots from ProDOS 8 into XT/GS and FreeDOS (command S), and the GS/OS
# application with its Finder icon is beside XTGS.SYSTEM for a launch from
# the Finder; SHARED holds FreeDOS, GW-BASIC (required, as for finder) and
# the demos, with release/shared's AUTOEXEC.BAT. run-release boots it in
# Ample's MAME; test-release boots it headless both ways (tools/release_test.py).
# the folders of release/shared that are games: off the release, on games-image
GAMES := lsl2 outrun arkanoid keen1 mech
RELEASE := $(B)/release/xtgs-$(XTGS_VERSION).po
release: $(RELEASE)
$(RELEASE): $(B)/xtgs $(B)/xtgs16 $(B)/xtgs16.rfork $(B)/core $(B)/svc $(FDIMG) tools/release_image.py \
            tools/gsos_rfork.py res/PRODOS release/READ.ME $(shell find release/shared -type f $(foreach g,$(GAMES),-not -path 'release/shared/$(g)/*')) Makefile
	@[ -f $(GWBASIC) ] || { echo "release: no $(GWBASIC) for the FreeDOS folder"; exit 1; }
	@mkdir -p $(B)/release
	$(PY) tools/release_image.py $@ $(XTGS_VERSION) $(foreach g,$(GAMES),--without $(g))

# games-image: build/boot/games.po, the release volume as a Tandy 1000 (the
# line VIDEO=TANDY) on a larger disk (GAMESIZE), with the games' folders of
# release/shared on it (GAMES; C:\LSL2, a Sierra game whose RESOURCE.CFG
# names TANDY320.DRV and JR.DRV, C:\OUTRUN, C:\ARKANOID): whichever are
# there. They are not in the tree (.gitignore) and make release leaves them
# out. run-games boots it in Ample's MAME; lsl-image and run-lsl are the
# older names.
GAMESIZE ?= 8192KB
games-image lsl-image: $(B)/boot/games.po
$(B)/boot/games.po: $(B)/xtgs $(B)/xtgs16 $(B)/xtgs16.rfork $(B)/core $(B)/svc $(FDIMG) tools/release_image.py \
            tools/gsos_rfork.py res/PRODOS release/READ.ME $(shell find release/shared -type f) Makefile
	@mkdir -p $(B)/boot
	VOLSIZE=$(GAMESIZE) $(PY) tools/release_image.py $@ $(XTGS_VERSION) --cmd VIDEO=TANDY

run-games run-lsl: $(B)/boot/games.po
	tools/mame/run-mame.sh $(B)/boot/games.po

# games-ega-image: build/boot/gamesega.po, the same volume without the line
# VIDEO=TANDY: a PC with the EGA (mode 0Dh), for the games that want one
# (C:\KEEN1, C:\MECH; OutRun's and Arkanoid's EGA choices). run-games-ega boots it.
games-ega-image: $(B)/boot/gamesega.po
$(B)/boot/gamesega.po: $(B)/xtgs $(B)/xtgs16 $(B)/xtgs16.rfork $(B)/core $(B)/svc $(FDIMG) tools/release_image.py \
            tools/gsos_rfork.py res/PRODOS release/READ.ME $(shell find release/shared -type f) Makefile
	@mkdir -p $(B)/boot
	VOLSIZE=$(GAMESIZE) $(PY) tools/release_image.py $@ $(XTGS_VERSION)

run-games-ega: $(B)/boot/gamesega.po
	tools/mame/run-mame.sh $(B)/boot/gamesega.po

run-release: $(RELEASE)
	tools/mame/run-mame.sh $(RELEASE)

# test-joy: the IIGS's joystick as the PC's game port (docs/joystick.md):
# JOYTEST under FreeDOS, MAME's joystick moved by the harness (tools/joy_test.py).
test-joy: $(PO) $(FDIMG)
	$(PY) tools/joy_test.py

# test-mouse: the IIGS's mouse as the PC's, by INT 33h (docs/mouse.md):
# MOUSETST under FreeDOS, MAME's mouse moved by the harness (tools/mouse_test.py).
test-mouse: $(PO) $(FDIMG)
	$(PY) tools/mouse_test.py

# test-xms: the XMS driver (docs/xms.md): FreeDOS booted from the folder
# (command S), XMSTEST typed, its line judged; then with the line XMS=OFF,
# which must find no driver (tools/xms_test.py; work files in build/xms/).
# test-control: the desk accessory "XTGS Control" (docs/control.md): FreeDOS
# booted from the folder, Control-Apple-Esc, and in a boot each the
# accessory's soft reboot, its hard one, a state saved and restored, and its
# Quit (tools/control_test.py; build/control/).
test-control: $(PO) $(FDIMG)
	$(PY) tools/control_test.py soft
	$(PY) tools/control_test.py hard
	$(PY) tools/control_test.py state
	$(PY) tools/control_test.py drop
	$(PY) tools/control_test.py quit

test-xms: $(PO) $(FDIMG)
	$(PY) tools/xms_test.py
	$(PY) tools/xms_test.py XMS=OFF

# test-serial: the IIGS's serial ports as COM1 and COM2 (docs/serial.md):
# COMTEST under FreeDOS with MAME's two ports looped back (tools/com_test.py).
test-serial: $(PO) $(FDIMG)
	$(PY) tools/com_test.py

test-release: $(RELEASE)
	$(PY) tools/release_test.py $(RELEASE)
	@[ -f "$(SYSTEM6)" ] || { echo "test-release: no System 6 volume at $(SYSTEM6) (set SYSTEM6=): the GS/OS launch is not tested"; exit 1; }
	$(PY) tools/release_test.py $(RELEASE) --gsos

# disk-image IMG=path: build/disk/disk.po, a ProDOS 8 volume that boots
# XT/GS and then the PC diskette image IMG (Mode B, command D): its boot
# sector is run, whatever system it holds. run-disk boots it in Ample's MAME.
# (Always rebuilt: IMG is whatever was named this time.)
disk-image: $(B)/xtgs $(B)/core $(B)/svc
	@[ -f "$(IMG)" ] || { echo "disk-image: name a diskette image, IMG=path"; exit 1; }
	@mkdir -p $(B)/disk
	cp $(B)/xtgs $(B)/disk/XTGS.SYSTEM\#FF2000
	cp $(B)/core $(B)/disk/CORE\#060000
	cp $(B)/svc  $(B)/disk/SVC\#060000
	cp "$(IMG)"  $(B)/disk/DISK\#060000
	printf 'D\r' > $(B)/disk/XTGS.CMD\#040000
	VOLSIZE=4096KB tools/make_image.sh $(B)/disk/disk.po \
	    $(B)/disk/XTGS.SYSTEM\#FF2000 $(B)/disk/CORE\#060000 $(B)/disk/SVC\#060000 \
	    $(B)/disk/DISK\#060000 $(B)/disk/XTGS.CMD\#040000
run-disk: disk-image
	tools/mame/run-mame.sh $(B)/disk/disk.po

# Minix 1.5 that way (docs/minix.md): at its boot menu press "=", type the
# date it asks for, log in as root.
minix-image:
	$(MAKE) disk-image IMG=$(MINIX)
run-minix:
	$(MAKE) run-disk IMG=$(MINIX)

lint: $(B)/xtgs $(B)/xtgs16 $(B)/core $(B)/svc

clean:
	rm -rf $(B) src/sys/error_output.txt src/gs/error_output.txt src/core/error_output.txt src/svc/error_output.txt
