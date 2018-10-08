@echo off
rem
rem   Build the EMAIL library.
rem
set srcdir=email
set libname=email

call src_get "%srcdir%" %libname%.ins.pas
call src_get "%srcdir%" %libname%2.ins.pas
call src_getfrom sys sys.ins.pas
call src_getfrom util util.ins.pas
call src_getfrom string string.ins.pas
call src_getfrom file file.ins.pas
call src_getfrom stuff stuff.ins.pas

call src_insall %srcdir% %libname%
