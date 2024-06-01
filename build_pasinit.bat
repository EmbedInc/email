@echo off
rem
rem   Set up for building a Pascal module.
rem
call build_vars

call src_get %srcdir% %libname%.ins.pas
call src_get %srcdir% %libname%2.ins.pas

call src_getbase
call src_getfrom sys sys_sys2.ins.pas
call src_getfrom stuff stuff.ins.pas

call src_builddate "%srcdir%"
