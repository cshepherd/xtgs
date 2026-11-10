# XT/GS: an 8088 PC environment for the Apple IIGS. Build driver.
#
#   make             build/xtgs.po: XTGS.SYSTEM + CORE + SVC, command P (probe)
#   make test-m0     boot it headless in MAME; judge the memory probe and the
#                    80x25 test frame (build/m0.png)
#   make test-cpu OP=xx   SingleStepTests vectors; make test-com   nasm .COM programs
#   make test-dos         independently sourced DOS utilities (third_party/)
#   make test-layout      the tests again with every bank and bank-$00 page moved
#   make test-gsos        launch XTGS.SYSTEM from GS/OS (needs a System 6 volume: SYSTEM6=)
#   make test-s16         the GS/OS application XTGS (src/gs): probe, .COM programs and
#                         sampled vectors under it, both layouts, and repeated launches;
#                         XTGS_FRONT=s16 does the same for any other target or tool
#   make finder           build/xtgs-finder.po: a System 6 volume that boots to the Finder,
#                         with the application and its icon in the folder XTGS, set to
#                         boot the FreeDOS disk (GW-BASIC on it) when opened
#   make run         boot the image in Ample's MAME with the claudebridge plugin
#   make run-dos     boot FreeDOS (Mode B) interactively in Ample's MAME
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
SVC_GEN   := src/svc/gen/font.s src/svc/gen/tables.s src/svc/gen/dostab.s src/svc/gen/t160.s
SVC_SRCS  := src/svc/svc.s src/svc/video.s src/svc/pcinit.s src/svc/bios.s src/svc/dos.s \
             src/svc/files.s src/svc/disk.s src/svc/keyboard.s src/svc/sound.s src/svc/capture.s $(SVC_GEN) $(INCLUDES)
CORE_GEN  := src/core/gen/optab.s src/core/gen/eatab.s src/core/gen/alu.s src/core/gen/flagtab.s
CORE_SRCS := src/core/core.s src/core/probe.s src/core/run.s src/core/jit.s src/core/jit2.s src/core/cpu.s src/core/flags.s \
             src/core/ops_mov.s src/core/ops_ctrl.s src/core/ops_grp.s src/core/ops_str.s \
             src/core/ops_misc.s src/core/harness.s $(CORE_GEN) $(INCLUDES)

.PHONY: all image finder test-m0 test-cpu test-com test-dos test-layout test-gsos test-s16 check-s16 bench boot-dos run run-dos dos-image clean lint

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
XTGS_VERSION := 0.1
ICONS        := icon/dos_32x32.qdicon.bin icon/dos_16x16.qdicon.bin
# The FreeDOS floppy of Mode B (its rule is with boot-dos) and the GW-BASIC
# that tools/build_freedos.py puts on it when it is there.
FDIMG        := third_party/freedos/fd/freedos.img
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
src/svc/gen/tables.s src/svc/gen/dostab.s src/svc/gen/t160.s: src/svc/gen/font.s

src/core/gen/optab.s: tools/gen_cpu.py
	$(PY) tools/gen_cpu.py
src/core/gen/eatab.s src/core/gen/alu.s src/core/gen/flagtab.s: src/core/gen/optab.s

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

