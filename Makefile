#
# Makefile
#
.PHONY: all

all: hp0 hp1 hp2 hp3 hp4 hp5

hp0:
	scp -C ./modules/* hp0:
	scp -C ./scripts/* hp0:
	scp -C ./hp0/* hp0:

hp1:
	scp -C ./modules/* hp1:
	scp -C ./scripts/* hp1:
	scp -C ./hp1/* hp1:

hp2:
	scp -C ./modules/* hp2:
	scp -C ./scripts/* hp2:
	scp -C ./hp2/* hp2:

hp3:
	scp -C ./modules/* hp3:
	scp -C ./scripts/* hp3:
	scp -C ./hp3/* hp3:

hp4:
	scp -C ./modules/* hp4:
	scp -C ./scripts/* hp4:
	scp -C ./hp4/* hp4:

hp5:
	scp -C ./modules/* hp5:
	scp -C ./scripts/* hp5:
	scp -C ./hp5/* hp5:

#
# end