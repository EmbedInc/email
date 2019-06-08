{   Function SMTP_RECV (CLIENT, TURN, STAT)
*
*   Perform SMTP protocol in receive mode.  We get here immediately after
*   establishing a connection if we are a server, or immediately after getting
*   a positive response to the TURN command if we are a client.
*
*   CLIENT is the SMTP client descriptor.  This contains, among other things,
*   the network connection and the name of the input queue.
*
*   TURN is set to TRUE by the caller if we are willing to allow role reversal.
*   TURN is returned TRUE if the client requested role reversal, and the caller
*   originally allowed it.
*
*   The function returns TRUE if at least one message was received and written
*   into the input queue, and FALSE otherwise.
*
*   This function may close the client connection under certain conditions.
*   Callers must check CLIENT.OPEN before attempting any further communication
*   with the client.  Even if the client connection is closed, the client
*   descriptor must still be eventually closed and deallocated by calling
*   SMTP_CLIENT_CLOSE.  The client connection is never closed when TURN is
*   returned TRUE.
}
module smtp_recv;
define smtp_recv;
%include 'email2.ins.pas';

const
  n_cmd_k = 11;                        {number of SMTP commands we recognize}
  cmd_len_max_k = 4;                   {chars in longest SMTP command name}

  cmds_len_ent_k = cmd_len_max_k + 1;  {chars reserved for each command in CMDS}

type
  cmds_ent_t =                         {format for each CMDS array entry}
    array[1..cmds_len_ent_k] of char;

var
  cmds: array[1..n_cmd_k] of cmds_ent_t := [ {all the SMTP command we recognize}
    'HELO',                            {1}
    'MAIL',                            {2}
    'RCPT',                            {3}
    'DATA',                            {4}
    'RSET',                            {5}
    'HELP',                            {6}
    'NOOP',                            {7}
    'QUIT',                            {8}
    'TURN',                            {9}
    'EHLO',                            {10}
    'AUTH',                            {11}
    ];

function smtp_recv (                   {get all mail from remote system into queue}
  in out  client: smtp_client_t;       {info on the remote client}
  in out  turn: boolean;               {in TRUE to allow TURN, TRUE on TURN received}
  out     stat: sys_err_t)             {returned completion status code}
  :boolean;                            {at least one message written to input queue}
  val_param;

var
  qdir: string_treename_t;             {name of top level queue directory}
  qopts: smtp_queue_options_t;         {info about the input mail queue}
  qopt2: smtp_queue_options_t;         {scratch queue information descriptor}
  str: string_var8192_t;               {scratch var string}
  buf: string_var8192_t;               {one line input buffer}
  adrs: string_var256_t;               {email address string}
  tk, tk2: string_var256_t;            {scratch tokens}
  user: string_var80_t;                {user name}
  pswd: string_var80_t;                {password}
  p: string_index_t;                   {BUF parse index}
  p2: string_index_t;                  {scratch string parse index}
  cmd: string_var32_t;                 {command name extracted from BUF}
  pick: sys_int_machine_t;             {number of keyword picked from list}
  sys_remote: string_var256_t;         {dot notation name of remote system}
  name_remote: string_var256_t;        {name claimed by remote system, may be empty}
  logstr: string_var256_t;             {log message string}
  conn_c: file_conn_t;                 {handle to queue entry control file}
  conn_a: file_conn_t;                 {handle to queue entry addresses list file}
  conn_m: file_conn_t;                 {handle to queue entry mail message file}
  adr: email_adr_t;                    {descriptor for one email address}
  n_adr: sys_int_machine_t;            {number of addresses for curr message}
  n_adrused: sys_int_machine_t;        {adr for current message not ignored}
  open: boolean;                       {a queue entry is currently open}
  done: boolean;                       {TRUE when hit end of mail message}
  auth: boolean;                       {client completed authorization sequence}
  client_local: boolean;               {client is on our LAN}
  blacklisted: boolean;                {client blacklisted during this session}
  ignoremsg: boolean;                  {ignore current message, detected as spam}
  ignoreadr: boolean;                  {ignore current target address}
  black: boolean;                      {this address triggered blacklisting}
  save: boolean;                       {store and save this message}
  stat2: sys_err_t;                    {to avoid corrupting STAT}

