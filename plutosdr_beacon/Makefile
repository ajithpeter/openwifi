# Makefile for PlutoSDR WiFi Beacon Scanner

CC = gcc
CFLAGS = -Wall -O2 -std=gnu99
LDFLAGS = -liio -lm -lpthread

TARGET = beacon_scanner
SOURCES = beacon_scanner.c
OBJECTS = $(SOURCES:.c=.o)

.PHONY: all clean install

all: $(TARGET)

$(TARGET): $(OBJECTS)
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS)

%.o: %.c
	$(CC) $(CFLAGS) -c -o $@ $<

clean:
	rm -f $(TARGET) $(OBJECTS)

install: $(TARGET)
	install -D -m 0755 $(TARGET) /usr/local/bin/$(TARGET)

# Cross-compile for PlutoSDR (ARM)
CROSS_COMPILE ?= arm-linux-gnueabihf-

cross: CC=$(CROSS_COMPILE)gcc
cross: $(TARGET)

# Build with debug symbols
debug: CFLAGS += -g -DDEBUG
debug: $(TARGET)

help:
	@echo "PlutoSDR WiFi Beacon Scanner Build System"
	@echo ""
	@echo "Targets:"
	@echo "  all      - Build beacon_scanner (default)"
	@echo "  clean    - Remove build artifacts"
	@echo "  install  - Install to /usr/local/bin"
	@echo "  cross    - Cross-compile for ARM (PlutoSDR)"
	@echo "  debug    - Build with debug symbols"
	@echo ""
	@echo "Variables:"
	@echo "  CROSS_COMPILE - Cross-compiler prefix (default: arm-linux-gnueabihf-)"
	@echo ""
	@echo "Dependencies:"
	@echo "  - libiio-dev"
	@echo "  - libm (math library)"
	@echo "  - libpthread"
