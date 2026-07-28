# loadcli — atalhos da raiz.
#
# O app macOS vive em mac/ e o site em website/. Este Makefile só delega, para
# que `make build` continue funcionando de onde você já tem o costume de rodar.

.PHONY: all bootstrap icon gen build run release sign-notarize clean site site-deploy site-images

all: build

## --- app macOS (delega para mac/) ---
bootstrap icon gen build run release sign-notarize:
	$(MAKE) -C mac $@

clean:
	$(MAKE) -C mac clean

## --- site (website/) ---

## Sobe o site localmente em http://localhost:4173
site:
	cd website && python3 -m http.server 4173

## Publica em www.loadcli.com (Hetzner, pela tailnet).
site-deploy:
	./website/tools/deploy.sh

## Regera as ilustrações com o Nano Banana Pro.
## Precisa de terminal interativo — o 1Password pede Touch ID.
site-images:
	cd website && op run --env-file=.env -- node tools/gen-images.mjs
