PREFIX := /usr/local

OS := $(shell luajit -e 'print(require("ffi").os:lower())')
PROJECT := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
BUILD ?= $(PROJECT)/build

SRC := $(PROJECT)/src
OBJ := $(BUILD)/obj
BIN := $(BUILD)/bin
TMP := $(BUILD)/tmp

TEST_SRC := $(PROJECT)/tests
TEST_OBJ := $(BUILD)/test
TEST_BIN := $(BUILD)/test
VALGRIND := $(shell which valgrind)
ifneq (,$(VALGRIND))
	TEST_RUN:= $(VALGRIND) --error-exitcode=2 -q --leak-check=full
endif

OBJS_COMMON := $(OBJ)/heap.o
OBJS_LEVEE := \
	$(OBJS_COMMON) \
	$(OBJ)/task.o \
	$(OBJ)/liblevee.o \
	$(OBJ)/levee.o

TESTS := $(patsubst $(PROJECT)/tests/%.c,%,$(wildcard $(TEST_SRC)/*.c))

CFLAGS:= -Wall -Wextra -Werror -pedantic -Os -I$(PROJECT)/src
ifeq (osx,$(OS))
	LDFLAGS:= $(LDFLAGS) -pagezero_size 10000 -image_base 100000000
endif

LUAJIT_SRC := $(PROJECT)/dep/luajit
LUAJIT_DST := $(BUILD)/dep/luajit
LUAJIT_ARG := \
	XCFLAGS=-DLUAJIT_ENABLE_LUA52COMPAT \
	BUILDMODE=static \
	MACOSX_DEPLOYMENT_TARGET=10.8

LUAJIT := $(LUAJIT_DST)/bin/luajit

all: $(BIN)/levee

test: $(BIN)/levee
	@for name in $(TESTS); do $(MAKE) $$name || break; done
	$(PROJECT)/bin/lua.test $(PROJECT)/tests

%: $(TEST_BIN)/%
	$(TEST_RUN) $<

luajit: $(LUAJIT) $(LUAJIT_DST)/lib/libluajit-5.1.a

-include $(wildcard $(OBJ)/*.d)

$(BIN)/levee: $(LUAJIT_DST)/lib/libluajit-5.1.a $(OBJS_LEVEE)
	@mkdir -p $(BIN)
	$(CC) $(LDFLAGS) $^ -o $@

$(OBJ)/%.o: $(SRC)/%.c
	@mkdir -p $(OBJ)
	$(CC) $(CFLAGS) -MMD -MT $@ -MF $@.d -c $< -o $@

$(OBJ)/%.o: $(TMP)/%.c
	@mkdir -p $(OBJ)
	$(CC) $(CFLAGS) -MMD -MT $@ -MF $@.d -c $< -o $@

$(TMP)/liblevee.c: $(LUAJIT) $(PROJECT)/bin/bundle.lua $(shell find $(PROJECT)/levee -type f)
	@mkdir -p $(TMP)
	$(LUAJIT) $(PROJECT)/bin/bundle.lua $(PROJECT) levee > $@

$(LUAJIT_SRC)/Makefile:
	git submodule update --init $(LUAJIT_SRC)

$(LUAJIT) $(LUAJIT_DST)/lib/libluajit-5.1.a: $(LUAJIT_SRC)/Makefile
	@mkdir -p $(LUAJIT_DST)
	$(MAKE) -C $(LUAJIT_SRC) amalg $(LUAJIT_ARG) PREFIX=$(PREFIX)
	$(MAKE) -C $(LUAJIT_SRC) install $(LUAJIT_ARG) PREFIX=$(LUAJIT_DST)

$(TEST_OBJ)/%.o: $(TEST_SRC)/%.c
	@mkdir -p $(TEST_OBJ)
	$(CC) $(CFLAGS) -MMD -MT $@ -MF $@.d -c $< -o $@

$(TEST_BIN)/%: $(TEST_OBJ)/%.o $(OBJS_COMMON)
	@mkdir -p $(TEST_BIN)
	$(CC) $^ -o $@

clean:
	rm -rf $(BUILD)
	cd $(LUAJIT_SRC) && git clean -xdf

.PHONY: test clean
.SECONDARY:
