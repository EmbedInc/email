{   Subroutine SMTP_SEND_QUEUE (QNAME, RECV, QUEUE_IN, STAT)
*
*   Send all the mail in the queue with generic name QNAME.  The OPTIONS files
*   specify the details of how the mail is to be sent.  When RECV is TRUE,
*   an attempt should be made to receive any incoming mail before breaking
*   the remote connection, if this is possible.  QUEUE_IN is the queue where
*   all such incoming mail is to be placed.  The default input queue specified
*   in the OPTIONS files is used if QUEUE_IN is the empty string.
}
module smtp_send_queue;
define smtp_send_queue;
%include 'email2.ins.pas';

const
  max_msg_parms = 1;                   {max parameters we can pass to a message}

procedure smtp_send_queue (            {send all mail in a queue}
  in      qname: univ string_var_arg_t; {generic queue name}
  in      recv: boolean;               {try to receive incoming mail on TRUE}
  in      queue_in: univ string_var_arg_t; {name of input queue on RECV TRUE}
  out     stat: sys_err_t);            {returned completion status code}
  val_param;

var
  qconn: smtp_qconn_read_t;            {handle for reading queue}
  conn_stdout: file_conn_t;            {connection handle to standard output}
  conn_stderr: file_conn_t;            {connection handle to standard error}
  tnam: string_treename_t;             {scratch path name}
  lnam: string_leafname_t;             {scartch file leaf name}
  str: string_var8192_t;               {scratch string}
  cmd_len: string_index_t;             {STR length for command without args}
  to_list_p: string_list_p_t;          {pointer to list of target addresses}
  mconn_p: file_conn_p_t;              {pointer to mail message file connection}
  code_resp: smtp_code_resp_t;         {SMTP command response code}
  procid: sys_sys_proc_id_t;           {ID of process we launched}
  exstat: sys_sys_exstat_t;            {process exit status code}
  qrclose: smtp_qrclose_t;             {option flags for closing mail queue entry}
  cl_p: smtp_client_p_t;               {pointer to temporary SMTP client descriptor}
  turn: boolean;                       {try to reverse SMPT send/revc roles on TRUE}
  ok: boolean;                         {TRUE on positive response}
  qconn_open: boolean;                 {QCONN is open handle to queue}
  msg_parm:                            {parameter references for messages}
    array[1..max_msg_parms] of sys_parm_msg_t;
  stat2: sys_err_t;                    {to avoid corrupting STAT}

label
  send_quit, smtp_abort1, sendmail, loop_queue, sendmail_resend, next_queue,
  done_queue, sendmail_abort2, sendmail_abort1, abort1, leave;

begin
  str.max := sizeof(str.str);          {init local var strings}
  tnam.max := sizeof(tnam.str);
  lnam.max := sizeof(lnam.str);
  cl_p := nil;                         {init to no SMTP connection descriptor open}
  qconn_open := false;                 {init to mail queue not open}

  smtp_queue_read_open (               {open mail queue for read}
    qname,                             {generic queue name}
    util_top_mem_context,              {parent memory context to use}
    qconn,                             {returned connection handle for queue read}
    stat);
  if sys_error(stat) then goto leave;
  qconn_open := true;                  {remember that QCONN is now an open handle}

  if qconn.opts.sendmail then begin    {send mail to SENDMAIL program ?}
    goto sendmail;
    end;
  if string_equal(qconn.opts.remotesys, string_v('--MX--'(0))) then begin
    smtp_send_queue_mx (qconn, stat);  {send to hosts according to destination domains}
    goto leave;
    end;
{
************************************************************************
*
*   Send mail to a specific remote system via SMTP.
}
  if qconn.opts.port = 0 then begin    {default server port indicated ?}
    qconn.opts.port := smtp_port_k;    {use standard SMTP port}
    end;

  smtp_client_new (cl_p);              {create new descriptor for remote SMTP connection}
  string_copy (queue_in, cl_p^.inq);   {set input queue name}
  cl_p^.port := qconn.opts.port;       {set port to use on remote machine}
  file_inet_name_adr (                 {translate remote system name to node adr}
    qconn.opts.remotesys,              {remote system name}
    cl_p^.adr,                         {returned internet address}
    stat);
  if sys_error(stat) then begin
    smtp_client_log_stat_str (cl_p^, stat, 'Error trying to get IP address of remote machine');
    goto abort1;
    end;

  file_open_inetstr (                  {establish connection to remote server}
    cl_p^.adr,                         {address of remote machine}
    cl_p^.port,                        {port number on remote machine}
    cl_p^.conn,                        {returned handle to remote connection}
    stat);
  if sys_error(stat) then begin
    smtp_client_log_stat_str (cl_p^, stat, 'Error opening connection to remote server');
    goto abort1;
    end;
  cl_p^.open := true;

  smtp_resp_get (cl_p^.conn, code_resp, str, ok, stat); {get initial response code}
  if sys_error(stat) then begin
    if debug_smtp >= 1 then begin
      smtp_client_log_stat_str (cl_p^, stat, 'Error get initial response from SMTP server');
      end;
    goto smtp_abort1;
    end;
  if not ok then goto send_quit;       {send QUIT command and leave}

  turn := false;                       {disallow reversing roles to receive}
  smtp_send (                          {send queue data over established connection}
    cl_p^.conn,                        {handle to remote server connection}
    qconn,                             {handle to mail queue open for read}
    turn,                              {TRUE on try receive after done send}
    stat);
  smtp_queue_read_close (qconn, stat2); {close connection to output mail queue}
  qconn_open := false;                 {QCONN is no longer an open handle}

