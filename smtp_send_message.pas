{   Routines for sending single messages to single hosts.
}
module smtp_send_message;
define smtp_send_message;
%include 'email2.ins.pas';

const
  nshow_err_k = 200;                   {number of original message lines in bounce}
{
********************************************************************************
*
*   Subroutine SMTP_SEND_MESSAGE (HCONN, INIT, MCONN, ADRLIST, OPTS, STAT)
*
*   Send a single message to a host over a existing network connection.
*
*   HCONN is the existing connection to the host.
*
*   When INIT is TRUE, it must be assumed that nothing has been sent yet over
*   the connection to the host.  In that case, the initial SMTP handshake must
*   be performed before sending the particular message.  When INIT is FALSE,
*   only the incremental actions for sending the message need to be performed.
*
*   MCONN is the connection to the file containing the message to be sent.  The
*   current file position is irrelevant, and may be left anywhere.  MCONN can be
*   read and rewound, but is left open.
*
*   ADRLIST is the list of recipient addresses to send the message to at this
*   host.  The initial list position is irrelevant, and may be left anywhere.
*   The addresses to which the message was successfully sent are deleted from
*   ADRLIST.  ADRLIST is therefore returned the remaining addresses to send the
*   message to.
*
*   OPTS is the collection of options in effect for the queue that the message
*   is in.  Options used here are:
*
*     LOCALSYS
*     REMOTEPSWD
*     REMOTEUSER
*     SMTP_CMD
*     BOUNCEFROM
}
procedure smtp_send_message (          {send message over existing connection}
  in out  hconn: file_conn_t;          {existing connection to the SMTP host}
  in      init: boolean;               {do SMTP initial handshake}
  in out  mconn: file_conn_t;          {connection to message file, at any position}
  in out  adrlist: string_list_t;      {list of destination addresses for this message}
  in      opts: smtp_queue_options_t;  {options that apply to the message's queue}
  out     stat: sys_err_t);            {completion status code}
  val_param;

var
  code: smtp_code_resp_t;              {standard 3 digit SMTP command response code}
  serv_adr: sys_inet_adr_node_t;       {address of remote server node}
  serv_dot: string_var32_t;            {server address as dot notation string}
  serv_port: sys_inet_port_id_t;       {number of server port on remote node}
  cmd: string_var8192_t;               {SMTP command with parameters}
  info: string_var8192_t;              {SMTP command response text}
  errmsg: string_var256_t;             {error message string}
  adr_from: string_var256_t;           {mail originator address, lower case}
  pick: sys_int_machine_t;             {number of token picked from list}
  n_rcpt_ok: sys_int_machine_t;        {number of accepted recipients this msg}
  p: string_index_t;                   {parse index}
  tnam, tnam2: string_treename_t;      {scratch file treename}
  lnam: string_leafname_t;             {scratch file leafname}
  tk: string_var32_t;                  {scratch token}
  conne: file_conn_t;                  {connection to bounce message file}
  accadr: string_list_t;               {list of accepted addresses}
  eopen: boolean;                      {bounce error message file is open}
  ok: boolean;                         {TRUE if command response positive}
  err: boolean;                        {one or more errors in bounce file}
  acclist: boolean;                    {accepted addresses list is allocated}
  msg_sent: boolean;                   {TRUE if current message successfully sent}

label
  abort_msg, done_msg, leave;
{
********************************************************************************
*
*   Local subroutine SHOW_RESP
*
*   Print the error message string ERRMSG, followed by the response from the
*   remote system.  The three digit response code is in CODE, and the
*   informational text string is in INFO.  This routine is called on unexpected
*   response to help diagnose the problem.
}
procedure show_resp;

begin
  writeln (errmsg.str:errmsg.len);     {show caller's error message}
  writeln ('  ', code:3, ': ', info.str:info.len); {show code and info string}
  sys_stat_set (email_subsys_k, email_stat_smtp_err_k, stat); {general SMTP error}
  end;
{
********************************************************************************
*
*   Local subroutine WERR (S, STAT)
*
*   Write the string S as a new line to the bounce message error file.
}
procedure werr (                       {write line to bounce message error file}
  in      s: univ string_var_arg_t;    {the line to write}
  out     stat: sys_err_t);            {returned completion status}
  val_param; internal;

begin
  if not eopen then begin              {no bounce message file is open ?}
    sys_error_none (stat);             {silently ignore the request}
    return;
    end;

  file_write_text (s, conne, stat);
  end;
{
********************************************************************************
*
*   Local subroutine SERROR (STAT)
*
*   Add an error message to the bounce message file.  The error is assumed to be
*   a NACK response from the server.  CMD is the command sent to the server,
*   CODE is the status code returned by the server, and INFO is the error text
*   returned by the server.
*
*   The ERR flag will be set to indicate at least one error message is in the
*   bounce message file.
*
*   The bounce message file must be open on CONNE, although this is not checked.
}
procedure serror (                     {write whole message to bounce error file}
  out     stat: sys_err_t);            {returned completion status}
  val_param; internal;

var
  buf: string_var132_t;                {one line output buffer}

begin
  buf.max := size_char(buf.str);       {init local var string}

  if not eopen then begin              {no bounce message file is open ?}
    sys_error_none (stat);             {silently ignore the request}
    return;
    end;

  err := true;                         {indicate at least one message in bounce file}

  buf.len := 0;                        {write blank line}
  werr (buf, stat);
  if sys_error(stat) then return;

  werr (cmd, stat);                    {write the command sent to the server}
  if sys_error(stat) then return;

  string_vstring (buf, code, size_char(code));
  string_appends (buf, ': '(0));
  string_append (buf, info);           {server text response}
  werr (buf, stat);                    {write the line to the bounce file}
  end;
{
********************************************************************************
*
*   Local subroutine SEND_BOUNCE
*
*   Send an error bounce message to the sender.  Nothing is done if no bounce
*   message file is open (on CONNE).  The bounce message file will be closed and
*   deleted on success.
*
*   To avoid an infinite mail loop, the bounce message is not sent if the
*   message that caused the bounce was sent from the same address that the
*   bounce message would be sent from.
}
procedure send_bounce;                 {send error bounce message to sender}

var
  ii: sys_int_machine_t;               {scratch integer and loop counter}
  tf: boolean;                         {TRUE/FALSE status from subordinate process}
  exstat: sys_sys_exstat_t;            {exit status of subordinate process}
  buf: string_var8192_t;               {one line output buffer and command line}
  tk: string_var32_t;                  {scratch token}
  stat: sys_err_t;                     {completion status}

begin
  buf.max := size_char(buf.str);       {init local var strings}
  tk.max := size_char(tk.str);

  if not eopen then return;            {bounce message file not open ?}

  if string_equal (adr_from, opts.bouncefrom) {don't bounce to robot address}
    then return;
{
*   Complete the bounce message file and close it.
}
  buf.len := 0;                        {blank line after error messages}
  werr (buf, stat);
  if sys_error_check (stat, '', '', nil, 0) then return;

  string_vstring (buf,
    '----------------------------------------------------------------------'(0), -1);
  werr (buf, stat);
  if sys_error_check (stat, '', '', nil, 0) then return;

  buf.len := 0;                        {blank line before undelivered message}
  werr (buf, stat);
  if sys_error_check (stat, '', '', nil, 0) then return;

  file_pos_start (mconn, stat);        {re-position to start of file}
  if sys_error_check (stat, '', '', nil, 0) then return;
  for ii := 1 to nshow_err_k do begin  {once for each line to copy to bounce file}
    file_read_text (mconn, buf, stat); {read next message line from file}
    if file_eof(stat) then exit;       {end of file, stop copying ?}
    if sys_error_check (stat, '', '', nil, 0) then return;
    werr (buf, stat);                  {write this line to the bounce message file}
    if sys_error_check (stat, '', '', nil, 0) then return;
    end;                               {back to do next line}
  file_close (conne);                  {close the bounce message file}
  eopen := false;                      {indicate bounce file no longer open}
{
*   Run the SMTP program in a separate process to put the bounce message
*   into the default input queue.  The command line will be:
*
*   SMTP -ENQUEUE -MSG fnam -DEBUG dbglevel -TO from_adr
}
  string_copy (opts.smtp_cmd, buf);    {init command line with command name}
  string_appends (buf, ' -enqueue -msg '(0));
  string_append (buf, conne.tnam);     {bounce message file name}
  string_appends (buf, ' -debug '(0));
  string_f_int (tk, debug_smtp);
  string_append (buf, tk);             {debug level}
  string_appends (buf, ' -to '(0));
  string_append (buf, adr_from);       {address to send the bounce message to}

  if debug_smtp >= 5 then begin
    sys_thread_lock_enter_all;         {single threaded code}
    writeln ('Running: ', buf.str:buf.len);
    sys_thread_lock_leave_all;
    end;

  sys_run_wait_stdsame (buf, tf, exstat, stat); {run command to send bounce message}
  file_delete_name (conne.tnam, stat); {try to delete the bounce message file}
  end;
{
********************************************************************************
*
*   Local subroutine ERR_CLOSE
*
*   Close the bounce error message file and delete it, if it is open.
}
procedure err_close;                   {close and delete bounce message file}

var
  stat: sys_err_t;

begin
  if not eopen then return;            {no bounce message file is open ?}
  file_close (conne);                  {close the file}
  eopen := false;                      {indicate no bounce message file open}

  file_delete_name (conne.tnam, stat); {try to delete the file}
  end;
{
********************************************************************************
*
*   Local subroutine AUTHORIZE (STAT)
*
*   The remote server requires authentication of the client before accepting any
*   mail.  We will attempt authorization by using the AUTH command of ESMTP.
*   Note that EHLO should be used instead of HELO when ESMTP commands are used.
*   The AUTH command is described in RFC 2554.
*
*   The global variables CODE, INFO, and ERRMSG are trashed.
}
procedure authorize (                  {authorize ourselves to the remote server}
  out     stat: sys_err_t);            {completion status}
  val_param; internal;

var
  cmd: string_var256_t;                {SMTP command buffer}
  prompt: string_var80_t;              {challenge prompt from server, clear text}
  pick: sys_int_machine_t;             {number of keyword picked from list}
  ok: boolean;                         {TRUE if command response positive}

label
  loop_chal, err;

begin
  cmd.max := size_char(cmd.str);       {init local var strings}
  prompt.max := size_char(prompt.str);
{
*   Send the EHLO command.
}
  string_vstring (cmd, 'EHLO '(0), -1); {build command}
  string_append (cmd, opts.localsys);
  inet_vstr_crlf_put (cmd, hconn, stat); {send command}
  if sys_error(stat) then return;

  smtp_resp_get (hconn, code, info, ok, stat); {get command response}
  if not ok then begin
    string_vstring (errmsg, 'EHLO error:'(0), -1);
    show_resp;
    goto err;
    end;
{
*   The EHLO command has been sent and a successful response received.  The EHLO
*   command response reports the various ESMTP extensions that this server
*   supports.  A full featured SMTP client would examine this list to see which
*   authorization types the server supports.  However, we only know how to use
*   the AUTH LOGIN command, so we send it and if the server doesn't support it,
*   it will fail.  Oh well.
}
  string_vstring (cmd, 'AUTH LOGIN'(0), -1);
  inet_vstr_crlf_put (cmd, hconn, stat); {send AUTH LOGIN command}
  if sys_error(stat) then return;

loop_chal:                             {back here for each new challenge}
  smtp_resp_get (hconn, code, info, ok, stat); {get command response}
  if not ok then begin
    string_vstring (errmsg, 'AUTH LOGIN error:'(0), -1);
    show_resp;
    goto err;
    end;
  if code[1] = '2' then return;        {AUTH command completed successfully ?}
{
*   Assume the response is a challenge to us.  Such challenges are sent BASE64
*   encoded.
}
  string_f_base64 (info, prompt);      {make clear text challenge prompt}
  string_unpad (prompt);               {delete any trailing spaces}
  string_upcase (prompt);              {make case-insensitive for keyword matching}
  string_tkpick80 (prompt,             {pick challenge prompt from list}
    'USERNAME: PASSWORD:',
    pick);
  case pick of                         {which challenge is it ?}
{
*   USERNAME:
}
1: begin
  string_t_base64 (opts.remoteuser, cmd); {make encoded challenge response}
  inet_vstr_crlf_put (cmd, hconn, stat); {send it}
  end;
{
*   PASSWORD:
}
2: begin
  string_t_base64 (opts.remotepswd, cmd); {make encoded challenge response}
  inet_vstr_crlf_put (cmd, hconn, stat); {send it}
  end;
{
*   Unexpected challenge prompt received.
}
otherwise
    string_vstring (errmsg, 'Unexpected challenge prompt received:'(0), -1);
    show_resp;
    goto err;
    end;

  goto loop_chal;                      {back to get next challenge prompt}

err:                                   {jump here to return with generic error}
  sys_stat_set (email_subsys_k, email_stat_smtp_err_k, stat); {general SMTP error}
  end;
{
********************************************************************************
*
*   Start of main routine.
}
begin
  cmd.max := sizeof(cmd.str);          {init local var strings}
  info.max := sizeof(info.str);
  errmsg.max := sizeof(errmsg.str);
  adr_from.max := sizeof(adr_from.str);
  tnam.max := sizeof(tnam.str);
  tnam2.max := sizeof(tnam2.str);
  lnam.max := sizeof(lnam.str);
  serv_dot.max := sizeof(serv_dot.str);
  tk.max := sizeof(tk.str);

  msg_sent := false;                   {init to this message not sent}
  eopen := false;                      {init to bounce message error file not open}
  err := false;                        {init to no errors in bounce file}
  acclist := false;                    {init to accepted addresses list not created}
{
*   Set SERV_DOT to the dot-notation address of the server we are connected to.
}
  file_inetstr_info_remote (hconn, serv_adr, serv_port, stat); {get server info}
  if sys_error(stat) then goto leave;
  string_f_inetadr (serv_dot, serv_adr); {make dot-notation server address}
{
*   Initialize the SMTP connection if INIT is TRUE.  This means sending the HELO
*   or EHLO commands.  The latter includes additional interactions for
*   authenticating.  The EHLO handshake is encapsulated in the separate
*   subroutine AUTHORIZE.
}
  if init then begin                   {need to initialize the SMTP conversation ?}
    if (opts.remoteuser.len <= 0) and (opts.remotepswd.len <= 0) {no user name or password ?}
      then begin                       {no authorization required, use normal HELO}
        string_vstring (cmd, 'HELO '(0), -1); {build command}
        string_append (cmd, opts.localsys);
        inet_vstr_crlf_put (cmd, hconn, stat); {send command}
        if sys_error(stat) then goto leave;
        smtp_resp_get (hconn, code, info, ok, stat); {get command response}
        if not ok then begin
          string_vstring (errmsg, 'HELO error:'(0), -1);
          show_resp;
          goto leave;
          end;
        end
      else begin                       {explicit authorization is required}
        authorize (stat);              {perform the authorization}
        if sys_error(stat) then goto leave;
        end
      ;
    end;                               {end of SMTP conversation initialization}
{
*   Read thru the header lines to set ADR_FROM to the From: address.
}
  adr_from.len := 0;                   {init to no FROM address found}
  file_pos_start (mconn, stat);        {go to start of message file}
  if sys_error_check (stat, '', '', nil, 0) then return;

  while true do begin                  {scan the header lines}
    file_read_text (mconn, info, stat); {read next mail message line}
    if file_eof(stat) then exit;       {hit end of mail message file ?}
    if sys_error(stat) then goto done_msg;
    string_unpad (info);               {truncate trailing spaces from received line}
    if info.len <= 0 then exit;        {blank line indicating end of header ?}
    if info.str[1] = ' ' then next;    {continuation line, not a new command ?}
    p := 1;                            {init mail line parse index}
    string_token (info, p, cmd, stat); {extract header keyword, if any}
    if string_eos(stat) then exit;     {hit end of mail message header ?}
    if sys_error(stat) then next;      {ignore on err, like open quote, etc.}
    if cmd.len <= 1 then next;         {too short to be valid header command ?}
    if cmd.str[cmd.len] <> ':' then next; {no colon, not a valid header command ?}
    cmd.len := cmd.len - 1;            {truncate the ":" after keyword name}
    string_upcase (cmd);               {make upper case for keyword matching}
    string_tkpick80 (cmd,              {pick keyword name from list}
      'FROM',
      pick);
    case pick of                       {which keyword is it ?}
      {
      *   Mail header keyword FROM.
      }
1:    begin
        string_substr (info, p, info.len, cmd); {extract string after FROM: keyword}
        email_adr_extract (cmd, adr_from, errmsg); {get raw address in ADR_FROM}
        string_downcase (adr_from);
        end;

      end;                             {end of special handling keyword cases}
    end;                               {back to read the next header line}

  if adr_from.len = 0 then begin       {no From: address available ?}
    goto leave;                        {we don't send messages without From: address}
    end;
{
*   Open and initialize the bounce mail message file.
}
  string_pathname_split (mconn.tnam, tnam, lnam); {get message file dir and name}
  lnam.str[1] := 'e';                  {change to error file leafname}
  string_pathname_join (tnam, lnam, tnam2); {make error file full treename}
  file_open_write_text (tnam2, '', conne, stat); {open error output file}
  if sys_error(stat) then goto leave;
  eopen := true;                       {indicate bounce message file is now open}

  string_vstring (info, 'To: '(0), -1);
  string_append (info, adr_from);
  werr (info, stat);
  if sys_error(stat) then goto leave;

  string_vstring (info, 'From: '(0), -1);
  string_append (info, opts.bouncefrom);
  werr (info, stat);
  if sys_error(stat) then goto leave;

  string_vstring (info, 'Subject: Mail delivery error'(0), -1);
  werr (info, stat);
  if sys_error(stat) then goto leave;

  info.len := 0;                       {write blank line to end email header}
  werr (info, stat);
  if sys_error(stat) then goto leave;

  string_vstring (info,
    'A mail message from you was not delivered to all its recipients.'(0), -1);
  werr (info, stat);
  if sys_error(stat) then goto leave;

  string_vstring (info,
    'Errors were received from the SMTP server on port '(0), -1);
  string_f_int (tk, serv_port);
  string_append (info, tk);
  string_appends (info, ' of'(0));
  werr (info, stat);
  if sys_error(stat) then goto leave;

  string_vstring (info, 'machine '(0), -1);
  string_append (info, serv_dot);
  file_inet_adr_name (serv_adr, cmd, stat); {try to get remote node name}
  if sys_error(stat)
    then begin
      sys_error_none (stat);           {didn't get name, reset error}
      end
    else begin                         {remote node name is in CMD}
      string_appends (info, ' ('(0));
      string_append (info, cmd);
      string_appends (info, ')'(0));
      end;
    ;
  string_append1 (info, '.');
  werr (info, stat);
  if sys_error(stat) then goto leave;

  string_vstring (info,
    'Below is a list of the commands sent to the server and its error'(0), -1);
  werr (info, stat);
  if sys_error(stat) then goto leave;

  string_vstring (info,
    'responses, followed by the first '(0), -1);
  string_f_int (tk, nshow_err_k);
  string_append (info, tk);
  string_appends (info,
    ' lines of your message.'(0));
  werr (info, stat);
  if sys_error(stat) then goto leave;
{
*   Send command "MAIL FROM:<address>"
}
  string_vstring (cmd, 'MAIL FROM:<'(0), -1);

  string_append (cmd, adr_from);
  string_append1 (cmd, '>');
  inet_vstr_crlf_put (cmd, hconn, stat); {send MAIL command}
  if sys_error(stat) then goto leave;
  smtp_resp_get (hconn, code, info, ok, stat); {get MAIL command response}
  if sys_error(stat) then goto leave;
  if not ok then begin                 {received error from server ?}
    serror (stat);                     {write message to bounce file}
    if sys_error(stat) then goto leave;
    goto abort_msg;                    {abort this mail message}
    end;
{
*   Send a RCPT command for each recipient of this mail message.
}
  n_rcpt_ok := 0;                      {init number of accepted recipients}
  string_list_init (accadr, util_top_mem_context); {init list of accepted addresses}
  acclist := true;                     {indicate that the ACCADR list now exists}

  string_list_pos_start (adrlist);     {go to before first destination address}
  while true do begin                  {loop over each destination address}
    string_list_pos_rel (adrlist, 1);  {to list entry for this address}
    if adrlist.str_p = nil then exit;  {exhausted the list of addresses}
    string_vstring (cmd, 'RCPT TO:<'(0), -1);
    string_append (cmd, adrlist.str_p^);
    string_append1 (cmd, '>');
    inet_vstr_crlf_put (cmd, hconn, stat); {send this RCPT command}
    if sys_error(stat) then goto leave;
    smtp_resp_get (hconn, code, info, ok, stat); {get response to this RCPT command}
    if sys_error(stat) then goto leave;
    if ok                              {this address was accepted ?}
      then begin
        n_rcpt_ok := n_rcpt_ok + 1;    {count one more accepted recipient}
        accadr.size := adrlist.str_p^.len; {set size of new list entry}
        string_list_line_add (accadr); {create the new list entry}
        string_copy (adrlist.str_p^, accadr.str_p^); {write this adr to accepted adr list}
        end
      else begin                       {remote system rejected this recipient}
        serror (stat);                 {write message to bounce file}
        if sys_error(stat) then goto leave;
        end
      ;
    end;                               {back for next address in destination list}

  if n_rcpt_ok <= 0 then goto abort_msg; {no recipients accepted, don't send msg ?}
{
*   Send the mail message data.
}
  inet_cstr_crlf_put ('DATA'(0), hconn, stat); {indicate start of msg transmission}
  if sys_error(stat) then goto leave;
  smtp_resp_get (hconn, code, info, ok, stat); {get immediate response to DATA cmd}
  if sys_error(stat) then goto leave;
  if not ok then begin
    serror (stat);                     {write message to bounce file}
    if sys_error(stat) then goto leave;
    string_vstring (
      errmsg, 'Unexpected response to DATA command for message '(0), -1);
    string_append (errmsg, mconn.tnam);
    show_resp;                         {show error and response to user}
    goto abort_msg;
    end;

  file_pos_start (mconn, stat);        {re-position to start of file}
  if sys_error(stat) then goto leave;
  while true do begin                  {loop over the message file lines}
    file_read_text (mconn, cmd, stat); {read next message line from file}
    if file_eof(stat) then exit;       {hit end of mail message file ?}
    if sys_error(stat) then goto abort_msg;
    smtp_mailline_put (cmd, hconn, stat); {send this message line}
    if sys_error(stat) then goto abort_msg;
    end;                               {back to do next message line}
  smtp_mail_send_done (hconn, stat);   {send end of message notification}
  if sys_error(stat) then goto abort_msg;
  smtp_resp_get (hconn, code, info, ok, stat); {get final response to DATA cmd}
  if sys_error(stat) then goto abort_msg;
  if not ok then begin
    serror (stat);                     {write message to bounce file}
    if sys_error(stat) then goto leave;
    string_vstring (
      errmsg, 'Unexpected response message data for message '(0), -1);
    string_append (errmsg, mconn.tnam);
    show_resp;                         {show error and response to user}
    goto abort_msg;
    end;

  msg_sent := true;                    {message sent or bounce errors generated}
  goto done_msg;
{
*   Abort with the SMTP conversation in the middle of a message.  This is after
*   the MAIL command and before the end of the DATA command.
}
abort_msg:
  inet_str_crlf_put ('RSET', hconn, stat); {abort this mail message}
  if sys_error(stat) then goto leave;
  smtp_resp_get (hconn, code, info, ok, stat); {get response to RSET command}
  sys_error_none (stat);
{
*   Done with sending or trying to send the message.
*
*   MSG_SENT is TRUE if the whole message was sent and acknoledged.  The local
*   string list ACCADR contains the list of recipient addresses that were
*   accepted by the remote server.  ERR is TRUE if one or more error message
*   were written to the bounce message file.
}
done_msg:
  if err then begin                    {errors written to bounce file ?}
    send_bounce;                       {send bounce message on any errors}
    end;
  err_close;                           {close and delete the bounce message file}
  {
  *   If the message was sent, delete the accepted addresses from the recipient
  *   list.  The addresses list is effectively returned the remaining addresses
  *   list.
  *
  *   The accepted addresses are in the ACCADR list, in the order that they
  *   appear in the ADRLIST list.
  }
  if msg_sent then begin               {the message was sent ?}
    string_list_pos_abs (adrlist, 1);  {to first recipient list entry}
    string_list_pos_start (accadr);    {to before start of accepted list}
    while true do begin                {loop thru each accepted list entry}
      string_list_pos_rel (accadr, 1); {to this accepted address}
      if accadr.str_p = nil then exit; {done processing all accepted addresses ?}
      while adrlist.str_p <> nil do begin {scan forwards thru the recipient list}
        if string_equal(adrlist.str_p^, accadr.str_p^) then begin {found accepted adr ?}
          string_list_line_del (adrlist, true); {delete this adr from recipient list}
          exit;
          end;
        string_list_pos_rel (adrlist, 1); {no match, advance to next recipient adr}
        end;                           {back to check this new recipient address}
      end;                             {back to process next accepted address}
    end;
{
*   Common exit point.  STAT must already be set.  The bounce message file may
*   be open.
}
leave:
  if acclist then begin                {accepted addresses list exists ?}
    string_list_kill (accadr);         {deallocate the list}
    acclist := false;                  {indicate list no longer exists}
    end;
  err_close;                           {close and delete bounce message, if open}
  end;
