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
# verilator's src/Makefile_obj relies on .SECONDARY/intermediate semantics
# that Apple's GNU make 3.81 gets wrong: with VL_VLCOV=1 the only
# prerequisite (VlcMain.o) is implicit-rule-only, 3.81 treats the missing
# intermediate as "already up to date" and verilator_coverage_bin_dbg is
# silently never linked (surfaces later as installbin Error 71). Use brew's
# GNU make 4.x for the verilator tree (brew install make).
VMAKE ?= $(BREW)/opt/make/libexec/gnubin/make
else
SHELL := /bin/bash
VMAKE ?= $(MAKE)
endif

.PHONY: all yosys yosys-slang verilator surfer veridian sby openroad \
        openxc7 openxc7-boost openxc7-nextpnr openxc7-prjxray openxc7-chipdb

all: yosys yosys-slang verilator surfer veridian sby openroad

# `openxc7` (the open FPGA toolchain — nextpnr-xilinx + prjxray + a
# per-part nextpnr chipdb) is OPTIONAL and intentionally NOT part of `all`:
# `make` / `make all` never build it. Build it on demand with `make
# openxc7`. See the openXC7 section near the end of this file.

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
		$(VMAKE) -C verilator -j$(JOBS)
	env -u VERILATOR_ROOT $(VMAKE) -C verilator install

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

# ===========================================================================
# openXC7 — open FPGA toolchain (OPTIONAL; not built by `all`).
#
#   make openxc7                 # nextpnr-xilinx + prjxray + chipdb
#   make openxc7 CHIP_PART=xc7a100tcsg324-1   # a different 7-series part
#
# Components (submodules pinned at the openXC7 toolchain-installer's
# validated refs): nextpnr-xilinx, prjxray, prjxray-db. The in-repo `yosys`
# already provides `synth_xilinx`, so no second yosys is built. Outputs:
#   bin/{nextpnr-xilinx,bbasm,xc7frames2bit,fasm2frames}
#   tools/share/nextpnr/chipdb/<part>.bin        nextpnr chipdb (per part)
# env-macos.zsh / env-linux.sh export CHIPDB + PRJXRAY_DB_DIR so
# `rb fpga tool: openxc7` finds the chipdb and (for --bitstream) the db.
#
# nextpnr is built with BUILD_PYTHON=OFF: the chipdb generator (bbaexport)
# is standalone python and CLI place-and-route needs no bindings, so this
# sidesteps boost-python linkage entirely. The CMakeLists reads
# EIGEN3_INCLUDE_DIRS (plural) which modern Eigen3Config.cmake does not set,
# so the brew eigen3 include dir is passed explicitly (macOS). prjxray's
# vendored gflags/abseil predate cmake 4 -> CMAKE_POLICY_VERSION_MINIMUM.
# fasm2frames is a python util; bin/fasm2frames wraps it on a dedicated
# openxc7-venv carrying prjxray's requirements.
CHIP_PART ?= xc7a35tcsg324-1

# Eigen include dir, passed explicitly because nextpnr's CMakeLists reads the
# plural EIGEN3_INCLUDE_DIRS that modern Eigen3Config.cmake leaves unset.
# macOS: brew. Linux: this repo's ~/.local dep tree (OpenROAD's
# DependencyInstaller puts boost+eigen there); override for a system eigen,
# e.g. `make openxc7 EIGEN3_INC=/usr/include/eigen3`.
ifeq ($(UNAME),Darwin)
EIGEN3_INC ?= $(BREW)/include/eigen3
else
EIGEN3_INC ?= $(HOME)/.local/include/eigen3
# Private complete Boost for nextpnr (Linux). The ~/.local Boost from
# OpenROAD's DependencyInstaller is unusable for nextpnr: its headers (1.87)
# and libs (1.89) disagree so FindBoost rejects the whole package, and
# filesystem/program_options were never built. Build a self-contained static
# Boost here (openxc7-boost) with exactly the four libs nextpnr links.
BOOST_PREFIX ?= $(HOME)/.local/opt/boost-nextpnr
BOOST_VERSION ?= 1.87.0
BOOST_USCORE  := $(subst .,_,$(BOOST_VERSION))
endif

openxc7: openxc7-nextpnr openxc7-prjxray openxc7-chipdb
	@echo "openXC7 built. Source env-$(if $(filter Darwin,$(UNAME)),macos.zsh,linux.sh) for CHIPDB + PRJXRAY_DB_DIR."

