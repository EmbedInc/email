{   Program POP3 <options>
*
*   This program is a server for the Post Office Protocol version 3, as described
*   in RFC 1725.  While the network side of this server conforms to RFC 1725,
*   the other side assumes the use of the Cognivision mail queueing system.
*
*   The command line options are:
*
*     -DEBUG level
*
*       Set the level of status and debug messages.  0 disables all optional
*       messages.  The maximum level is 10.  The default is 5.
}
program pop3;
%include 'base.ins.pas';
%include 'email.ins.pas';

const
  pop3_port_k = 110;                   {standard port for POP3 server}
  max_msg_parms = 1;                   {max parameters we can pass to a message}
  ipsave_n = 16;                       {number of last connection attempt IPs to save}
  ip_rej_sec = 30.0;                   {reject request if last bad within this time, seconds}
{
*   Derived constants.
}
  ipsave_last = ipsave_n - 1;          {last valid 0-N index for saved IP address}

type
  msg_ent_t = record                   {info about each possible mail queue entry}
    n: sys_int_machine_t;              {QCONN.LIST_ENTS index for this entry}
    size: sys_int_adr_t;               {message file size in machine address units}
    delete: boolean;                   {TRUE if marked for deletion by client}
    end;

  msg_ar_t = array[1..1] of msg_ent_t; {template for client message numbers array}
  msg_ar_p_t = ^msg_ar_t;

  remconn_t = record                   {info about one remote connection attempt}
    ip: sys_inet_adr_node_t;           {IP address}
    time: sys_clock_t;                 {time of connection attempt}
    end;

var
  opt:                                 {command line option name or client cmd name}
    %include '(cog)lib/string256.ins.pas';
  pick: sys_int_machine_t;             {number of token picked from list}
  serv: file_inet_port_serv_t;         {handle to our internet server port}
  conn_client: file_conn_t;            {connection handle to client internet stream}
  ii: sys_int_machine_t;               {scratch integer}
  buf:                                 {buffer containing latest client command}
    %include '(cog)lib/string8192.ins.pas';
  p: string_index_t;                   {BUF parse index}
  queue:                               {generic mail queue name}
    %include '(cog)lib/string_leafname.ins.pas';
  parm:                                {parameter parsed from client or command line}
    %include '(cog)lib/string256.ins.pas';
  tk:                                  {scratch string for number conversion}
    %include '(cog)lib/string32.ins.pas';
  pass:                                {password}
    %include '(cog)lib/string80.ins.pas';
  qconn: smtp_qconn_read_t;            {handle to mail queue read connection}
  msg_ar_p: msg_ar_p_t;                {pointer to client messages array}
  n_msg: sys_int_machine_t;            {number of messages listed in MSG_AR_P^}
  size_all: sys_int_adr_t;             {total size of all mail messages}
  n_ndel: sys_int_machine_t;           {number of messages not marked as deleted}
  size_ndel: sys_int_adr_t;            {size of all message not marked as deleted}
  mem_p: util_mem_context_p_t;         {pointer to mem context for current client}
  to_list_p: string_list_p_t;          {pointer to message destination addresses}
  mconn_p: file_conn_p_t;              {pointer to message body connection handle}
  rem_adr: sys_inet_adr_node_t;        {address of remote client node}
  rem_port: sys_inet_port_id_t;        {client port on remote node}
  connlist:                            {list of recent bad connection requests}
    array[0 .. ipsave_last] of remconn_t;
  connext: sys_int_machine_t;          {CONNLIST index where to store next}
  connt: sys_clock_t;                  {time of current connection request}
  time: sys_clock_t;                   {scratch time value}
  dt: real;                            {scratch delta time value, seconds}
  reminfo: boolean;                    {info on remote connection is valid}
  user_ok: boolean;                    {TRUE if user properly autenticated}
  conn_ok: boolean;                    {connection attempt was valid}
  show_abort: boolean;                 {write Aborted message to StdOut on abort}

  msg_parm:                            {parameter references for messages}
    array[1..max_msg_parms] of sys_parm_msg_t;
  stat: sys_err_t;                     {completion status code}

label
  loop_opts, done_opts, loop_server, next_listent, loop_cmd, loop_retr,
  eof_retr, retr_abort, done_cmd, done_multiline, wrong_state, err_parm,
  abort_client;
{
******************************************************************************
*
*   Local function AUTHENTICATE
*
*   Return TRUE only if the QUEUE and PASS are a valid combination.
*   If TRUE is returned, then QCONN will be left the handle open on the user's
*   mail queue for read.  USER_OK is set to the same value as the function
*   return value.
}
function authenticate                  {determine whether user if valid}
  :boolean;                            {TRUE if user is valid, FALSE if not}

