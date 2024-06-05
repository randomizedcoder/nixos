#
# Makefile
#
.PHONY: all

all: hp0 hp3

hp0:
	scp -C ./hp0/* hp0:
	scp -C ./modules/* hp0:
	scp -C ./scripts/* hp0:

hp3:
	scp -C ./hp3/* hp3:
	scp -C ./modules/* hp3:
	scp -C ./scripts/* hp3:

#
# end