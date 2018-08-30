@echo off
rem
rem   BUILD_PROGS [-dbg]
rem
rem   Build the executable programs from this library.
rem
setlocal
set srcdir=email
set buildname=

call src_go %srcdir%
call src_getfrom stuff stuff.ins.pas

call src_prog %srcdir% pop3 %1
call src_prog %srcdir% sendmail %1
call src_prog %srcdir% smtp %1
call src_prog %srcdir% test_email %1
