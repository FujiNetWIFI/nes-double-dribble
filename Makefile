# Double Dribble (NES) -- FujiNet two-player netplay.
#
#   make                 the netplay ROM (build/dd_net.nes), SRV_HOST/SRV_PORT
#   make verify-org      split + rejoin of the original is byte-identical
#   make hook            HOOK build + patch audit + mailbox RMW audit
#   make run-hook        HOOK build in a MAME window: must feel like stock
#   make run-lag         SOLO build, controller 2 delayed 1 s: proof of capture
#   make det             determinism A/B: fuzz inputs, stall injection, the
#                        per-tick checksum traces must match
#   make rig             2 x fujinet-pc + relay + 2 x MAME, auto-matched,
#                        fuzz inputs, CRC cross-check
#   make m4              desync injection -> detect -> push -> recover
#   make peerleft        opponent walks out, both notice-screen branches
#   make play            two playable consoles side by side on this machine
#                        (tools/play_local.sh: fujinet-pcs, relay, 2 MAMEs)
#   make lobby           the session screens against parked idle players
#   make server          run the relay in the foreground

SRV_HOST ?= 127.0.0.1
SRV_PORT ?= 9700
ROM      := rom/double_dribble.nes
BUILD    := build
CA65     ?= ca65
LD65     ?= ld65
PY       ?= python3

SRCS := src/bank8.s src/defs.inc src/vars.inc src/dd.cfg src/ui/text.s \
        src/ui/font.inc src/netcode/mailbox.s src/netcode/session.s \
        src/netcode/lockstep.s src/netcode/resync.s src/netcode/image.inc \
        tools/patches.py tools/build_rom.py

.PHONY: all verify-org hook run-hook run-lag det rig m4 peerleft \
        server lobby play clean FORCE
all: $(BUILD)/dd_net.nes

$(BUILD):
	mkdir -p $@

# The server endpoint is baked in; regenerate only when it changes.
$(BUILD)/srv_endpoint.inc: FORCE | $(BUILD)
	@printf 'SRV_SPEC:       .byte "N:TCP://%s:%s/", 0\n' "$(SRV_HOST)" "$(SRV_PORT)" > $@.tmp
	@cmp -s $@.tmp $@ || mv $@.tmp $@
	@rm -f $@.tmp
# Rig endpoints. Console 1's baked-in one is a dead port on purpose: its
# fujinet-pc carries the Lobby's server-URL appkey, so connecting at all
# proves that handoff. Console 2 runs on the build-time fallback.
$(BUILD)/rig_endpoint.inc: | $(BUILD)
	@printf 'SRV_SPEC:       .byte "N:TCP://127.0.0.1:%s/", 0\n' "$(RIG_PORT)" > $@
$(BUILD)/rig_dead_endpoint.inc: | $(BUILD)
	@printf 'SRV_SPEC:       .byte "N:TCP://127.0.0.1:9/", 0\n' > $@
FORCE:

RIG_PORT ?= 9799

# build/<name>.nes from bank 8 assembled with that variant's flags
# $(call variant,name,flags,endpoint-dir)
define variant
$(BUILD)/$(1).bin: $(SRCS) $(BUILD)/srv_endpoint.inc $(BUILD)/rig_endpoint.inc $(BUILD)/rig_dead_endpoint.inc
	@mkdir -p $(BUILD)/$(1).d
	@cp $(3) $(BUILD)/$(1).d/srv_endpoint.inc
	$(CA65) -g -I src -I $(BUILD)/$(1).d $(2) -o $(BUILD)/$(1).o src/bank8.s
	$(LD65) -C src/dd.cfg -o $$@ -Ln $(BUILD)/$(1).lbl -m $(BUILD)/$(1).map $(BUILD)/$(1).o
$(BUILD)/$(1).nes: $(BUILD)/$(1).bin
	$(PY) tools/build_rom.py $(ROM) $$< $(BUILD)/$(1).lbl $$@
	$(PY) tools/check_patch.py $(ROM) $$@
	$(PY) tools/checkrom.py --claim --header-only $$@
	$(PY) tools/checkrom.py --raw 0x8000 $$<
endef

EP  := $(BUILD)/srv_endpoint.inc
REP := $(BUILD)/rig_endpoint.inc
DEP := $(BUILD)/rig_dead_endpoint.inc
$(eval $(call variant,dd_net,-D BUILD_KIND=1,$(EP)))
$(eval $(call variant,dd_hook,-D BUILD_KIND=0,$(EP)))
$(eval $(call variant,dd_lag,-D BUILD_KIND=2 -D SOLO_DELAY=60,$(EP)))
$(eval $(call variant,dd_detA,-D BUILD_KIND=2 -D FUZZ=1 -D TRACE=1,$(EP)))
$(eval $(call variant,dd_detB,-D BUILD_KIND=2 -D FUZZ=1 -D TRACE=1 -D STALL_N=9,$(EP)))
$(eval $(call variant,dd_rig1,-D BUILD_KIND=1 -D FUZZ=1 -D GUEST_SEED=17,$(DEP)))
$(eval $(call variant,dd_rig2,-D BUILD_KIND=1 -D FUZZ=1 -D AUTO_JOIN=1 -D GUEST_SEED=34,$(REP)))

verify-org: | $(BUILD)
	$(PY) tools/build_rom.py --org $(ROM) $(BUILD)/org.nes
	cmp $(ROM) $(BUILD)/org.nes && echo "verify-org: OK"

hook: $(BUILD)/dd_hook.nes

run-hook: $(BUILD)/dd_hook.nes
	emu/run.sh $<

run-lag: $(BUILD)/dd_lag.nes
	emu/run.sh $<

det: $(BUILD)/dd_detA.nes $(BUILD)/dd_detB.nes
	test/run_det.sh

rig: $(BUILD)/dd_rig1.nes $(BUILD)/dd_rig2.nes
	RIG_PORT=$(RIG_PORT) test/run_rig.sh

m4: $(BUILD)/dd_rig1.nes $(BUILD)/dd_rig2.nes
	RIG_PORT=$(RIG_PORT) RIG_MODE=m4 test/run_rig.sh

peerleft: $(BUILD)/dd_rig1.nes $(BUILD)/dd_rig2.nes
	RIG_PORT=$(RIG_PORT) RIG_MODE=peerleft LEAVE_MODE=clean test/run_rig.sh
	RIG_PORT=$(RIG_PORT) RIG_MODE=peerleft LEAVE_MODE=timeout test/run_rig.sh

play:
	tools/play_local.sh

lobby: $(BUILD)/dd_net.nes
	test/run_lobby.sh

server:
	$(PY) server/dd_relay_server.py --port $(SRV_PORT)

clean:
	rm -rf $(BUILD)