send_quit:
  inet_str_crlf_put ('QUIT', cl_p^.conn, stat); {tell remote server we are done}
  if sys_error(stat) then goto smtp_abort1;
  smtp_resp_get (cl_p^.conn, code_resp, str, ok, stat); {get response to QUIT command}
{
*   Jump here on error while connection to remote server is open.
}
smtp_abort1:
  file_close (cl_p^.conn);             {close internet stream connection}
  cl_p^.open := false;
  goto abort1;
{
************************************************************************
*
*   Send mail to local SENDMAIL program.
}
sendmail:
  file_open_stream_text (              {create connection to our standard output}
    sys_sys_iounit_stdout_k,           {system stream to connect to}
    [file_rw_write_k],                 {required read/write access}
    conn_stdout,                       {returned connection handle}
    stat);
  if sys_error(stat) then goto abort1;
  file_open_stream_text (              {create connection to our error output}
    sys_sys_iounit_errout_k,           {system stream to connect to}
    [file_rw_write_k],                 {required read/write access}
    conn_stderr,                       {returned connection handle}
    stat);
  if sys_error(stat) then goto sendmail_abort1;

loop_queue:                            {back here each new queue entry}
  smtp_queue_read_ent (                {open next queue entry for read}
    qconn,                             {handle to queue connection}
    to_list_p,                         {returned pointer to target addresses list}
    mconn_p,                           {returned pointer to message file connection}
    stat);
  if sys_stat_match (email_subsys_k, email_stat_queue_end_k, stat) {hit queue end ?}
    then goto done_queue;
  if sys_error(stat) then goto sendmail_abort2;
  qrclose := [];                       {init to not delete queue entry}

  sys_cognivis_dir ('com'(0), tnam);   {get name of Cognivision commands directory}
  string_vstring (lnam, 'sendmail'(0), -1); {make program leaf name}
  string_pathname_join (tnam, lnam, str); {make program pathname in STR}
  cmd_len := str.len;                  {save length right after program name}

  string_list_pos_abs (to_list_p^, 1); {position to first target address in list}
sendmail_resend:                       {back here to send to remaining addresses}
  str.len := cmd_len;                  {reset to just program name}
  while to_list_p^.str_p <> nil do begin {once for each address in list}
    if (to_list_p^.str_p^.len + 1) > (str.max - str.len) {no room for this address ?}
      then exit;                       {run SENDMAIL with the command line we have}
    string_append1 (str, ' ');         {add separator before this command line token}
    string_append (str, to_list_p^.str_p^); {add this address to command line}
    string_list_pos_rel (to_list_p^, 1); {advance to next address in list}
    end;                               {back to process this new target address}
{
*   We have a complete SENDMAIL command line in STR.
}
  if debug_smtp >= 5 then begin
    writeln ('Running: ', str.str:str.len);
    end;

  sys_run (                            {run SENDMAIL program}
    str,                               {command line with arguments}
    sys_procio_explicit_k,             {we will pass explicit stream handles}
    mconn_p^.sys,                      {system handle to standard input}
    conn_stdout.sys,                   {system handle to standard output}
    conn_stderr.sys,                   {system handle to standard error}
    procid,                            {returned ID of new process}
    stat);
  if sys_error(stat) then goto sendmail_abort2;
  discard( sys_proc_status (           {wait for SENDMAIL program to finish}
    procid,                            {ID of process}
    true,                              {wait for process to finish}
    exstat,                            {returned process exit status code}
    stat) );
  if debug_smtp >= 6 then begin
    writeln ('SENDMAIL completed, exit status was ', exstat);
    end;
  if sys_error(stat) then goto sendmail_abort2;
  if exstat <> sys_sys_exstat_ok_k then begin {SENDMAIL failed ?}
    sys_msg_parm_vstr (msg_parm[1], mconn_p^.tnam);
    sys_message_parms ('email', 'email_sendmail_err', msg_parm, 1);
    goto next_queue;                   {abort trying this queue entry}
    end;

  if to_list_p^.str_p <> nil then begin {still more target addresses to go ?}
    file_pos_start (mconn_p^, stat);   {re-position to start of mail message file}
    if sys_error(stat) then goto sendmail_abort2;
    goto sendmail_resend;              {back to do next chunk of target addresses}
    end;
  qrclose := [smtp_qrclose_del_k];     {queue entry sent, OK to delete it}

next_queue:                            {jump here to advance to next queue entry}
  smtp_queue_read_ent_close (          {close this mail queue entry}
    qconn,                             {handle to mail queue connection}
    qrclose,                           {set of close option flags}
    stat);
  if sys_error(stat) then goto sendmail_abort2;
  goto loop_queue;                     {back to process next queue entry}

done_queue:                            {all queue entries have been exhausted}
  file_close (conn_stderr);            {close connection to standard error}
  file_close (conn_stdout);            {close connection to standard output}
  goto leave;
{
*   Jump here on error while STDERR stream open.
}
sendmail_abort2:
  file_close (conn_stderr);
{
*   Jump here on error while STDOUT stream open.
}
sendmail_abort1:
  file_close (conn_stdout);
  goto abort1;
{
*   Jump here on error while mail queue could be open.
}
abort1:
{
*   Common exit point, whether on error or not.
}
leave:
  if qconn_open then begin
    smtp_queue_read_close (qconn, stat2); {close the mail queue}
    end;
  if cl_p <> nil then begin            {SMTP connection descriptor still open ?}
    smtp_client_close (cl_p);          {close it}
    end;
  end;
