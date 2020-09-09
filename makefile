PLATFORM=$(shell uname -s | tr '[:upper:]' '[:lower:]')
VERSION := $(shell grep -Eo '(v[0-9]+[\.][0-9]+[\.][0-9]+([-a-zA-Z0-9]*)?)' version.go)

.PHONY: build docker release

build:
	go fmt ./...
	@mkdir -p ./bin/
	go build github.com/moov-io/ach
	go build -o bin/examples-http github.com/moov-io/ach/examples/http
	CGO_ENABLED=0 go build -o ./bin/server github.com/moov-io/ach/cmd/server

build-webui:
	cp $(shell go env GOROOT)/misc/wasm/wasm_exec.js ./cmd/webui/assets/wasm_exec.js
	GOOS=js GOARCH=wasm go build -o ./cmd/webui/assets/ach.wasm github.com/moov-io/ach/cmd/webui/ach/
	CGO_ENABLED=0 go build -o ./bin/webui ./cmd/webui

clean:
	@rm -rf ./bin/ ./tmp/ coverage.txt misspell* staticcheck lint-project.sh

.PHONY: check
check:
ifeq ($(OS),Windows_NT)
	@echo "Skipping checks on Windows, currently unsupported."
else
	@wget -O lint-project.sh https://raw.githubusercontent.com/moov-io/infra/master/go/lint-project.sh
	@chmod +x ./lint-project.sh
	GOOS=js GOARCH=wasm GOCYCLO_LIMIT=26 time ./lint-project.sh
endif

dist: clean build
ifeq ($(OS),Windows_NT)
	CGO_ENABLED=1 GOOS=windows go build -o bin/achcli.exe github.com/moov-io/ach/cmd/achcli
	CGO_ENABLED=1 GOOS=windows go build -o bin/ach.exe github.com/moov-io/ach/cmd/server
else
	CGO_ENABLED=0 GOOS=$(PLATFORM) go build -o bin/achcli-$(PLATFORM)-amd64 github.com/moov-io/ach/cmd/achcli
	CGO_ENABLED=0 GOOS=$(PLATFORM) go build -o bin/ach-$(PLATFORM)-amd64 github.com/moov-io/ach/cmd/server
endif

docker: clean
# ACH Docker image
	docker build --pull -t moov/ach:$(VERSION) -f Dockerfile .
	docker tag moov/ach:$(VERSION) moov/ach:latest
# ACH OpenShift Docker image
	docker build --pull -t quay.io/moov/ach:$(VERSION) -f Dockerfile-openshift --build-arg VERSION=$(VERSION) .
	docker tag quay.io/moov/ach:$(VERSION) quay.io/moov/ach:latest
# ACH Fuzzing Docker image
	docker build --pull -t moov/achfuzz:$(VERSION) . -f Dockerfile-fuzz
	docker tag moov/achfuzz:$(VERSION) moov/achfuzz:latest
# webui Docker image
	docker build --pull -t moov/ach-webui:$(VERSION) -f Dockerfile-webui .
	docker tag moov/ach-webui:$(VERSION) moov/ach-webui:latest

.PHONY: clean-integration test-integration

clean-integration:
	docker-compose kill
	docker-compose rm -v -f

test-integration: clean-integration
	docker-compose up -d
	sleep 5
	curl -v http://localhost:8080/files

release: docker AUTHORS
	go test ./...
	git tag -f $(VERSION)

release-push:
	docker push moov/ach:$(VERSION)
	docker push moov/ach:latest
	docker push moov/achfuzz:$(VERSION)

quay-push:
	docker push quay.io/moov/ach:$(VERSION)
	docker push quay.io/moov/ach:latest

.PHONY: cover-test cover-web
cover-test:
	go test -coverprofile=cover.out ./...
cover-web:
	go tool cover -html=cover.out

# From https://github.com/genuinetools/img
.PHONY: AUTHORS
AUTHORS:
	@$(file >$@,# This file lists all individuals having contributed content to the repository.)
	@$(file >>$@,# For how it is generated, see `make AUTHORS`.)
	@echo "$(shell git log --format='\n%aN <%aE>' | LC_ALL=C.UTF-8 sort -uf)" >> $@

.PHONY: fuzz
fuzz:
	docker run moov/achfuzz:latest

.PHONY: legal
legal:
ifeq ($(OS),Linux)
	@wget -q -nc https://github.com/elastic/go-licenser/releases/download/v0.3.0/go-licenser_0.3.0_Linux_x86_64.tar.gz
	@tar xf go-licenser_0.3.0_Linux_x86_64.tar.gz
else
	@wget -q -nc https://github.com/elastic/go-licenser/releases/download/v0.3.0/go-licenser_0.3.0_Darwin_x86_64.tar.gz
	@tar xf go-licenser_0.3.0_Darwin_x86_64.tar.gz
endif
	./go-licenser -license ASL2 -licensor 'The Moov Authors' -notice
	@git checkout README.md LICENSE
