INIT_HZ ?= 5000
OSC_HZ ?= 25000000
RUN_PHY = $(MAKE) -C .. SUPERVISED=1 INIT_HZ=$(INIT_HZ)

.PHONY: test test-at-rate sim wave synth route
test:
	$(RUN_PHY) test OSC_HZ=19000000
	$(RUN_PHY) test OSC_HZ=31000000

test-at-rate:
	$(RUN_PHY) test OSC_HZ=$(OSC_HZ)

sim wave:
	$(RUN_PHY) $@ OSC_HZ=$(OSC_HZ)

synth route:
	$(RUN_PHY) $@
