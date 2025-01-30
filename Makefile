#
# Makefile
#
.PHONY: all

all: hosts

hosts:
# [das@t:~/nixos]$ find ./ -name 'hosts.nix'
# ./hp/hp1/hosts.nix
# ./hp/hp0/hosts.nix
# ./hp/hp2/hosts.nix
# ./hp/hp5/hosts.nix
# ./modules/hosts.nix
# ./laptops/t/hosts.nix
	cp ./modules/hosts.nix ./hp/hp0/hosts.nix
	cp ./modules/hosts.nix ./hp/hp1/hosts.nix
	cp ./modules/hosts.nix ./hp/hp2/hosts.nix
	cp ./modules/hosts.nix ./hp/hp3/hosts.nix
	cp ./modules/hosts.nix ./hp/hp4/hosts.nix
	cp ./modules/hosts.nix ./hp/hp5/hosts.nix

	cp ./modules/hosts.nix ./laptops/t/hosts.nix
	cp ./modules/hosts.nix ./laptops/t14/hosts.nix

	cp ./modules/hosts.nix ./arm/pi5-1-os/hosts.nix
	cp ./modules/hosts.nix ./chromebox/chromebox3/hosts.nix

#all: hp0 hp1 hp2 hp3 hp4 hp5

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