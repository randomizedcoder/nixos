#
# Makefile
#
.PHONY: all

all: hp0 hp3

hp0:
	scp ./hp0/configuration.nix hp0:

hp3:
	scp ./hp3/configuration.nix hp3: