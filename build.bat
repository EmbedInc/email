@echo off
rem
rem   Build everything from this source directory.  That includes the EMAIL
rem   library and various related executables.
rem
setlocal
set srclib=email
set libname=email
set buildname=

call godir (cog)source/%srclib%
call build_lib
call build_progs
