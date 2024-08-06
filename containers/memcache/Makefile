all:
	nix-build memcache.nix
load:
	docker load < result
run:
	docker run -t memcached:latest