var
  stat: sys_err_t;

label
  abort;

begin
  authenticate := false;               {init to user authentication failed}
  user_ok := false;
  conn_ok := false;

  smtp_queue_read_open (               {try to open mail queue for read}
    queue,                             {generic queue name (user name)}
    mem_p^,                            {parent memory context for queue read state}
    qconn,                             {returned connection handle for reading queue}
    stat);
  if sys_error(stat) then return;      {assume no queue of this name}

  if not qconn.opts.pop3               {this mail queue not enabled for POP3 ?}
    then goto abort;
  if not string_equal (pass, qconn.opts.pswdget) {password doesn't match ?}
    then goto abort;

  authenticate := true;                {everything looks right}
  user_ok := true;
  conn_ok := true;
  return;                              {return with TRUE}

abort:                                 {jump here on failure with QCONN open}
  smtp_queue_read_close (qconn, stat); {try to close our use of this mail queue}
  end;
{
******************************************************************************
*
*   Local subroutine QUEUE_INVENTORY
*
*   Make list of waiting outgoing mail messages in this queue.  The mail queue
*   must already be open for read with handle QCONN.  This routine sets
*   MSG_AR_P, N_MSG, SIZE_ALL, and entries 1 thru N_MSG of MSG_AR_P^.
}
procedure queue_inventory;

var
  finfo: file_info_t;                  {scratch info about a file}
  stat: sys_err_t;

label
  loop_ent, eoq;

begin
  util_mem_grab (                      {alloc entry for each possible msg in queue}
    sizeof(msg_ar_p^[1]) * max(qconn.list_ents.n, 1), {amount of memory needed}
    mem_p^,                            {parent memory context}
    false,                             {allocate from pool, if possible}
    msg_ar_p);                         {returned pointer to new messages array}
  n_msg := 0;                          {init number of entries in messages array}
  size_all := 0;                       {init total size of all messages in array}

loop_ent:                              {back here each new message in queue}
  smtp_queue_read_ent (                {try to open next message in queue}
    qconn,                             {connection handle to mail queue}
    to_list_p,                         {returned pointing to destination addresses}
    mconn_p,                           {returned pnt to message file conn handle}
    stat);
  if sys_stat_match (email_subsys_k, email_stat_queue_end_k, stat) {exhausted queue ?}
    then goto eoq;
  if sys_error_check (stat, 'email', 'email_queue_entry_read_next', nil, 0)
    then goto eoq;

  n_msg := n_msg + 1;                  {make messages list entry for this message}
  msg_ar_p^[n_msg].n := qconn.list_ents.curr; {save index number for this message}
  msg_ar_p^[n_msg].delete := false;    {init to message not marked for deletion}

  file_info (                          {try to get length of mail message file}
    mconn_p^.tnam,                     {name of file inquiring about}
    [file_iflag_len_k],                {all we want is file length}
    finfo,                             {returned info about file}
    stat);
  if sys_error(stat)
    then begin                         {couldn't get necessary info about msg file}
      n_msg := n_msg - 1;              {delete this messages array entry}
      end
    else begin                         {we got message file size}
      msg_ar_p^[n_msg].size := finfo.len; {save message size in array entry}
      size_all := size_all + finfo.len; {update combined size of all message files}
      end
    ;

  smtp_queue_read_ent_close (          {close this queue entry for now}
    qconn,                             {handle to mail queue connection}
    [],                                {no special operations on close}
    stat);
  goto loop_ent;                       {back to process next queue entry}
{
*   The end of the mail message queue was reached.
}
eoq:
  n_ndel := n_msg;                     {init number of non-deleted messages}
  size_ndel := size_all;               {init total size of non-deleted messages}
  end;
{
******************************************************************************
*
*   Local subroutine TIME_STRING (S)
*
*   Return the current time in YYYY/MM/DD.HH:MM:SS format.
}
procedure time_string (                {get current date/time string}
  in out  s: univ string_var_arg_t);   {returned in YYYY/MM/DD.HH:MM:SS format}
  val_param;

var
  tzone: sys_tzone_k_t;                {our time zone}
  hours_west: real;                    {hours west of CUT}
  daysave: sys_daysave_k_t;            {daylight savings time strategy}
  date: sys_date_t;                    {expanded date/time descriptor}
  tk: string_var80_t;                  {scratch token}
  stat: sys_err_t;                     {completion status code}

begin
  tk.max := size_char(tk.str);         {init local var string}
  tk.len := 0;
  s.len := 0;                          {init return string to empty}

  sys_timezone_here (                  {get info about our time zone}
    tzone, hours_west, daysave);

  sys_clock_to_date (                  {make date/time from system clock}
    sys_clock,                         {the time to convert}
    tzone,                             {time zone ID}
    hours_west,                        {hours west of coor univ time}
    daysave,                           {daylight savings strategy}
    date);                             {returned expanded date/time descriptor}

  sys_date_string (date, sys_dstr_year_k, 4, s, stat); {init string with year}
  string_append1 (s, '/');
  sys_date_string (date, sys_dstr_mon_k, 2, tk, stat); {add month number}
  string_append (s, tk);
  string_append1 (s, '/');
  sys_date_string (date, sys_dstr_day_k, 2, tk, stat); {add day number}
  string_append (s, tk);
  string_append1 (s, '.');
  sys_date_string (date, sys_dstr_hour_k, 2, tk, stat); {add hour}
  string_append (s, tk);
  string_append1 (s, ':');
  sys_date_string (date, sys_dstr_min_k, 2, tk, stat); {add minute}
  string_append (s, tk);
  string_append1 (s, ':');
  sys_date_string (date, sys_dstr_sec_k, 2, tk, stat); {add second}
  string_append (s, tk);
  end;
{
******************************************************************************
*
*   Start of main program.
}
begin
  debug_inet := 0;                     {init to default state}
  %debug; debug_inet := 10;            {default to max debug level when debugging}
  debug_smtp := debug_inet;
{
*   Process command line arguments.
}
  string_cmline_init;                  {init for reading command line}

loop_opts:                             {back here each new command line option}
  string_cmline_token (opt, stat);     {get next command line option}
  if string_eos(stat) then goto done_opts; {exhausted command line ?}
  sys_error_abort (stat, 'string', 'cmline_opt_err', nil, 0);
  string_upcase (opt);                 {make upper case for keyword matching}
  string_tkpick80 (opt,                {pick option name from list}
    '-DEBUG',
    pick);                             {number of option picked from list}
  case pick of                         {which command line option is this ?}
{
*   -DEBUG level
}
1: begin
  string_cmline_token_int (debug_inet, stat);
  debug_inet := max(min(debug_inet, 10), 0); {clip to legal range}
  debug_smtp := debug_inet;
  end;
{
*   Unrecognized command line option.
}
otherwise
    string_cmline_opt_bad;
    end;

  string_cmline_parm_check (stat, opt); {abort on parameter error}
  goto loop_opts;                      {back for next command line option}
done_opts:                             {done reading the command line}
{
*   Done with command line.
*
*   Init local state.
}
  time :=                              {make time for save IP to be stale}
    sys_clock_sub (
      sys_clock,                       {start with the current time}
      sys_clock_from_fp_rel (ip_rej_sec + 1.0) {back enough to guarantee stale}
      );
  for ii := 0 to ipsave_last do begin  {loop over the list of saved connection attempts}
    connlist[ii].ip := 0;              {init to invalid IP address}
    connlist[ii].time := time;         {set time to indicate IP address stale anyway}
    end;
  connext := 0;                        {init where to store next connection attempt}
{
*   Establish internet server.
}
  file_create_inetstr_serv (           {create internet server port}
    sys_sys_inetnode_any_k,            {respond to any addresses this node has}
    pop3_port_k,                       {request official pop3 server port number}
    serv,                              {returned handle to new server port}
    stat);
  if sys_error(stat)
    then begin                         {assume couldn't get our desired port}
      file_create_inetstr_serv (       {try again letting system pick port number}
        sys_sys_inetnode_any_k,        {respond to any addresses this node has}
        sys_sys_inetport_unspec_k,     {let system pick port number}
        serv,                          {returned handle to new server port}
        stat);
      sys_error_abort (stat, 'file', 'create_server', nil, 0);
      ii := serv.port;
      sys_msg_parm_int (msg_parm[1], ii);
      sys_message_parms ('email', 'pop3_server_port_nstd', msg_parm, 1);
      end
    else begin                         {we successfully created server}
      ii := serv.port;
      sys_msg_parm_int (msg_parm[1], ii);
      sys_message_parms ('email', 'pop3_server_port_normal', msg_parm, 1);
      end
    ;

  mem_p := nil;                        {init to no client mem context allocated}
{
*   Back here to wait for each new client connection.
}
loop_server:                           {back here for each new client}
{
*   Initialize the state for handling the next client.
}
  if mem_p <> nil then begin           {still have mem context from previous client ?}
    util_mem_context_del (mem_p);      {deallocate dynamic mem for previous client}
    end;

  queue.len := 0;                      {init to no user name given}
  pass.len := 0;                       {init to no password given}
  user_ok := false;                    {init to user not authenticated}
  conn_ok := false;                    {init to not a valid connection request}
  reminfo := false;                    {init to info on remote client not valid}
  show_abort := true;                  {init to show message on abort}
{
*   Wait for a client to connect.
}
  file_open_inetstr_accept (           {wait for a client to connect to us}
    serv,                              {handle to internet server port}
    conn_client,                       {returned handle to new stream connection}
    stat);
  if sys_error_check (stat, 'file', 'inetstr_accept', nil, 0)
    then goto loop_server;             {try next client on error}
  connt := sys_clock;                  {save time of the connection request}
  file_inetstr_tout_rd (conn_client, smtp_tout_rd_k); {set read timeout}
  file_inetstr_tout_wr (conn_client, smtp_tout_wr_k); {set write timeout}

  file_inetstr_info_remote (           {get info about the client}
    conn_client,                       {connection inquiring about}
    rem_adr,                           {client node address}
    rem_port,                          {port number on client node}
    stat);
  if sys_error_check (stat, 'file', 'inet_info_remote', nil, 0)
    then goto abort_client;            {abort this client on error}
  reminfo := true;                     {indicate REM_xxx data is now valid}
{
*   Check for whether to ignore this client.  To quickly reject arbitrary
*   connection requests, a new connection is rejected if there was a failed
*   request from the same IP address within IP_REJ_SEC seconds.  The list of
*   recent failed connection requests is in CONNLIST.  A failed connection
*   request is one that does not result in a authenticated user.
*
*   CONNEXT is the CONNLIST index of where to write the next connection.
*   CONNLIST is a circular buffer.  To search saved connection requests in
*   newest to oldest order therefore starts at CONNEXT-1 and continues until
*   reaching CONNEXT.  Note that this decrement is performed by wrapping back
*   from 0 to IPSAVE_LAST.
}
  ii := connext - 1;                   {init index to most recent saved entry}
  while true do begin                  {loop over entries, newest to oldest}
    if ii < 0 then ii := ipsave_last;  {wrap back to end of the array ?}
    if rem_adr <> connlist[ii].ip then goto next_listent; {not same client machine ?}
    dt := sys_clock_to_fp2 (sys_clock_sub ( {make time since last failed connection request}
      connt,                           {time of this connection}
      connlist[ii].time));             {time of last failed attempt}
    if dt <= ip_rej_sec then begin     {too recent, dirtbag detected ?}
      time_string (buf);               {init message with current time string}
      string_appends (buf, '  Rejecting repeat offender on '(0));
      string_f_inetadr (tk, rem_adr);
      string_append (buf, tk);
      string_appends (buf, ' at port '(0));
      string_f_int (tk, rem_port);
      string_append (buf, tk);
      writeln (buf.str:buf.len);
      show_abort := false;             {don't bother showing additional abort message}
      goto abort_client;
      end;
next_listent:                          {advance to the next older list entry}
    if ii = ipsave_last then exit;     {already at oldest list entry ?}
    ii := ii - 1;                      {to next older entry, will wrap above}
    end;                               {back to process this next older entry}

  if debug_inet < 5 then begin         {show remote system info ?}
    time_string (buf);                 {init output line with current date/time}
    string_appends (buf, '  New client on '(0));
    string_f_inetadr (tk, rem_adr);
    string_append (buf, tk);
    string_appends (buf, ' at port '(0));
    string_f_int (tk, rem_port);
    string_append (buf, tk);
    writeln (buf.str:buf.len);
    end;
{
*   Send initial greeting.
}
  string_vstring (buf, '+OK Logged access by '(0), -1);
  string_f_inetadr (tk, rem_adr);
  string_append (buf, tk);
  string_appends (buf, ' from port '(0));
  string_f_int (tk, rem_port);
  string_append (buf, tk);
  inet_vstr_crlf_put (buf, conn_client, stat);
  if sys_error_check (stat, 'file', 'write_inetstr_server', nil, 0)
    then goto abort_client;

  util_mem_context_get (               {create private mem handle for this client}
    util_top_mem_context,              {parent memory context}
    mem_p);                            {returned pointer to new memory context}
{
*   Back here each new client command.
}
loop_cmd:
  inet_vstr_crlf_get (buf, conn_client, stat); {get next command from client}
  if sys_error_check (stat, 'file', 'read_inetstr_server', nil, 0)
    then goto abort_client;            {try next client on error}
  string_unpad (buf);                  {delete trailing spaces from client command}
  p := 1;                              {init command buffer parse index}
  string_token (buf, p, opt, stat);    {parse command name from command buffer}
  sys_error_none (stat);               {ignore errors, will be caught as syntax err}
  string_upcase (opt);                 {make upper case for token matching}
  string_tkpick80 (opt,                {pick command name token from list}
    'USER PASS STAT LIST RETR DELE NOOP RSET QUIT'(0),
    pick);                             {number of keyword picked from list}
  case pick of                         {which command is it ?}
{
************************
*
*   USER name
}
1: begin
  if user_ok                           {not in AUTHORIZATION state ?}
    then goto wrong_state;             {we are in wrong state for this command}
  string_token (buf, p, queue, stat);  {extract user name as generic queue name}
  if sys_error(stat) then goto err_parm;
  string_downcase (queue);             {user names are case-insentitive}
  inet_cstr_crlf_put ('+OK'(0), conn_client, stat);
  if sys_error_check (stat, 'email', 'pop3_user_ok', nil, 0)
    then goto abort_client;
  end;
{
************************
*
*   PASS password
}
2: begin
  if user_ok                           {not in AUTHORIZATION state ?}
    then goto wrong_state;             {we are in wrong state for this command}
  while                                {advance to first non-blank after cmd name}
      (p < buf.len) and
      (buf.str[p] = ' ')
      do begin
    p := p + 1;
    end;
  string_substr (buf, p, buf.len, pass); {extract password string}
  if queue.len <= 0 then begin
    inet_cstr_crlf_put (
      '-ERR No user name previously specified.'(0), conn_client, stat);
    if sys_error_check (stat, 'email', 'pop3_pass_nuser', nil, 0)
      then goto abort_client;
    goto done_cmd;
    end;
  time_string (parm);
  string_appends (parm, '    User '(0));
  string_append (parm, queue);

  if not authenticate then begin       {user is a phony ?}
    string_appends (parm, ' denied.'(0));
    writeln (parm.str:parm.len);
    sys_wait (2.0);                    {prevent rapid retry after break in attempt}
    inet_cstr_crlf_put ('-ERR Access denied.'(0), conn_client, stat);
    if sys_error_check (stat, 'email', 'pop3_pass_denied', nil, 0)
      then goto abort_client;
    goto done_cmd;
    end;
  {
  *   This user is valid.
  }
  string_appends (parm, ' accepted.'(0));
  writeln (parm.str:parm.len);
  queue_inventory;                     {take inventory of waiting mail messages}
  inet_cstr_crlf_put ('+OK Access granted.'(0), conn_client, stat);
  if sys_error_check (stat, 'email', 'pop3_pass_accepted', nil, 0)
    then goto abort_client;
  end;
{
************************
*
*   STAT
}
3: begin
  if not user_ok                       {not in TRANSACTION state ?}
    then goto wrong_state;             {we are in wrong state for this command}

  string_vstring (parm, '+OK '(0), -1); {init response string}
  string_f_int (tk, n_ndel);
  string_append (parm, tk);            {number of messages in queue}
  string_append1 (parm, ' ');
  string_f_int (tk, size_ndel);
  string_append (parm, tk);            {combined size of all messages in queue}

  inet_vstr_crlf_put (parm, conn_client, stat); {send response string}
  if sys_error_check (stat, 'email', 'pop3_stat_response', nil, 0)
    then goto abort_client;
  end;
{
************************
*
*   LIST [message_number]
}
4: begin
  if not user_ok                       {not in TRANSACTION state ?}
    then goto wrong_state;             {we are in wrong state for this command}
  string_token_int (buf, p, ii, stat); {get message number in II, if present}

  if string_eos(stat) then begin       {no message number, list all messages ?}
    inet_cstr_crlf_put ('+OK'(0), conn_client, stat); {send initial response line}
    if sys_error_check (stat, 'email', 'pop3_list_nparm', nil, 0)
      then goto abort_client;
    for ii := 1 to n_msg do begin      {once for each message in list}
      if msg_ar_p^[ii].delete then next; {ignore messages marked for deletion}
      string_f_int (parm, ii);         {init response line with message number}
      string_append1 (parm, ' ');
      string_f_int (tk, msg_ar_p^[ii].size);
      string_append (parm, tk);        {append message length}
      inet_vstr_crlf_put (parm, conn_client, stat); {send line for this message}
      if sys_error_check (stat, 'email', 'pop3_list_nparm_msg', nil, 0)
        then goto abort_client;
      end;                             {back for next message in list}
    goto done_multiline;               {close multiline response, back for next cmd}
    end;

  if sys_error(stat) then goto err_parm; {error getting parameter to LIST command ?}

  if                                   {bad message number ?}
      (ii < 1) or (ii > n_msg) or else {message number out of range ?}
      (msg_ar_p^[ii].delete)           {message marked for deletion ?}
      then begin
    inet_cstr_crlf_put ('-ERR Bad message number.'(0), conn_client, stat);
    if sys_error_check (stat, 'email', 'pop3_list_n_bad', nil, 0)
      then goto abort_client;
    goto done_cmd;
    end;

  string_vstring (parm, '+OK '(0), -1); {init response string}
  string_f_int (tk, ii);
  string_append (parm, tk);            {append message number}
  string_append1 (parm, ' ');
  string_f_int (tk, msg_ar_p^[ii].size);
  string_append (parm, tk);            {append message size}
  inet_vstr_crlf_put (parm, conn_client, stat); {send response}
  if sys_error_check (stat, 'email', 'pop3_list_n_ok', nil, 0)
    then goto abort_client;
  end;
{
************************
*
*   RETR message_number
}
5: begin
  if not user_ok                       {not in TRANSACTION state ?}
    then goto wrong_state;             {we are in wrong state for this command}

  string_token_int (buf, p, ii, stat); {get message number in II}
  if sys_error(stat) then goto err_parm;
  if                                   {bad message number ?}
      (ii < 1) or (ii > n_msg) or else {message number out of range ?}
      (msg_ar_p^[ii].delete)           {message marked for deletion ?}
      then begin
    inet_cstr_crlf_put ('-ERR Bad message number.'(0), conn_client, stat);
    if sys_error_check (stat, 'email', 'pop3_retr_n_bad', nil, 0)
      then goto abort_client;
    goto done_cmd;
    end;

  string_list_pos_abs (                {position to open requested message next}
    qconn.list_ents,                   {list to set position in}
    msg_ar_p^[ii].n);                  {entry number to position to}
  smtp_queue_read_ent (                {open this queue entry for read}
    qconn,                             {handle to mail queue read connection}
    to_list_p,                         {returned pointing to destination addresses}
    mconn_p,                           {returned pointing to msg file conn handle}
    stat);
  if sys_error_check (stat, 'email', 'email_queue_entry_read_next', nil, 0)
    then goto abort_client;

  inet_cstr_crlf_put ('+OK'(0), conn_client, stat); {send initial response line}
  if sys_error_check (stat, 'email', 'pop3_retr_ok', nil, 0)
    then goto abort_client;

  sys_msg_parm_vstr (msg_parm[1], mconn_p^.tnam); {set parm for error message}
loop_retr:                             {back here each new mail message line}
  file_read_text (mconn_p^, buf, stat); {try to read next line from message file}
  if file_eof(stat) then goto eof_retr; {hit end of mail message file ?}
  if sys_error_check (stat, 'email', 'email_msg_in_read', msg_parm, 1)
    then goto retr_abort;

  if (buf.len >= 1) and (buf.str[1] = '.') then begin {line starts with "." ?}
    buf.len := min(buf.max, buf.len + 1); {new length after "." added to front}
    for ii := buf.len downto 2 do begin {once for each char to move right}
      buf.str[ii] := buf.str[ii - 1];  {copy this character right one column}
      end;
    end;                               {done dealing with leading termination char}
  inet_vstr_crlf_put (buf, conn_client, stat); {send this mail message line}
  if sys_error_check (stat, 'email', 'pop3_retr_line', nil, 0)
    then goto retr_abort;
  goto loop_retr;                      {back for next line in mail message}

eof_retr:                              {end of mail message file encountered}
  smtp_queue_read_ent_close (          {close this mail queue entry}
    qconn,                             {handle to mail queue connection}
    [],                                {don't do special processing on close}
    stat);
  if sys_error_check (stat, 'email', 'email_queue_entry_read_close', msg_parm, 1)
    then goto abort_client;
  goto done_multiline;                 {close multiline response, back for next cmd}

retr_abort:                            {error occurred with queue entry open}
  smtp_queue_read_ent_close (          {close this mail queue entry}
    qconn,                             {handle to mail queue connection}
    [],                                {don't do special processing on close}
    stat);
  if sys_error_check (stat, 'email', 'pop3_retr_abort', msg_parm, 1)
    then goto abort_client;
  end;
{
************************
*
*   DELE message_number
}
6: begin
  if not user_ok                       {not in TRANSACTION state ?}
    then goto wrong_state;             {we are in wrong state for this command}

  string_token_int (buf, p, ii, stat); {get message number in II}
  if sys_error(stat) then goto err_parm;
  if                                   {bad message number ?}
      (ii < 1) or (ii > n_msg) or else {message number out of range ?}
      (msg_ar_p^[ii].delete)           {message marked for deletion ?}
      then begin
    inet_cstr_crlf_put ('-ERR Bad message number.'(0), conn_client, stat);
    if sys_error_check (stat, 'email', 'pop3_dele_n_bad', nil, 0)
      then goto abort_client;
    goto done_cmd;
    end;

  msg_ar_p^[ii].delete := true;        {mark message for deletion}
  n_ndel := n_ndel - 1;                {count one less undeleted message}
  size_ndel := size_ndel - msg_ar_p^[ii].size; {update size of remaining messages}

  inet_cstr_crlf_put ('+OK Message marked for deletion.'(0), conn_client, stat);
  if sys_error_check (stat, 'email', 'pop3_dele_ok', nil, 0)
    then goto abort_client;
  end;
{
************************
*
*   NOOP
}
7: begin
  if not user_ok                       {not in TRANSACTION state ?}
    then goto wrong_state;             {we are in wrong state for this command}

  inet_cstr_crlf_put ('+OK'(0), conn_client, stat);
  if sys_error_check (stat, 'email', 'pop3_noop_ok', nil, 0)
    then goto abort_client;
  end;
{
************************
*
*   RSET
}
8: begin
  if not user_ok                       {not in TRANSACTION state ?}
    then goto wrong_state;             {we are in wrong state for this command}

  for ii := 1 to n_msg do begin        {once for each message in our list}
    if not msg_ar_p^[ii].delete then next; {this message isn't marked for deletion ?}
    msg_ar_p^[ii].delete := false;     {reset to not deleted}
    n_ndel := n_ndel + 1;              {count one more non-deleted message}
    size_ndel := size_ndel + msg_ar_p^[ii].size; {update size of non-deleted messages}
    end;                               {back to check next message list entry}

  inet_cstr_crlf_put ('+OK All messages reset to not-deleted.'(0), conn_client, stat);
  if sys_error_check (stat, 'email', 'pop3_rset_ok', nil, 0)
    then goto abort_client;
  end;
{
************************
*
*   QUIT
}
9: begin
  if user_ok then begin                {we have mail queue open ?}

    for ii := 1 to n_msg do begin      {once for each mail message in the list}
      if not msg_ar_p^[ii].delete then next; {this message not marked for deletion ?}
      string_list_pos_abs (            {position to open this message next}
        qconn.list_ents,               {list to set position in}
        msg_ar_p^[ii].n);              {entry number to position to}
      smtp_queue_read_ent (            {open this queue entry for read}
        qconn,                         {handle to mail queue read connection}
        to_list_p,                     {returned pointing to destination addresses}
        mconn_p,                       {returned pointing to msg file conn handle}
        stat);
      if sys_error_check (stat, 'email', 'pop3_quit_del_open', nil, 0)
        then goto abort_client;
      smtp_queue_read_ent_close (      {close this mail queue entry}
        qconn,                         {handle to mail queue connection}
        [smtp_qrclose_del_k],          {delete this queue entry}
        stat);
      if sys_error(stat) then begin    {error on deleting queue entry ?}
        sys_msg_parm_vstr (msg_parm[1], qconn.conn_m.tnam);
        sys_error_print (stat, 'email', 'email_queue_entry_read_close', msg_parm, 1);
        goto abort_client;
        end;
      end;                             {back to check out next messages list entry}

    smtp_queue_read_close (qconn, stat); {close our connection to the mail queue}
    user_ok := false;                  {indicate queue no longer open}
    if sys_error(stat) then begin      {error on closing queue ?}
      sys_msg_parm_vstr (msg_parm[1], qconn.qdir);
      sys_error_print (stat, 'email', 'email_queue_read_close', msg_parm, 1);
      goto abort_client;
      end;
    end;                               {done cleaing up mail queue state}

  inet_cstr_crlf_put ('+OK Closing connection.'(0), conn_client, stat);
  if sys_error_check (stat, 'email', 'pop3_quit_ok', nil, 0)
    then goto abort_client;

  time_string (parm);
  string_appends (parm, '    Closed.');
  writeln (parm.str:parm.len);
  file_close (conn_client);            {close connection to client}
  goto loop_server;                    {back to wait for next client connect request}
  end;
{
************************
*
*   Unrecognized command.
}
otherwise
    inet_cstr_crlf_put ('-ERR unrecognized command.'(0), conn_client, stat);
    if sys_error(stat) then begin
      sys_msg_parm_vstr (msg_parm[1], opt); {command name}
      sys_error_print (stat, 'email', 'pop3_command_bad', msg_parm, 1);
      goto abort_client;
      end;
    end;                               {end of command keyword cases}
{
************************
*
*   Done processing the current command.
}
done_cmd:
  if sys_error(stat) then begin        {error, should have been handled above ?}
    sys_msg_parm_vstr (msg_parm[1], opt); {command name}
    sys_error_print (stat, 'email', 'pop3_command_end', msg_parm, 1);
    goto abort_client;
    end;
  goto loop_cmd;
{
*   Jump here to terminate a multi-line response and go back to process the
*   next command.
}
done_multiline:
  inet_cstr_crlf_put ('.'(0), conn_client, stat); {terminate multi-line response}
  if sys_error(stat) then begin
    sys_msg_parm_vstr (msg_parm[1], opt); {command name}
    sys_error_print (stat, 'email', 'pop3_multiline_end', msg_parm, 1);
    goto abort_client;
    end;
  goto done_cmd;
{
*   The current command is not valid at the this time.  The server has either
*   issued a transaction command in authorization state, or an authorization
*   command in transaction state.  We are in transaction state if and only if
*   USER_OK is TRUE.
}
wrong_state:                           {jump here if command invalid for curr state}
  string_vstring (parm, '-ERR Command '(0), -1);
  string_append (parm, opt);
  string_appends (parm, ' is not valid in '(0));
  if user_ok
    then begin                         {we are in TRANSACTION state}
      string_appends (parm, 'TRANSACTION'(0));
      end
    else begin                         {we are in AUTHORIZATION state}
      string_appends (parm, 'AUTHORIZATION'(0));
      end
    ;
  string_appends (parm, ' state.'(0));
  inet_vstr_crlf_put (parm, conn_client, stat); {send response to client}
  if sys_error(stat) then begin
    sys_msg_parm_vstr (msg_parm[1], opt); {command name}
    sys_error_print (stat, 'email', 'pop3_state_bad', msg_parm, 1);
    goto abort_client;
    end;
  goto done_cmd;
{
*   Jump here on error with parameters for the current command.
}
err_parm:
  inet_cstr_crlf_put ('-ERR Bad or missing command parameter'(0), conn_client, stat);
  if sys_error(stat) then begin
    sys_msg_parm_vstr (msg_parm[1], opt); {command name}
    sys_error_print (stat, 'email', 'pop3_parm_bad', msg_parm, 1);
    goto abort_client;
    end;
  goto loop_cmd;                       {back for next client command}
{
*   Jump here on fatal client-related error.
}
abort_client:
  if debug_inet >= 10 then writeln ('At ABORT_CLIENT.');

  if user_ok then begin                {mail queue connection open ?}
    if debug_inet >= 10 then writeln ('Calling SMTP_QUEUE_READ_CLOSE.');
    smtp_queue_read_close (qconn, stat); {try to close mail queue connection}
    sys_msg_parm_vstr (msg_parm[1], qconn.qdir);
    sys_error_print (stat, 'email', 'email_queue_read_close', msg_parm, 1);
    end;

  if (not conn_ok) and reminfo then  begin {log this as a bad connection ?}
    connlist[connext].ip := rem_adr;   {save dirtbag's IP address}
    connlist[connext].time := connt;   {save time of the connect attempt}
    connext := connext + 1;            {update where to write next entry}
    if connext > ipsave_last then begin {wrap from end of array back to start}
      connext := 0;
      end;
    end;

  if (debug_inet >= 5) or show_abort then begin
    time_string (parm);
    string_appends (parm, '    Aborted.');
    writeln (parm.str:parm.len);
    end;

  if debug_inet >= 10 then writeln ('Calling FILE_CLOSE on client stream.');
  file_close (conn_client);            {close connection to client}
  if debug_inet >= 10 then writeln ('Going back to LOOP_SERVER.');
  goto loop_server;                    {back to wait for next client connect request}
  end.
