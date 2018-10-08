@echo off
rem
rem   Build everything from this source directory.  That includes the EMAIL
rem   library and various related executables.
rem
setlocal
call godir (cog)source/email
call build_lib
call build_progs
