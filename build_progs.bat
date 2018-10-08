@echo off
rem
rem   BUILD_PROGS [-dbg]
rem
rem   Build the executable programs from this library.
rem
setlocal
call build_pasinit

call src_prog %srcdir% pop3 %1
call src_prog %srcdir% sendmail %1
call src_prog %srcdir% smtp %1
call src_prog %srcdir% test_email %1