# The same folder on a System 6 volume that boots to the Finder, as a user
# has it: the application with its icon, to be double-clicked, and the
# FreeDOS floppy as DISK (command D), so opening XTGS boots FreeDOS to A:\>
# with GWBASIC.EXE and the demo .BAS files on the disk (docs/mode-b.md).
# GW-BASIC is not fetched: without third_party/gwbasic/GWBASIC.EXE there is
# no FreeDOS disk with it, and this fails rather than leave it out.
finder: $(B)/xtgs-finder.po
$(B)/xtgs-finder.po: $(B)/xtgs16 $(B)/xtgs16.rfork $(B)/core $(B)/svc $(FDIMG) tools/gsos_image.sh tools/gsos_rfork.py
	@[ -f "$(SYSTEM6)" ] || { echo "finder: no System 6 volume at $(SYSTEM6) (set SYSTEM6=)"; exit 1; }
	@[ -f $(GWBASIC) ] || { echo "finder: no $(GWBASIC) for the FreeDOS disk"; exit 1; }
	@mkdir -p $(B)/finder
	cp $(B)/xtgs16 $(B)/finder/XTGS\#B30000
	cp $(B)/xtgs16.rfork $(B)/finder/XTGS\#B30000_ResourceFork.bin
	cp $(B)/core $(B)/finder/CORE\#060000
	cp $(B)/svc  $(B)/finder/SVC\#060000
	cp $(FDIMG)  $(B)/finder/DISK\#060000
	printf 'D\r' > $(B)/finder/XTGS.CMD\#040000
	tools/gsos_image.sh "$(SYSTEM6)" $@ - $(B)/finder/XTGS\#B30000 $(B)/finder/CORE\#060000 \
	    $(B)/finder/SVC\#060000 $(B)/finder/DISK\#060000 $(B)/finder/XTGS.CMD\#040000

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

# Mode B: boot a real FreeDOS kernel from a disk image (docs/mode-b.md).
# Builds the FreeDOS floppy (tools/build_freedos.py), then boots it headless.
$(FDIMG): tools/build_freedos.py tools/make_fat12.py $(wildcard $(GWBASIC))
	$(PY) tools/fetch_dos.py
	$(PY) tools/build_freedos.py
boot-dos: $(PO) $(FDIMG)
	VOLSIZE=4096KB $(PY) tools/boot_dos.py $(FDIMG) --seconds 120

# ---- interactive ------------------------------------------------------------

run: $(PO)
	tools/mame/run-mame.sh $<

# dos-image: build/boot/boot.po, a bootable 4 MB ProDOS 8 volume that boots
# XT/GS, loads the FreeDOS floppy (Mode B, command D) to the A:\> prompt, with
# GW-BASIC 3.23 and the demos on it. This is image-build only (no emulator), so
# it also serves a real IIGS - put the .po on a FloppyEmu/CFFA/SCSI volume.
# GW-BASIC 3.23 is included when third_party/gwbasic/GWBASIC.EXE is present;
# AUTOEXEC runs a demo, then at A:\> type GWBASIC for the live Ok interpreter.
dos-image: $(B)/boot/boot.po
$(B)/boot/boot.po: $(B)/xtgs $(B)/core $(B)/svc $(FDIMG) tools/make_image.sh
	@mkdir -p $(B)/boot
	cp $(B)/xtgs $(B)/boot/XTGS.SYSTEM\#FF2000
	cp $(B)/core $(B)/boot/CORE\#060000
	cp $(B)/svc  $(B)/boot/SVC\#060000
	cp $(FDIMG)  $(B)/boot/DISK\#060000
	printf 'D\r' > $(B)/boot/XTGS.CMD\#040000
	VOLSIZE=4096KB tools/make_image.sh $(B)/boot/boot.po \
	    $(B)/boot/XTGS.SYSTEM\#FF2000 $(B)/boot/CORE\#060000 $(B)/boot/SVC\#060000 \
	    $(B)/boot/DISK\#060000 $(B)/boot/XTGS.CMD\#040000

# Boot that image (Mode B) interactively in Ample's MAME. Kernel init is slow
# (~15K guest IPS): the A:\> prompt takes a while to appear. See docs/mode-b.md.
run-dos: $(B)/boot/boot.po
	tools/mame/run-mame.sh $(B)/boot/boot.po

lint: $(B)/xtgs $(B)/xtgs16 $(B)/core $(B)/svc

clean:
	rm -rf $(B) src/sys/error_output.txt src/gs/error_output.txt src/core/error_output.txt src/svc/error_output.txt
