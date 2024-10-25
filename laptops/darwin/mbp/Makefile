all:
	nix run nix-darwin -- switch --flake ~/.config/nix

go:
	darwin-rebuild switch --flake ~/.config/nix

rsync:
	rsync -avdz ./ 172.16.50.135:/Users/das/.config/nix/

scp:
	scp ./* 172.16.50.135:/Users/das/.config/nix/
