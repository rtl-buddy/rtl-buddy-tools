# Consolidated macOS builds of the EDA tools rtl_buddy depends on.
# Each tool is a git submodule pinned at a validated ref, with three
# documented fork pins (per rtl_buddy docs — see README.md):
#   - yosys: rtl-buddy/yosys `rtl-buddy` branch (docs/concepts/synthesis.md) —
#     stock upstream rejects the unpacked structs / specific package imports
#     that rtl_buddy designs use.
#   - yosys-slang: rtl-buddy/yosys-slang `rtl-buddy` branch until
#     povik/yosys-slang#317 merges (docs/concepts/fpv.md).
#   - surfer: rtl-buddy/surfer `rtl-buddy` branch — mainline lacks the WCP
#     extensions (set_scope, query_variable_values, time_unit) that
#     `rb wave` / the hub bridge rely on (docs/install.md, docs/concepts/wave.md).
#
# Usage:
#   make all            # build everything (OpenROAD is hours)
#   make yosys verilator surfer ...   # individual tools
#
# Outputs land in each submodule's build dir; `bin/` holds relative
# symlinks to every binary — put bin/ on PATH (or symlink from
# /usr/local/bin).

SHELL := /bin/zsh
ROOT  := $(CURDIR)
BREW  ?= $(shell brew --prefix)
JOBS  ?= 8

.PHONY: all yosys yosys-slang verilator surfer veridian sby openroad

all: yosys yosys-slang verilator surfer veridian sby openroad

yosys:
	echo "CONFIG := clang" > yosys/Makefile.conf
	PATH="$(BREW)/opt/bison/bin:$(BREW)/opt/flex/bin:$(BREW)/bin:$$PATH" \
		$(MAKE) -C yosys -j$(JOBS)

# Needs the shared yosys built first (yosys-config on PATH).
yosys-slang:
	PATH="$(ROOT)/yosys:$(BREW)/bin:$$PATH" $(MAKE) -C yosys-slang -j$(JOBS)

verilator:
	cd verilator && autoconf && ./configure --prefix=$(ROOT)/tools
	$(MAKE) -C verilator -j$(JOBS)
	$(MAKE) -C verilator install

surfer:
	cd surfer && cargo build --release --bin surfer --bin surver

veridian:
	cd veridian && cargo build --release

sby:
	test -d sby-venv || python3 -m venv sby-venv
	./sby-venv/bin/pip install --quiet click
	$(MAKE) -C sby install PREFIX=$(ROOT)/tools \
		YOSYS_RELEASE_VERSION="SBY $$(git -C sby describe --tags)"
	sed -i '' '1s|^#!/usr/bin/env python3$$|#!$(ROOT)/sby-venv/bin/python3|' tools/bin/sby

# OpenROAD's lemon/cudd deps are expected under ~/.local — install once with:
#   cd OpenROAD && ./etc/DependencyInstaller.sh -prefix $$HOME/.local
# Every flag below is load-bearing on macOS; see AGENTS.md before changing.
openroad:
	$(BREW)/bin/cmake -S OpenROAD -B OpenROAD/build \
		-DCMAKE_BUILD_TYPE=RELEASE \
		-DBUILD_GUI=OFF \
		-DCMAKE_DISABLE_FIND_PACKAGE_Qt5=ON \
		-DCMAKE_C_COMPILER=$(BREW)/opt/llvm/bin/clang \
		-DCMAKE_CXX_COMPILER=$(BREW)/opt/llvm/bin/clang++ \
		"-DCMAKE_PREFIX_PATH=$(HOME)/.local;$(BREW);$(BREW)/opt/icu4c" \
		-DTCL_LIBRARY=$(BREW)/opt/tcl-tk@8/lib/libtcl8.6.dylib \
		-DTCL_HEADER=$(BREW)/opt/tcl-tk@8/include/tcl-tk/tcl.h \
		-DBISON_EXECUTABLE=$(BREW)/opt/bison/bin/bison \
		-DFLEX_EXECUTABLE=$(BREW)/opt/flex/bin/flex \
		-DFLEX_INCLUDE_DIR=$(BREW)/opt/flex/include \
		-DCMAKE_C_FLAGS=-DBOOST_STACKTRACE_GNU_SOURCE_NOT_REQUIRED \
		-DCMAKE_CXX_FLAGS=-DBOOST_STACKTRACE_GNU_SOURCE_NOT_REQUIRED \
		"-DCMAKE_EXE_LINKER_FLAGS=-L$(BREW)/lib -L$(HOME)/.local/lib -L$(BREW)/opt/icu4c/lib -L$(BREW)/opt/llvm/lib/c++ -lc++ -lc++abi" \
		"-DCMAKE_SHARED_LINKER_FLAGS=-L$(BREW)/lib -L$(HOME)/.local/lib -L$(BREW)/opt/icu4c/lib -L$(BREW)/opt/llvm/lib/c++"
	$(MAKE) -C OpenROAD/build -j$(JOBS)