openxc7-chipdb: openxc7-nextpnr
	mkdir -p tools/share/nextpnr/chipdb
	PYTHONPATH=$(ROOT)/nextpnr-xilinx/xilinx/python python3 \
		nextpnr-xilinx/xilinx/python/bbaexport.py \
		--device $(CHIP_PART) --bba tools/share/nextpnr/chipdb/$(CHIP_PART).bba
	nextpnr-xilinx/build/bbasm --le --files \
		tools/share/nextpnr/chipdb/$(CHIP_PART).bba \
		tools/share/nextpnr/chipdb/$(CHIP_PART).bin
	rm -f tools/share/nextpnr/chipdb/$(CHIP_PART).bba

ifeq ($(UNAME),Darwin)
openxc7-nextpnr:
	cd nextpnr-xilinx && git submodule update --init --recursive
	$(BREW)/bin/cmake -S nextpnr-xilinx -B nextpnr-xilinx/build \
		-DARCH=xilinx -DBUILD_GUI=OFF -DBUILD_PYTHON=OFF -DBUILD_TESTS=OFF \
		-DUSE_OPENMP=OFF -DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX=$(ROOT)/tools \
		-DEIGEN3_INCLUDE_DIRS=$(EIGEN3_INC)
	$(BREW)/bin/cmake --build nextpnr-xilinx/build -j$(JOBS)
	ln -sf ../nextpnr-xilinx/build/nextpnr-xilinx bin/nextpnr-xilinx
	ln -sf ../nextpnr-xilinx/build/bbasm bin/bbasm

openxc7-prjxray:
	cd prjxray && git submodule update --init --recursive
	$(BREW)/bin/cmake -S prjxray -B prjxray/build \
		-DCMAKE_BUILD_TYPE=Release -DPRJXRAY_BUILD_TESTING=OFF \
		-DCMAKE_POLICY_VERSION_MINIMUM=3.5
	$(BREW)/bin/cmake --build prjxray/build -j$(JOBS)
	test -d openxc7-venv || uv venv --python 3.11 --seed openxc7-venv
	# pip from inside prjxray/: requirements.txt has `-e third_party/fasm`
	# and `-e .` whose RELATIVE paths only resolve with CWD=prjxray.
	cd prjxray && $(ROOT)/openxc7-venv/bin/pip install --quiet -r requirements.txt
	ln -sf ../prjxray/build/tools/xc7frames2bit bin/xc7frames2bit
	printf '#!/bin/sh\nexec "%s/openxc7-venv/bin/python" "%s/prjxray/utils/fasm2frames.py" "$$@"\n' \
		"$(ROOT)" "$(ROOT)" > bin/fasm2frames
	chmod +x bin/fasm2frames
else
# Linux (validated end-to-end on AlmaLinux/Rocky 8.10, gcc 12.3.0: synth ->
# nextpnr PnR -> fasm2frames -> xc7frames2bit on the arty-a35 blinky).
# Uses this repo's ~/.local dep tree (eigen3, newer cmake/gmake on
# ~/.local/bin; system cmake on Rocky 8 is too old for prjxray's vendored
# gflags/abseil even with the policy floor) plus a PRIVATE Boost — see
# openxc7-boost below for why ~/.local Boost can't be used here.
#
# Two Linux-only fixups vs the macOS recipe:
#  * Boost: built static into BOOST_PREFIX and pinned with BOOST_ROOT +
#    Boost_NO_BOOST_CMAKE/NO_SYSTEM_PATHS so cmake ignores the shadowing
#    ~/.local 1.87 BoostConfig; Boost_USE_STATIC_LIBS keeps the binary free
#    of a runtime libboost_*.so search path. gcc-runtime libstdc++ resolves
#    via the baked LD_RUN_PATH from site-env.sh (issue #6), as for every
#    other tool here.
#  * Eigen: the ~/.local Eigen3Config sets EIGEN3_DEFINITIONS to
#    "EIGEN_MPL2_ONLY" with NO -D, so nextpnr's add_definitions() feeds the
#    compiler a bare token (a phantom "linker input file"). Rewrite that one
#    line to the well-formed flag; submodules are `ignore = dirty`, so the
#    edit is expected and idempotent (it no-ops once applied).
openxc7-nextpnr: openxc7-boost
	cd nextpnr-xilinx && git submodule update --init --recursive
	sed -i 's|add_definitions($${EIGEN3_DEFINITIONS})|add_definitions(-DEIGEN_MPL2_ONLY)|' \
		nextpnr-xilinx/CMakeLists.txt
	PATH="$(HOME)/.local/bin:$$PATH" cmake -S nextpnr-xilinx -B nextpnr-xilinx/build \
		-DARCH=xilinx -DBUILD_GUI=OFF -DBUILD_PYTHON=OFF -DBUILD_TESTS=OFF \
		-DUSE_OPENMP=ON -DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX=$(ROOT)/tools \
		-DCMAKE_PREFIX_PATH=$(HOME)/.local \
		-DEIGEN3_INCLUDE_DIRS=$(EIGEN3_INC) \
		-DBOOST_ROOT=$(BOOST_PREFIX) -DBoost_NO_BOOST_CMAKE=ON \
		-DBoost_NO_SYSTEM_PATHS=ON -DBoost_USE_STATIC_LIBS=ON
	PATH="$(HOME)/.local/bin:$$PATH" cmake --build nextpnr-xilinx/build -j$(JOBS)
	ln -sf ../nextpnr-xilinx/build/nextpnr-xilinx bin/nextpnr-xilinx
	ln -sf ../nextpnr-xilinx/build/bbasm bin/bbasm

