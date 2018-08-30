@echo off
rem
rem   Build the EMAIL library.
rem
setlocal
set srclib=email
set libname=email

call src_get "%srclib%" %libname%.ins.pas
call src_get "%srclib%" %libname%2.ins.pas
call src_getfrom sys sys.ins.pas
call src_getfrom util util.ins.pas
call src_getfrom string string.ins.pas
call src_getfrom file file.ins.pas
call src_getfrom stuff stuff.ins.pas

call src_insall %srclib% %libname%

call src_pas %srclib% %libname%_adr %1
call src_pas %srclib% %libname%_adr_extract %1
call src_pas %srclib% %libname%_adr_translate %1
call src_pas %srclib% %libname%_comblock %1
call src_pas %srclib% inet %1
call src_pas %srclib% inet_sys %1
call src_pas %srclib% smtp_client %1
call src_pas %srclib% smtp_client_thread %1
call src_pas %srclib% smtp_queue %1
call src_pas %srclib% smtp_queue_read %1
call src_pas %srclib% smtp_queue_write %1
call src_pas %srclib% smtp_recv %1
call src_pas %srclib% smtp_rinfo %1
call src_pas %srclib% smtp_rqmeth %1
call src_pas %srclib% smtp_send %1
call src_pas %srclib% smtp_send_queue %1
call src_pas %srclib% smtp_subs %1

call src_lib %srclib% %libname%
call src_msg %srclib% %libname%
