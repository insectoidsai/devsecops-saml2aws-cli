NAME=saml2aws
ARCH=$(shell uname -m)
OS?=$(shell uname)
ITERATION := 1

GOLANGCI_VERSION = 1.55.2
GORELEASER := $(shell command -v goreleaser 2> /dev/null)

SOURCE_FILES?=$$(go list ./... | grep -v /vendor/)
TEST_PATTERN?=.
TEST_OPTIONS?=

BIN_DIR := $(CURDIR)/bin

# Choose the right config file for the OS
ifeq ($(OS),Darwin)
   CONFIG_FILE?=$(CURDIR)/.goreleaser.macos-latest.yml
else ifeq ($(OS),Linux)
   CONFIG_FILE?=$(CURDIR)/.goreleaser.ubuntu-20.04.yml
else
   $(error Unsupported build OS: $(OS))
endif

ci: prepare test

mod:
	@go mod download
	@go mod tidy
.PHONY: mod

lint: 
	@echo "--- lint all the things"
	@docker run --rm -v $(shell pwd):/app -w /app golangci/golangci-lint:v$(GOLANGCI_VERSION) golangci-lint run -v
.PHONY: lint

lint-fix:
	@echo "--- lint all the things"
	@docker run --rm -v $(shell pwd):/app -w /app golangci/golangci-lint:v$(GOLANGCI_VERSION) golangci-lint run -v --fix
.PHONY: lint-fix

fmt: lint-fix

install:
	go install ./cmd/saml2aws
.PHONY: install

setup-path:
	@echo "--- setting up PATH for Go binaries"
	@if ! echo "$$PATH" | grep -q "$(shell go env GOPATH)/bin"; then \
		echo "export PATH=\$$PATH:$(shell go env GOPATH)/bin" >> ~/.zshrc; \
		echo "✓ Added Go bin directory to PATH in ~/.zshrc"; \
		echo "Please run: source ~/.zshrc to apply changes"; \
	else \
		echo "✓ Go bin directory already in PATH"; \
	fi
.PHONY: setup-path

verify-install:
	@echo "--- verifying saml2aws installation"
	@if ! command -v saml2aws >/dev/null 2>&1; then \
		echo "Error: saml2aws binary not found in PATH"; \
		echo "Please ensure GOPATH/bin is in your PATH"; \
		echo "Current GOPATH: $(shell go env GOPATH)"; \
		echo "Run 'make setup-path' to add Go bin directory to PATH"; \
		exit 1; \
	fi
	@saml2aws --version
	@echo "✓ saml2aws installed successfully"
.PHONY: verify-install

codesign:
	codesign --force --deep --sign - /Users/chris.powell/go/bin/saml2aws
.PHONY: codesign

logs:
	log show --predicate 'eventMessage contains "saml2aws"' --last 1h
.PHONY: logs

build:

ifndef GORELEASER
    $(error "goreleaser is not available please install and ensure it is on PATH")
endif
	goreleaser build --snapshot --clean --config $(CONFIG_FILE)
.PHONY: build

release-local: $(BIN_DIR)/goreleaser
	goreleaser release --snapshot --rm-dist --config $(CONFIG_FILE)
.PHONY: release-local

clean:
	@rm -fr ./build
.PHONY: clean

generate-mocks:
	mockery -dir pkg/prompter --all
	mockery -dir pkg/provider/okta -name U2FDevice
.PHONY: generate-mocks

test:
	@echo "--- test all the things"
	@go test -cover ./...
.PHONY: test

# It can be difficult to set up and test everything locally.  Using this target you can build and run a docker container
# that has all the tools you need to build and test saml2aws.  This is particularly useful on Mac as it allows the Linux
# and Docker builds to be tested.
# Note: By necessity, this target mounts the Docker socket into the container.  This is a security risk and should not
# be used on a production system.
# Note: Files written by the container will be owned by root.  This is a limitation of the Docker socket mount.
# You may need to run `docker run --privileged --rm tonistiigi/binfmt --install all` to enable the buildx plugin.
docker-build-environment:
	docker build --platform=amd64 -t saml2aws/build -f Dockerfile.build .
	docker run -it --rm -v /var/run/docker.sock:/var/run/docker.sock -e BUILDX_CONFIG=$(PWD)/.buildtemp -e GOPATH=$(PWD)/.buildtemp -e GOTMPDIR=$(PWD)/.buildtemp -e GOCACHE=$(PWD)/.buildtemp/.cache -e GOENV=$(PWD)/.buildtemp/env -v $(PWD):$(PWD) -w $(PWD) saml2aws/build:latest
.PHONY: docker-build-environment