label
  loop_cmd, adr_ok, adr_bad, loop_msg, done_msg,
  auth_getuser, auth_getpswd, auth_auth, done_auth, done_cmd, err_syn_args, abort;
{
**********************************************************************************
*
*   Local subroutine ABORT_MESSAGE (STAT)
*
*   Abort the currently open mail queue entry, if any.  This will leave the
*   state as if the mail entry was never created.  Any information about the
*   current mail message will be lost.
}
procedure abort_message (              {close and delete any partially written msg}
  out     stat: sys_err_t);            {returned completion status code}

begin
  sys_error_none (stat);               {init to no error}
  if not open then return;             {no mail message currently open ?}
  smtp_queue_create_close (            {close and delete this queue entry}
    conn_c, conn_a, conn_m,            {handles to the queue entry files}
    false,                             {don't keep this entry}
    stat);
  open := false;                       {indicate no mail message currently open}
  end;
{
**********************************************************************************
*
*   Start of main routine.
}
begin
  qdir.max := sizeof(qdir.str);
  str.max := sizeof(str.str);
  buf.max := sizeof(buf.str);
  adrs.max := sizeof(adrs.str);
  tk.max := sizeof(tk.str);
  tk2.max := sizeof(tk2.str);
  user.max := sizeof(user.str);
  pswd.max := sizeof(pswd.str);
  cmd.max := sizeof(cmd.str);
  sys_remote.max := sizeof(sys_remote.str);
  name_remote.max := sizeof(name_remote.str);
  logstr.max := sizeof(logstr.str);
  smtp_recv := false;                  {init to no message written to input queue}

  sys_cognivis_dir ('smtpq'(0), qdir); {get name of top level queue directory}
  smtp_queue_opts_get (qdir, client.inq, qopts, stat); {get OPTIONS info for input queue}
  if sys_error(stat) then return;
  if client.inq.len <= 0 then begin    {no specific input queue given}
    string_copy (qopts.inq, client.inq); {use default input queue}
    if client.inq.len <= 0 then begin  {no input queue name available at all ?}
      sys_stat_set (email_subsys_k, email_stat_smtp_no_in_queue_k, stat);
      return;                          {return with error}
      end;
    smtp_queue_opts_get (qdir, client.inq, qopts, stat); {get options info for this queue}
    if sys_error(stat) then return;
    end;

  auth := false;                       {init to client not performed authorization}
  client_local := sys_inetadr_local (client.adr); {determine if client on local network}
  string_f_inetadr (sys_remote, client.adr); {make dot notation name of remote node adr}
  blacklisted := false;                {init to client not blacklisted this session}
{
*   Send initial wakeup identification.
}
  string_vstring (str, '220 '(0), -1);
  string_append (str, qopts.localsys);
  string_appends (str, ' SMTP Server ready');
  inet_vstr_crlf_put (str, client.conn, stat);
  if sys_error(stat) then return;
{
*   Init state before looping thru client commands.
}
  open := false;                       {no queue entry is currently open}
{
***********************************************
*
*   Client command loop.  Back here to process each new command from client.
}
loop_cmd:
  inet_vstr_crlf_get (buf, client.conn, stat); {get next command line from client}
  discard( string_eos(stat) );         {no command is same as command with 0 len}
  if sys_error(stat) then goto abort;
  string_unpad (buf);                  {delete trailing spaces}
  p := 1;                              {init BUF parse index}
  string_token (buf, p, cmd, stat);    {extract command name}
  string_upcase (cmd);                 {make upper case for keyword matching}
  string_tkpick_s (cmd, cmds, sizeof(cmds), pick); {pick command name from list}
  case pick of                         {which command is this ?}
{
************************
*
*   HELO <remote system name>
}
1: begin
  auth := false;                       {init to client not authenticated}
  abort_message (stat);
  if sys_error(stat) then goto abort;

  string_token (buf, p, name_remote, stat); {extract remote system name}
  discard( string_eos(stat) );         {no system name is same as zero length}
  if sys_error(stat) then goto abort;
{
*   Send reply.
}
  string_vstring (str, '250 '(0), -1);
  string_append (str, qopts.localsys);
  string_appends (str, ' Client is on machine '(0));
  string_append (str, sys_remote);
  if name_remote.len > 0 then begin    {we have remote machine name ?}
    string_appends (str, ' ('(0));
    string_append (str, name_remote);
    string_append1 (str, ')');
    end;
  inet_vstr_crlf_put (str, client.conn, stat);
  end;
{
************************
*
*   MAIL FROM:<reverse path>
*
*   In our implementation, we ignore the reverse path.
}
2: begin
  abort_message (stat);                {abort old unfinished mail message, if any}
  if sys_error(stat) then goto abort;

  smtp_queue_create_ent (              {create new mail queue entry}
    client.inq,                        {generic mail queue name}
    conn_c,                            {returned connection handle to control file}
    conn_a,                            {returned connection handle to adr list file}
    conn_m,                            {returned connection handle to message file}
    stat);
  if sys_error(stat) then goto abort;
  open := true;                        {indicate a mail message is now pending}
  n_adr := 0;                          {init number of target addresses for this msg}
  n_adrused := 0;                      {init target addresses actually used}
  ignoremsg := blacklisted;            {init whether to ignore this message}

  inet_cstr_crlf_put ('250 New mail message opened.'(0), client.conn, stat);

  smtp_client_log_str (client, 'New message opened');
  end;
{
************************
*
*   RCPT TO:<forward path>
*
*   We don't accept addresses that specify a route.  We only accept end mail
*   addresses user@machine.domain, where "domain" may be several names separated
*   by dots.
}
3: begin
  if not open then begin               {no mail message currently open ?}
    inet_cstr_crlf_put ('503 No mail message open.'(0), client.conn, stat);
    goto done_cmd;
    end;

  str.len := 0;                        {init extracted mail address string}
  while (p <= buf.len) and (buf.str[p] <> '<') {first "<" before mail address}
    do p := p + 1;
  p := p + 1;                          {skip over "<"}
  while (p <= buf.len) and (buf.str[p] <> '>') do begin {copy mail address chars}
    string_append1 (str, buf.str[p]);
    p := p + 1;
    end;
  if                                   {check for syntax error}
      (p > buf.len) or                 {never found trailing ">" ?}
      (str.len = 0)                    {mail address missing ?}
    then goto err_syn_args;
{
*   The mail address string has been extracted into STR.
}
  email_adr_create (adr, client.mem_p^); {create descriptor for this email address}
  email_adr_string_add (adr, str);     {make expanded description of email address}
  email_adr_t_string (adr, email_adrtyp_at_k, adrs); {make sanitized email address in ADRS}

  if
      client_local and                 {this is a local client ?}
      (not qopts.userput)              {no user name required for local clients ?}
    then goto adr_ok;                  {accept mail from this client}
  if auth then goto adr_ok;            {client has explicitly authorized itself ?}
  {
  *   Client is not explicitly authorized.  Accept this target address only
  *   if it is to one of our domains.
  }
  email_adr_domain (adr, tk);          {make domain of this address in TK}
  p2 := 1;                             {init domain names list parse index}
  while true do begin                  {back for each new acceptable domain name}
    string_token (qopts.recvdom, p2, tk2, stat); {get next acceptable domain in TK2}
    if string_eos(stat) then goto adr_bad; {no match found ?}
    if sys_error(stat) then goto adr_bad; {give up on hard error}
    if string_equal (tk, tk2) then goto adr_ok; {is one of our receiving domains ?}
    end;                               {back to check next acceptable domain}
{
*   It is OK to accept mail to this address.  The expanded address is in ADR,
*   and string format of the address in ADRS.  LOGSTR contains the start of the
*   log message ending in the address.
}
adr_ok:                                {the mail destination address is acceptable}
  ignoreadr := false;                  {init to this address not ignored}
  black := false;                      {init to this address not cause blacklisting}
  email_adr_translate (adr);           {translate to local version of target address}
  email_adr_t_string (adr, email_adrtyp_at_k, str); {make local address string}
  {
  *   After translating the recevied email address thru our MAIL.ADR file set,
  *   first domain name is really the name of the mail to pass this message on.
  *   The mailers are defined in the MAILERS.MSG file and mostly don't mean
  *   anything to us here.  However, the special mailer IGNORE causes the
  *   message to be ignored, and is trapped as a special case here.  We will
  *   discard messages bound for the IGNORE mailer here as a special case to
  *   descrease system load to queue and dequeue the many spam messages.
  *
  *   The next domain name after (more local) IGNORE is set by the MAIL.ADR file
  *   set to indicate the reason to ignore the message.  The only one that is
  *   relevant here is BLACKLIST, which causes us to not only ignore the message
  *   but blacklist the client to that future connections from it are rejected.
  }
  if adr.dom_first = 0 then ignoreadr := true; {address didn't translate to anything valid ?}
  if adr.dom_first > 0 then begin      {mailer name is available ?}
    string_list_pos_abs (adr.names, adr.dom_first); {go to mailer name}
    string_copy (adr.names.str_p^, tk); {make local copy of mailer name}
    string_upcase (tk);
    if string_equal (tk, string_v('IGNORE'(0))) then begin {special case of IGNORE mailer ?}
      ignoreadr := true;               {definitely ignore this address}
      string_list_pos_rel (adr.names, 1); {advance to next more local dom name}
      if adr.names.str_p <> nil then begin {second domain name exists ?}
        string_copy (adr.names.str_p^, tk); {make local copy of second dom}
        string_upcase (tk);
        black := black or              {blacklisted ?}
          string_equal (tk, string_v('BLACKLIST'(0)));
        end;
      end;                             {end of IGNORE mailer case}
    end;
  email_adr_delete (adr);              {deallocate email address descriptor}

  if ignoreadr                         {init log string}
    then begin
      string_vstring (logstr, 'IGNORING '(0), -1);
      end
    else begin
      string_vstring (logstr, 'ACCEPTING '(0), -1);
      end
    ;
  string_append (logstr, adrs);        {add address to log string}

  if black then begin
    blacklisted := true;               {ignore everything further this session}
    ignoremsg := true;                 {ignore this message}
    smtp_client_blacklist (client);    {blacklist this client}
    string_appends (logstr, ' BLACKLISTING');
    end;
  smtp_client_log_vstr (client, logstr);

  if not ignoreadr then begin          {don't ignore this target address ?}
    file_write_text (adrs, conn_a, stat); {write adr to addresses list file}
    if sys_error(stat) then goto abort;
    n_adrused := n_adrused + 1;
    end;
  n_adr := n_adr + 1;                  {count one more target address for this msg}

  inet_cstr_crlf_put ('250 Recipient address stored.'(0), client.conn, stat);
  goto done_cmd;                       {done processing this command}
{
*   The client is from outside our LAN, but trying to send to an address
*   that is also external.  The client is obviously up to no good and
*   will be rejected without much cerimony.
}
adr_bad:
  string_vstring (logstr, 'REJECTING RELAY '(0), -1);
  string_append (logstr, adrs);
  smtp_client_log_vstr (client, logstr); {log the action}

  email_adr_delete (adr);              {deallocate email address descriptor}
  abort_message (stat);                {close and delete pending mail message}

  sys_stat_set (email_subsys_k, email_stat_mail_relay_k, stat); {pass back error}
  sys_stat_parm_vstr (sys_remote, stat); {client machine IP address}
  sys_stat_parm_vstr (name_remote, stat); {client machine name according to client}
  sys_stat_parm_vstr (adrs, stat);     {the target email address}

  turn := false;                       {we are definitely not reversing roles}
  sys_wait (1.0);                      {wait a while to slow down repeated attacks}
  return;                              {return with invalid relay attempt error}
  end;
{
************************
*
*   DATA
}
4: begin
  if not open then begin               {no mail message currently open ?}
    inet_cstr_crlf_put ('503 No mail message open.'(0), client.conn, stat);
    goto done_cmd;
    end;
  if n_adr <= 0 then begin             {no target addresses for this message ?}
    inet_cstr_crlf_put ('503 No target addresses given.'(0), client.conn, stat);
    goto done_cmd;
    end;

  ignoremsg := ignoremsg or            {ignore message if no valid target addresses}
    (n_adrused = 0);
  if                                   {blacklist client for being a spammer ?}
      (n_adr >= 2) and                 {tried at least 2 target addresses ?}
      (n_adrused = 0) and              {none of them were any good ?}
      (not blacklisted)                {we didn't already blacklist this client ?}
      then begin
    smtp_client_blacklist (client);    {blacklist the dirtbag}
    blacklisted := true;               {remember we've already blacklisted this client}
    end;

  if ignoremsg then begin              {ignore this message ?}
    abort_message (stat);              {close the message}
    smtp_client_close_conn (client);   {close connection to the client}
    turn := false;                     {definitely not reversion roles}
    return;                            {outta here}
    end;
{
*   Create time stamp line and insert it as the first mail message line.
*   The time stamp line has the format:
*
*   Received: from <remote system name> by <local system name> ; <date/time>
}
  string_vstring (str, 'Received: from '(0), -1);
  string_append (str, sys_remote);
  if name_remote.len > 0 then begin    {we have remote machine name ?}
    string_appends (str, ' ('(0));
    string_append (str, name_remote);
    string_append1 (str, ')');
    end;
  string_appends (str, ' by '(0));
  string_append (str, qopts.localsys);
  string_appends (str, ' ; '(0));
  sys_date_time1 (tk);                 {get date/time "YYYY MMM DD HH:MM:SS ZZZZ"}
  string_append (str, tk);

  file_write_text (str, conn_m, stat); {write time stamp line to mail message file}
  if sys_error(stat) then goto abort;
{
*   Copy the mail message to the end of the mail message file.
}
  inet_cstr_crlf_put ('354 Ready for mail message text.'(0), client.conn, stat);

loop_msg:                              {back here each new mail message line}
  smtp_mailline_get (client.conn, str, done, stat); {get next line from sender}
  if sys_error(stat) then goto abort;
  if done then goto done_msg;          {hit end of mail message}
  file_write_text (str, conn_m, stat); {copy this line to mail message file}
  if sys_error(stat) then goto abort;
  goto loop_msg;                       {back for next line}

done_msg:                              {done reading entire mail message}
  save := not ignoremsg;               {save this message ?}
  smtp_queue_create_close (            {close and save this mail queue entry}
    conn_c, conn_a, conn_m,            {handles to mail queue files}
    save,                              {keep this queue entry}
    stat);
  if sys_error(stat) then goto abort;
  open := false;                       {indicate no mail message currently open}
  if save then smtp_recv := true;      {at least one message written to queue}

  inet_cstr_crlf_put ('250 Mail message saved and closed.'(0), client.conn, stat);
  end;
{
************************
*
*   RSET
}
5: begin
  abort_message (stat);
  if sys_error(stat) then goto abort;

  inet_cstr_crlf_put ('250 Ready for new mail message.'(0), client.conn, stat);
  end;
{
************************
*
*   HELP [<string>]
}
6: begin
  string_token (buf, p, cmd, stat);    {try to get help topic token, if any}

  if string_eos(stat) then begin       {no specific help topic selected}
    inet_cstr_crlf_put ('214-SMTP Commands:'(0), client.conn, stat);
    if sys_error(stat) then goto abort;
    inet_cstr_crlf_put ('214-  HELO (sender machine name)'(0), client.conn, stat);
    if sys_error(stat) then goto abort;
    inet_cstr_crlf_put ('214-  MAIL FROM:<(reverse path)>'(0), client.conn, stat);
    if sys_error(stat) then goto abort;
    inet_cstr_crlf_put ('214-  RCPT TO:<(forward path)>'(0), client.conn, stat);
    if sys_error(stat) then goto abort;
    inet_cstr_crlf_put ('214-  DATA'(0), client.conn, stat);
    if sys_error(stat) then goto abort;
    inet_cstr_crlf_put ('214-  RSET'(0), client.conn, stat);
    if sys_error(stat) then goto abort;
    inet_cstr_crlf_put ('214-  HELP [(help topic)]'(0), client.conn, stat);
    if sys_error(stat) then goto abort;
    inet_cstr_crlf_put ('214-  NOOP'(0), client.conn, stat);
    if sys_error(stat) then goto abort;
    inet_cstr_crlf_put ('214-  QUIT'(0), client.conn, stat);
    if sys_error(stat) then goto abort;
    inet_cstr_crlf_put ('214-  TURN'(0), client.conn, stat);
    if sys_error(stat) then goto abort;
    inet_cstr_crlf_put ('214 All command names are valid HELP topics.'(0), client.conn, stat);
    goto done_cmd;
    end;

  if sys_error(stat) then goto abort;  {error parsing help topic from command line ?}

  string_upcase (cmd);                 {make upper case for keyword matching}
  string_tkpick_s (cmd, cmds, sizeof(cmds), pick); {pick command name from list}
  case pick of                         {which command is this ?}

1: begin                               {HELO}
  inet_cstr_crlf_put ('214-Command HELO (sender machine name)'(0), client.conn, stat);
  if sys_error(stat) then goto abort;
  inet_cstr_crlf_put ('214   Must be first command.'(0), client.conn, stat);
  end;

2: begin                               {MAIL}
  inet_cstr_crlf_put ('214-Command MAIL FROM:<(reverse path)>'(0), client.conn, stat);
  if sys_error(stat) then goto abort;
  inet_cstr_crlf_put ('214   Starts new mail message.'(0), client.conn, stat);
  end;

3: begin                               {RCPT}
  inet_cstr_crlf_put ('214-Command RCPT TO:<(forward path)>'(0), client.conn, stat);
  if sys_error(stat) then goto abort;
  inet_cstr_crlf_put ('214   Declare one recipient of current message.'(0),
    client.conn, stat);
  end;

4: begin                               {DATA}
  inet_cstr_crlf_put ('214-Command DATA'(0), client.conn, stat);
  if sys_error(stat) then goto abort;
  inet_cstr_crlf_put ('214-  Mail message data follows on subsequent lines'(0),
    client.conn, stat);
  inet_cstr_crlf_put ('214   Ends with line containing only ".".'(0), client.conn, stat);
  end;

5: begin                               {RSET}
  inet_cstr_crlf_put ('214-Command RSET'(0), client.conn, stat);
  if sys_error(stat) then goto abort;
  inet_cstr_crlf_put ('214   Discards any current mail message.'(0), client.conn, stat);
  end;

6: begin                               {HELP}
  inet_cstr_crlf_put ('214-Command HELP [(help topic)]'(0), client.conn, stat);
  if sys_error(stat) then goto abort;
  inet_cstr_crlf_put ('214   Returns general help, or help about specific topic.'(0),
    client.conn, stat);
  end;

7: begin                               {NOOP}
  inet_cstr_crlf_put ('214-Command NOOP'(0), client.conn, stat);
  if sys_error(stat) then goto abort;
  inet_cstr_crlf_put ('214   No operation.'(0), client.conn, stat);
  end;

8: begin                               {QUIT}
  inet_cstr_crlf_put ('214-Command QUIT'(0), client.conn, stat);
  if sys_error(stat) then goto abort;
  inet_cstr_crlf_put ('214   Ends SMTP session.'(0), client.conn, stat);
  end;

9: begin                               {TURN}
  inet_cstr_crlf_put ('214-Command TURN'(0), client.conn, stat);
  if sys_error(stat) then goto abort;
  inet_cstr_crlf_put ('214   Reverses sender/receiver roles.'(0), client.conn, stat);
  end;

otherwise                              {unrecognized help topic}
    string_vstring (str, '504 Help topic '(0), -1);
    string_append (str, cmd);
    string_appends (str, ' is not recognized.'(0));
    inet_vstr_crlf_put (str, client.conn, stat);
    end;                               {end of HELP topic keyword cases}
  end;
{
************************
*
*   NOOP
}
7: begin
  if open
    then begin                         {a mail message is in progress}
      inet_cstr_crlf_put ('250 Mail message currently open.'(0), client.conn, stat);
      end
    else begin                         {no mail message is in progress}
      inet_cstr_crlf_put ('250 Ready for new mail message.'(0), client.conn, stat);
      end
    ;
  end;
{
************************
*
*   QUIT
}
8: begin
  abort_message (stat);
  if sys_error(stat) then goto abort;

  string_vstring (str, '221 '(0), -1);
  string_append (str, qopts.localsys);
  string_appends (str, ' signing off.');
  inet_vstr_crlf_put (str, client.conn, stat);

  turn := false;                       {we are not reversing send/recv roles}
  return;                              {normal return}
  end;
{
************************
*
*   TURN
}
9: begin
  abort_message (stat);
  if sys_error(stat) then goto abort;

  if turn then begin                   {role reversal allowed ?}
    inet_cstr_crlf_put ('250 Reversing role to become transmitter.'(0), client.conn, stat);
    return;                            {normal return with roles reversed}
    end;

  inet_cstr_crlf_put ('502 Role reversal currently disabled.'(0), client.conn, stat);
  end;
{
************************
*
*   EHLO <remote system name>
}
10: begin
  abort_message (stat);
  if sys_error(stat) then goto abort;

  string_token (buf, p, name_remote, stat); {extract remote system name}
  discard( string_eos(stat) );         {no system name is same as zero length}
  if sys_error(stat) then goto abort;
{
*   Send reply.
}
  string_vstring (str, '250-'(0), -1);
  string_append (str, qopts.localsys);
  string_appends (str, ' Client is on machine '(0));
  string_append (str, sys_remote);
  if name_remote.len > 0 then begin    {we have remote machine name ?}
    string_appends (str, ' ('(0));
    string_append (str, name_remote);
    string_append1 (str, ')');
    end;
  inet_vstr_crlf_put (str, client.conn, stat);
  if sys_error(stat) then goto abort;

  string_vstring (str, '250-HELP'(0), -1);
  inet_vstr_crlf_put (str, client.conn, stat);
  if sys_error(stat) then goto abort;

  string_vstring (str, '250-TURN'(0), -1);
  inet_vstr_crlf_put (str, client.conn, stat);
  if sys_error(stat) then goto abort;

  string_vstring (str, '250 AUTH LOGIN PLAIN'(0), -1);
  inet_vstr_crlf_put (str, client.conn, stat);
  if sys_error(stat) then goto abort;
  end;
{
************************
*
*   AUTH <auth type name> [<key>]
}
11: begin
  abort_message (stat);                {abort old unfinished mail message, if any}
  if sys_error(stat) then goto abort;
  auth := false;                       {init to client not authorized}

  string_token (buf, p, tk, stat);     {get AUTH subcommand}
  if string_eos(stat) then goto auth_getuser;
  if sys_error(stat) then goto abort;
  string_upcase (tk);                  {make upper case for keyword matching}
  string_tkpick80 (tk,                 {pick subcommand from list}
    'LOGIN PLAIN',
    pick);
  case pick of                         {which AUTH subcommand is it ?}
{
*   AUTH LOGIN [user] [password]
}
1:  begin
      string_token (buf, p, str, stat); {try to get optional user name}
      if string_eos(stat) then goto auth_getuser;
      if sys_error(stat) then goto abort;
      string_f_base64 (str, user);     {convert from BASE64 encoding}

      string_token (buf, p, str, stat); {try to get optional password}
      if string_eos(stat) then goto auth_getpswd;
      if sys_error(stat) then goto abort;
      string_f_base64 (str, pswd);     {convert from BASE64 encoding}

      goto auth_auth;                  {go authenticate USER and PSWD}
      end;
{
*   AUTH PLAIN [user password]
}
2:  begin
      string_token (buf, p, tk, stat); {try to get user-password BASE64 string}
      if string_eos(stat) then goto auth_getuser;
      if sys_error(stat) then goto abort;
      string_f_base64 (tk, str);       {get plain text user and password string}
      p2 := 1;                         {init user-password parse index}

      string_token (str, p2, tk, stat); {try to get optional user name}
      if string_eos(stat) then goto auth_getuser;
      if sys_error(stat) then goto abort;
      string_f_base64 (tk, user);      {convert from BASE64 encoding}

      string_token (str, p2, tk, stat); {try to get optional password}
      if string_eos(stat) then goto auth_getpswd;
      if sys_error(stat) then goto abort;
      string_f_base64 (tk, pswd);      {convert from BASE64 encoding}

      goto auth_auth;                  {go authenticate USER and PSWD}
      end;
{
*   Unrecognized AUTH subcommand.
}
otherwise
    goto abort;
    end;
{
*   Prompt and get user name into USER.
}
auth_getuser:                          {nothing recceived prompt for user name}
  string_vstring (str, '334 '(0), -1); {init challenge response string}
  string_vstring (tk, 'Username:'(0), -1); {challenge command}
  string_t_base64 (tk, tk2);           {convert challenge command to BASE64}
  string_append (str, tk2);
  inet_vstr_crlf_put (str, client.conn, stat);
  if sys_error(stat) then goto abort;

  inet_vstr_crlf_get (str, client.conn, stat); {get client response to USERNAME challenge}
  if sys_error(stat) then goto abort;
  string_f_base64 (str, user);         {convert from BASE64 encoding}
{
*   Prompt and get password into PSWD.
}
auth_getpswd:
  string_vstring (str, '334 '(0), -1); {init challenge response string}
  string_vstring (tk, 'Password:'(0), -1); {challenge command}
  string_t_base64 (tk, tk2);           {convert challenge command to BASE64}
  string_append (str, tk2);
  inet_vstr_crlf_put (str, client.conn, stat);
  if sys_error(stat) then goto abort;

  inet_vstr_crlf_get (str, client.conn, stat); {get client response to PASSWORD challenge}
  if sys_error(stat) then goto abort;
  string_f_base64 (str, pswd);         {convert from BASE64 encoding}
{
*   The client has supplied a user name and password, which have been
*   stored in USER and PSWD.
*
*   Now validate USER and PSWD.  The boolean variable AUTH is set to TRUE
*   on successful validation.  AUTH has already been initialized to FALSE.
}
auth_auth:
  string_downcase (user);              {user names are queue names, and lower case}
  if user.len <= 0 then goto done_auth; {no user name specified ?}

  smtp_queue_opts_get (qdir, user, qopt2, stat); {get info about user's queue}
  if sys_error(stat) then begin        {hard error reading OPTIONS files ?}
    sys_error_none (stat);             {reset the error condition}
    goto done_auth;                    {abort the authorization process}
    end;
  if not qopt2.localqueue              {user name invalid ?}
    then goto done_auth;
  if qopt2.pswdput.len <= 0            {authentication explicitly disabled ?}
    then goto done_auth;
  if not string_equal (pswd, qopt2.pswdput) {password doesn't match ?}
    then goto done_auth;

  auth := true;                        {client is authorized}
done_auth:                             {AUTH all set for this user}

  if auth
    then begin                         {received the correct response}
      string_vstring (str, '235 OK'(0), -1);
      end
    else begin                         {received incorrect response}
      sys_wait (1.0);
      string_vstring (str, '535 Wrong, bozo'(0), -1);
      end
    ;
  inet_vstr_crlf_put (str, client.conn, stat);
  if sys_error(stat) then goto abort;
  end;
{
************************
*
*   Unrecognized command.
}
otherwise
    string_vstring (str, '500 Command '(0), -1);
    string_append (str, cmd);
    string_appends (str, ' is not recognized.');
    inet_vstr_crlf_put (str, client.conn, stat);
    end;                               {end of command name cases}
{
*   Done processing the current command.  Abort if STAT is indicating an error.
}
done_cmd:                              {jump here when done with current command}
  if sys_error(stat) then goto abort;  {a hard error is flagged ?}
  goto loop_cmd;                       {back for next command from sender}
{
*   A syntax error to arguments to the current command has been detected.
}
err_syn_args:
  inet_cstr_crlf_put ('501 Syntax error in command parameters.'(0), client.conn, stat);
  goto done_cmd;
{
*   A hard error occurred after the initial wakeup handshake.  Try to close
*   down as gracefully as possible.  STAT must already be set before coming
*   here.
}
abort:
  abort_message (stat2);               {close and delete any pending mail message}
  string_vstring (str, '421 '(0), -1); {try to tell client we are going away}
  string_append (str, qopts.localsys);
  string_appends (str, ' closing connection due to internal error.');
  inet_vstr_crlf_put (str, client.conn, stat2);

  turn := false;                       {we are definately not reversing roles}
  end;
