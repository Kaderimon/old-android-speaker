#!/usr/bin/env bash
cd ~/w200-build/shairport/src/shairport-sync
grep -nE '^(CC|CXX|CCLD|LINK|CXXLINK|shairport_sync_LINK|LIBS|LDFLAGS) =' Makefile
grep -nE 'shairport_sync_LINK|CXXLINK' Makefile | head
grep -n 'shairport-sync\$(EXEEXT):' -A4 Makefile
ls *.cpp 2>/dev/null | head