# Private, self-contained static Boost for nextpnr (the four libs it links).
# Built once into BOOST_PREFIX and skipped if already present. Needed because
# the ~/.local Boost (OpenROAD's DependencyInstaller) is both incomplete
# (no filesystem/program_options) and internally inconsistent (1.87 headers,
# 1.89 libs), which makes FindBoost reject it outright.
openxc7-boost:
	test -f $(BOOST_PREFIX)/lib/libboost_filesystem.a || ( set -e; \
		mkdir -p $(HOME)/.local/src && cd $(HOME)/.local/src; \
		test -f boost_$(BOOST_USCORE).tar.bz2 || curl -fsSLO \
			https://archives.boost.io/release/$(BOOST_VERSION)/source/boost_$(BOOST_USCORE).tar.bz2; \
		rm -rf boost_$(BOOST_USCORE) && tar xf boost_$(BOOST_USCORE).tar.bz2; \
		cd boost_$(BOOST_USCORE); \
		./bootstrap.sh --prefix=$(BOOST_PREFIX) \
			--with-libraries=filesystem,thread,program_options,iostreams; \
		./b2 -j$(JOBS) --prefix=$(BOOST_PREFIX) link=static \
			threading=multi variant=release install )

openxc7-prjxray:
	cd prjxray && git submodule update --init --recursive
	# prjxray's OpenSafeFile flock()s every db file it reads. The prjxray-db
	# lives on the /auto/share NFS4 mount, where flock is unsupported and
	# raises EBADF -> fasm2frames dies (exit 1) before emitting any frames.
	# The db is read-only here, so drop the (LOCK_EX/LOCK_UN) flock calls;
	# idempotent (no-ops once applied). submodules are `ignore = dirty`.
	sed -i 's|fcntl.flock(self.fd.fileno(), fcntl.LOCK_EX)|pass  # rb_tools(nfs): flock unsupported on /auto/share NFS4|; s|fcntl.flock(self.fd.fileno(), fcntl.LOCK_UN)|pass  # rb_tools(nfs): flock unsupported on /auto/share NFS4|' \
		prjxray/prjxray/util.py
	PATH="$(HOME)/.local/bin:$$PATH" cmake -S prjxray -B prjxray/build \
		-DCMAKE_BUILD_TYPE=Release -DPRJXRAY_BUILD_TESTING=OFF \
		-DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
		-DCMAKE_PREFIX_PATH=$(HOME)/.local
	PATH="$(HOME)/.local/bin:$$PATH" cmake --build prjxray/build -j$(JOBS)
	test -d openxc7-venv || uv venv --python 3.11 --seed openxc7-venv
	# pip from inside prjxray/: requirements.txt has `-e third_party/fasm`
	# and `-e .` whose RELATIVE paths only resolve with CWD=prjxray.
	cd prjxray && $(ROOT)/openxc7-venv/bin/pip install --quiet -r requirements.txt
	ln -sf ../prjxray/build/tools/xc7frames2bit bin/xc7frames2bit
	printf '#!/bin/sh\nexec "%s/openxc7-venv/bin/python" "%s/prjxray/utils/fasm2frames.py" "$$@"\n' \
		"$(ROOT)" "$(ROOT)" > bin/fasm2frames
	chmod +x bin/fasm2frames
endif
