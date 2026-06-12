# Consolidated builds of the EDA tools rtl_buddy depends on (macOS + Linux).
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
#
# OS support: recipes branch on `uname -s` — Darwin keeps the original
# brew/clang recipe; Linux (validated on Rocky 8.10) builds with the
# default gcc toolchain (>= 12 required) and expects the prerequisites
# from install-prereqs-linux.sh under ~/.local plus rustup in ~/.cargo.

UNAME := $(shell uname -s)
ROOT  := $(CURDIR)
JOBS  ?= 8

ifeq ($(UNAME),Darwin)
SHELL := /bin/zsh
BREW  ?= $(shell brew --prefix)
else
SHELL := /bin/bash
endif

.PHONY: all yosys yosys-slang verilator surfer veridian sby openroad

all: yosys yosys-slang verilator surfer veridian sby openroad

ifeq ($(UNAME),Darwin)
yosys:
	echo "CONFIG := clang" > yosys/Makefile.conf
	PATH="$(BREW)/opt/bison/bin:$(BREW)/opt/flex/bin:$(BREW)/bin:$$PATH" \
		$(MAKE) -C yosys -j$(JOBS)
else
# yosys needs bison >= 3.6; Rocky 8 ships 3.0.4 — install-prereqs-linux.sh
# puts 3.8.2 in ~/.local/bin.
yosys:
	echo "CONFIG := gcc" > yosys/Makefile.conf
	PATH="$(HOME)/.local/bin:$$PATH" $(MAKE) -C yosys -j$(JOBS)
endif

# Needs the shared yosys built first (yosys-config on PATH).
ifeq ($(UNAME),Darwin)
yosys-slang:
	PATH="$(ROOT)/yosys:$(BREW)/bin:$$PATH" $(MAKE) -C yosys-slang -j$(JOBS)
else
# ~/.local/bin first: provides the `gmake` 4.4.x alias so the cmake-driven
# sub-build inherits the fifo jobserver (system gmake 4.2.1 chokes on it).
# CMAKE_CXX_FLAGS: in-tree yosys-config emits its baked-in PREFIX include
# dir (/usr/local/share/yosys/include) which needs root to exist; point the
# compiler at the in-tree yosys headers instead.
yosys-slang:
	PATH="$(ROOT)/yosys:$(HOME)/.local/bin:$$PATH" \
		$(MAKE) -C yosys-slang -j$(JOBS) \
		CMAKE_FLAGS="-DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_FLAGS=-I$(ROOT)/yosys"
endif

# env -u VERILATOR_ROOT: site environments (module load verilator) export a
# foreign VERILATOR_ROOT which configure would otherwise embed as DEFENV.
verilator:
	cd verilator && autoconf && env -u VERILATOR_ROOT \
		PATH="$(HOME)/.local/bin:$$PATH" ./configure --prefix=$(ROOT)/tools
	env -u VERILATOR_ROOT PATH="$(HOME)/.local/bin:$$PATH" \
		$(MAKE) -C verilator -j$(JOBS)
	env -u VERILATOR_ROOT $(MAKE) -C verilator install

surfer:
	cd surfer && PATH="$(HOME)/.cargo/bin:$$PATH" \
		cargo build --release --bin surfer --bin surver

veridian:
	cd veridian && PATH="$(HOME)/.cargo/bin:$$PATH" cargo build --release

# bin/sby is an exec wrapper (not a symlink) so sby resolves its real
# ../share/yosys/python3; the venv shebang keeps it off the system python.
#
# SBY_PYTHON: build sby's venv on the same uv-managed CPython that rtl_buddy
# (`rb`) runs on, instead of whatever python3 the ambient site module happens
# to provide. uv's standalone python carries an $ORIGIN/../lib rpath, so the
# resulting sby binary resolves libpython on its own — no python-module
# LD_LIBRARY_PATH entry in site-env.sh needed. Override e.g. SBY_PYTHON=3.12.
# (Requires uv on PATH at build time — already a runtime prerequisite of rb.)
SBY_PYTHON ?= 3.11
sby:
	test -d sby-venv || uv venv --python $(SBY_PYTHON) --seed sby-venv
	./sby-venv/bin/pip install --quiet click
	$(MAKE) -C sby install PREFIX=$(ROOT)/tools \
		YOSYS_RELEASE_VERSION="SBY $$(git -C sby describe --tags)"
ifeq ($(UNAME),Darwin)
	sed -i '' '1s|^#!/usr/bin/env python3$$|#!$(ROOT)/sby-venv/bin/python3|' tools/bin/sby
else
	sed -i '1s|^#!/usr/bin/env python3$$|#!$(ROOT)/sby-venv/bin/python3|' tools/bin/sby
endif

# OpenROAD's lemon/cudd/boost/or-tools deps are expected under ~/.local —
# install once with:
#   cd OpenROAD && ./etc/DependencyInstaller.sh -prefix $$HOME/.local
ifeq ($(UNAME),Darwin)
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
else
# Boost_DIR: the or-tools binary bundle drops Boost-1.87 cmake configs into
# ~/.local/lib64/cmake which shadow the 1.89 the installer builds; pin 1.89.
# Explicit -L linker dirs: some test binaries link bare -lyaml-cpp etc.
# without the ~/.local library paths (same failure class as macOS).
openroad:
	cmake -S OpenROAD -B OpenROAD/build \
		-DCMAKE_BUILD_TYPE=RELEASE \
		-DBUILD_GUI=OFF \
		-DCMAKE_DISABLE_FIND_PACKAGE_Qt5=ON \
		"-DCMAKE_PREFIX_PATH=$(HOME)/.local" \
		"-DBoost_DIR=$(HOME)/.local/lib/cmake/Boost-1.89.0" \
		"-DCMAKE_EXE_LINKER_FLAGS=-L$(HOME)/.local/lib -L$(HOME)/.local/lib64" \
		"-DCMAKE_SHARED_LINKER_FLAGS=-L$(HOME)/.local/lib -L$(HOME)/.local/lib64"
	$(MAKE) -C OpenROAD/build -j$(JOBS)
endif
