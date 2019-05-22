@echo off
rem
rem   BUILD_LIB [-dbg]
rem
rem   Build the EMAIL library.
rem
setlocal
call build_pasinit

call src_insall %srcdir% %libname%

call src_pas %srcdir% %libname%_adr %1
call src_pas %srcdir% %libname%_adr_extract %1
call src_pas %srcdir% %libname%_adr_translate %1
call src_pas %srcdir% %libname%_comblock %1
call src_pas %srcdir% inet %1
call src_pas %srcdir% inet_sys %1
call src_pas %srcdir% smtp_client %1
call src_pas %srcdir% smtp_client_thread %1
call src_pas %srcdir% smtp_queue %1
call src_pas %srcdir% smtp_queue_read %1
call src_pas %srcdir% smtp_queue_write %1
call src_pas %srcdir% smtp_recv %1
call src_pas %srcdir% smtp_rinfo %1
call src_pas %srcdir% smtp_rqmeth %1
call src_pas %srcdir% smtp_send %1
call src_pas %srcdir% smtp_send_host %1
call src_pas %srcdir% smtp_send_message %1
call src_pas %srcdir% smtp_send_queue %1
call src_pas %srcdir% smtp_send_queue_mx %1
call src_pas %srcdir% smtp_subs %1

call src_lib %srcdir% %libname%
call src_msg %srcdir% %libname%
