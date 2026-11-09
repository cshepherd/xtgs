# XT/GS: an 8088 PC environment for the Apple IIGS. Build driver.
#
#   make             build/xtgs.po: XTGS.SYSTEM + CORE + SVC, command P (probe)
#   make test-m0     boot it headless in MAME; judge the memory probe and the
#                    80x25 test frame (build/m0.png)
#   make test-cpu OP=xx   SingleStepTests vectors; make test-com   the .COM programs
#   make run         boot the image in Ample's MAME with the claudebridge plugin
#   make clean
#
# Toolchain: merlin32 (Brutal Deluxe, 1.1.10), cadius, Homebrew mame + Ample's
# ROM set (~/Library/Application Support/Ample/roms), python3. See CLAUDE.md
# for the Merlin32 rules and BOOTSTRAP.md for the plan.

B      := build
PY     := python3 -I

# merlin32 has no dependency output: every PUT file is listed here.
INCLUDES  := src/include/hw.s src/include/mailbox.s src/include/guest.s src/include/pc.s
SYS_SRCS  := src/sys/xtgs.s $(INCLUDES)
SVC_GEN   := src/svc/gen/font.s src/svc/gen/tables.s src/svc/gen/dostab.s
SVC_SRCS  := src/svc/svc.s src/svc/video.s src/svc/pcinit.s src/svc/bios.s src/svc/dos.s \
             src/svc/keyboard.s src/svc/capture.s $(SVC_GEN) $(INCLUDES)
CORE_GEN  := src/core/gen/optab.s src/core/gen/eatab.s src/core/gen/alu.s src/core/gen/flagtab.s
CORE_SRCS := src/core/core.s src/core/probe.s src/core/run.s src/core/cpu.s src/core/flags.s \
             src/core/ops_mov.s src/core/ops_ctrl.s src/core/ops_grp.s src/core/ops_str.s \
             src/core/ops_misc.s src/core/harness.s $(CORE_GEN) $(INCLUDES)

.PHONY: all image test-m0 test-cpu test-com bench run clean lint

all: $(B)/xtgs.po

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

$(B)/xtgs: $(SYS_SRCS)
	$(call merlin,src/sys,xtgs.s,xtgs,$@)

$(B)/svc: $(SVC_SRCS)
	$(call merlin,src/svc,svc.s,svc,$@)

$(B)/core: $(CORE_SRCS)
	$(call merlin,src/core,core.s,core,$@)

# ---- generated sources ------------------------------------------------------

# (make 3.81 has no grouped targets: the first output is the rule, the rest depend on it)
src/svc/gen/font.s: tools/gen_tables.py third_party/font8x8/font8x8_basic.h
	$(PY) tools/gen_tables.py
src/svc/gen/tables.s src/svc/gen/dostab.s: src/svc/gen/font.s

src/core/gen/optab.s: tools/gen_cpu.py
	$(PY) tools/gen_cpu.py
src/core/gen/eatab.s src/core/gen/alu.s src/core/gen/flagtab.s: src/core/gen/optab.s

# ---- images -----------------------------------------------------------------

$(B)/xtgs.po: $(B)/xtgs $(B)/core $(B)/svc tools/make_image.sh
	@mkdir -p $(B)/stage
	cp $(B)/xtgs $(B)/stage/XTGS.SYSTEM\#FF2000
	cp $(B)/core $(B)/stage/CORE\#060000
	cp $(B)/svc  $(B)/stage/SVC\#060000
	printf 'P\r' > $(B)/stage/XTGS.CMD\#040000
	tools/make_image.sh $@ $(B)/stage/XTGS.SYSTEM\#FF2000 $(B)/stage/CORE\#060000 \
	    $(B)/stage/SVC\#060000 $(B)/stage/XTGS.CMD\#040000

image: $(B)/xtgs.po

# ---- tests ------------------------------------------------------------------

test-m0: $(B)/xtgs.po
	$(PY) tools/judge_m0.py --image $< --listing $(B)/xtgs.lst --png $(B)/m0.png

# One opcode's SingleStepTests vectors (OP=00, or a group sub-opcode OP=80.3;
# COUNT limits how many). The image is built in build/vec/.
OP    ?= 00
COUNT ?=
test-cpu: $(B)/xtgs.po
	$(PY) tools/judge_cpu.py $(foreach o,$(OP),--op $(o)) $(if $(COUNT),--count $(COUNT),)

# The .COM programs in tests/com (nasm), each judged on its console output,
# exit code and screen (tests/com/NAME.json). COM=hello runs one.
COM ?=
test-com: $(B)/xtgs.po
	$(PY) tools/judge_com.py $(if $(COM),tests/com/$(COM).json,)

# Guest instructions a second, stock 2.8 MHz and 16 MHz ZipGS, from MAME's
# emulated frame count around each tests/bench/*.asm program (nasm).
bench: $(B)/xtgs.po
	$(PY) tools/bench.py

# ---- interactive ------------------------------------------------------------

run: $(B)/xtgs.po
	tools/mame/run-mame.sh $<

lint: $(B)/xtgs $(B)/core $(B)/svc

clean:
	rm -rf $(B) src/sys/error_output.txt src/core/error_output.txt src/svc/error_output.txt
