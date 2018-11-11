{   Program SMTP <options>
*
*   Perform SMTP (Simple Mail Transfer Protocol).  This program can perform
*   several roles, depending on the command line options.
}
program smtp;
%include 'base.ins.pas';
%include 'email.ins.pas';

const
  max_msg_parms = 4;                   {max parameters we can pass to a message}

type
  mode_t = (                           {major program mode}
    mode_client_k,                     {SMTP client}
    mode_server_k,                     {SMTP server}
    mode_enqueue_k);                   {add mail message to mail queue}

var
  outq,                                {specific output queue name}
  inq:                                 {specific input queue name}
    %include '(cog)lib/string_leafname.ins.pas';
  fnam_msg,                            {pathname of mail message file}
  qdir,                                {true name of Cognivision SMTPQ directory}
  tnam:                                {scratch system path name}
    %include '(cog)lib/string_leafname.ins.pas';
  str:                                 {long scartch string}
    %include '(cog)lib/string8192.ins.pas';
  pgm_mode: mode_t;                    {top level program mode}
  conn: file_conn_t;                   {scratch file connection handle}
  conn_c, conn_a, conn_m: file_conn_t; {mail queue file connections}
  finfo: file_info_t;                  {info about a file}
  list_to: string_list_t;              {list of mail destination addresses}
  qopts: smtp_queue_options_t;         {info from queue OPTIONS files}
  port: sys_inet_port_id_t;            {preferred port to establish server on}
  serv: file_inet_port_serv_t;         {handle to internet server port}
  anyport: boolean;                    {TRUE on -ANYPORT command line opotion}
  sclient: boolean;                    {only one client allowed at a time}
  id_thread: sys_sys_thread_id_t;      {ID for separate thread}
  client_p: smtp_client_p_t;           {info about client for thread routine}
  ii: sys_int_machine_t;               {scratch integer and loop counter}
  b: boolean;                          {scratch boolean}
  cmdopts:                             {list of command line options}
    %include '(cog)lib/string256.ins.pas';

  pick: sys_int_machine_t;             {number of token picked from list}
  opt:                                 {command line option name}
    %include '(cog)lib/string32.ins.pas';
  msg_parm:                            {parameter references for messages}
    array[1..max_msg_parms] of sys_parm_msg_t;
  stat: sys_err_t;                     {completion status code}
  stat2: sys_err_t;                    {to avoid corrupting STAT from earlier err}
{
********************************************************************************
*
*   Local subroutine ADD_OPT (NAME)
*
*   Add the indicated name to the end of the list of command line options.
}
procedure add_opt (                    {add one command line option}
  in      name: string);               {name to add, blank padded or NULL term}
  val_param; internal;

var
  tk: string_var32_t;                  {option name, upper case}

begin
  tk.max := size_char(tk.str);         {init local var string}

  string_vstring (tk, name, size_char(name)); {make var string copy of NAME}
  string_upcase (tk);                  {make sure it is upper case}
  string_append_token (cmdopts, tk);   {add to end of command line options list}
  end;
{
********************************************************************************
*
*   Start of main routine.
}
label
  loop_opts, loop_to, loop_adrfile, done_adrfile, done_opts,
  loop_queues, done_queues, loop_server,
  loop_copy_m, done_copy_m, leave_enqueue;

begin
  sys_cognivis_dir ('smtpq'(0), qdir); {get full name of mail queues directory}

  outq.len := 0;                       {init to default state}
  inq.len := 0;
  pgm_mode := mode_server_k;
  string_list_init (list_to, util_top_mem_context);
  fnam_msg.len := 0;
  debug_inet := 0;
  debug_smtp := 0;
  port := smtp_port_k;                 {init desired server port to SMTP standard}
  anyport := false;
  sclient := false;
  smtp_client_init;                    {init CLIENT module}

  string_cmline_init;                  {init for reading command line}

  add_opt ('-CLIENT');                 {1}
  add_opt ('-SERVER');                 {2}
  add_opt ('-OUTQ');                   {3}
  add_opt ('-INQ');                    {4}
  add_opt ('-ENQUEUE');                {5}
  add_opt ('-TO');                     {6}
  add_opt ('-ADRFILE');                {7}
  add_opt ('-MSG');                    {8}
  add_opt ('-MUTE');                   {9}
  add_opt ('-DEBUG');                  {10}
  add_opt ('-ANYPORT');                {11}
  add_opt ('-1');                      {12}
  add_opt ('-PORT');                   {13}

loop_opts:                             {back here each new command line option}
  string_cmline_token (opt, stat);     {get next command line option}
  if string_eos(stat) then goto done_opts; {exhausted command line ?}
  sys_error_abort (stat, 'string', 'cmline_opt_err', nil, 0);
  string_upcase (opt);                 {make upper case for keyword matching}
  string_tkpick (opt, cmdopts, pick);  {pick option name from list}
  case pick of                         {which command line option is this ?}
{
*   -CLIENT
}
1: begin
  pgm_mode := mode_client_k;
  end;
{
*   -SERVER
}
2: begin
  pgm_mode := mode_server_k;
  end;
{
*   -OUTQ <queue name>
}
3: begin
  string_cmline_token (outq, stat);
  end;
{
*   -INQ <queue name>
}
4: begin
  string_cmline_token (inq, stat);
  end;
{
*   -ENQUEUE
}
5: begin
  pgm_mode := mode_enqueue_k;
  end;
{
*   -TO <adr1> ... <adrN>
}
6: begin
loop_to:                               {back here each new target address}
  string_cmline_token (str, stat);     {get next command line token}
  if string_eos(stat) then goto done_opts; {hit end of command line ?}
  string_cmline_parm_check (stat, opt); {abort on parameter error}
  list_to.size := str.len;             {create new target address list entry}
  string_list_line_add (list_to);
  string_copy (str, list_to.str_p^);   {copy address into list entry}
  goto loop_to;                        {back for next command line token}
  end;
{
*   -ADRFILE <addresses list file name>
}
7: begin
  string_cmline_token (tnam, stat);    {get addresses list file name}
  string_cmline_parm_check (stat, opt); {abort on parameter error}
  file_open_read_text (tnam, '', conn, stat); {open adresses list file}
  sys_msg_parm_vstr (msg_parm[1], conn.tnam);
loop_adrfile:                          {back here each new addresses list file line}
  file_read_text (conn, str, stat);    {read next line from addresses list file}
  if file_eof(stat) then goto done_adrfile; {hit end of file ?}
  sys_error_abort (stat, 'email', 'email_adrfile_read', msg_parm, 1);
  string_unpad (str);                  {truncate trailing blanks}
  list_to.size := str.len;             {create new target address list entry}
  string_list_line_add (list_to);
  string_copy (str, list_to.str_p^);   {copy address into list entry}
  goto loop_adrfile;                   {back for next address from adr list file}
done_adrfile:                          {done reading addresses list file}
  file_close (conn);                   {close file}
  end;
{
*   -MSG <mail message file name>
}
8: begin
  string_cmline_token (fnam_msg, stat);
  end;
{
*   -MUTE
}
9: begin
  debug_inet := 0;
  debug_smtp := 0;
  end;
{
*   -DEBUG level
}
10: begin
  string_cmline_token_int (debug_inet, stat);
  debug_inet := max(min(debug_inet, 10), 0); {clip to legal range}
  debug_smtp := debug_inet;
  end;
{
*   -ANYPORT
}
11: begin
  anyport := true;
  end;
{
*   -1
}
12: begin
  sclient := true;
  end;
{
*   -PORT port
}
13: begin
  string_cmline_token_int (ii, stat);
  port := ii;
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

  case pgm_mode of                     {what is top level program mode ?}
{
*************************************************************
*
*   Program mode is CLIENT.
}
mode_client_k: begin
  if outq.len = 0
{
*   Send mail from all queues.
}
    then begin                         {send from all queues}
      file_open_read_dir (qdir, conn, stat); {open top queue directory for read}
      sys_msg_parm_vstr (msg_parm[1], qdir);
      sys_error_abort (stat, 'file', 'open_dir', msg_parm, 1);
loop_queues:                           {back here each new entry in queues directory}
      file_read_dir (                  {read next directory entry}
        conn,                          {handle to directory open for read}
        [file_iflag_type_k],           {we want to know file type}
        outq,                          {returned directory entry name}
        finfo,                         {returned info about this file}
        stat);
      if file_eof(stat) then goto done_queues; {hit end of directory ?}
      discard(                         {didn't get requested info isn't hard error}
        sys_stat_match (file_subsys_k, file_stat_info_partial_k, stat) );
      if sys_error_check (stat, 'file', 'read_dir', nil, 0)
        then goto loop_queues;
      if                               {this is definately a sub-directory ?}
          (file_iflag_type_k in finfo.flags) and {file type info is valid ?}
          (finfo.ftype = file_type_dir_k) {file type is DIRECTORY ?}
          then begin
        smtp_send_queue (outq, true, inq, stat); {send mail from indicated queue}
        sys_msg_parm_vstr (msg_parm[1], outq);
        if sys_error_check (stat, 'email', 'smtp_send_queue', msg_parm, 1)
          then goto loop_queues;
        end;
      goto loop_queues;                {back to process next directory entry}
done_queues:                           {just hit end of top level queue directory}
      sys_error_none (stat);           {reset error flag}
      file_close (conn);               {close connection to directory}
      end
{
*   Send mail from only one specific queue.
}
    else begin                         {send only from the queue named in OUTQ}
      smtp_send_queue (outq, false, inq, stat); {send mail from indicated queue}
      sys_msg_parm_vstr (msg_parm[1], outq);
      sys_error_print (stat, 'email', 'smtp_send_queue', msg_parm, 1);
      end
    ;
  end;
{
*************************************************************
*
*   Program mode is SERVER.
}
mode_server_k: begin
{
*   Create the server data structures.
}
  file_create_inetstr_serv (           {create internet server port}
    sys_sys_inetnode_any_k,            {respond to any addresses this node has}
    port,                              {request desired port number}
    serv,                              {returned handle to new server port}
    stat);
  if sys_error(stat)
    then begin                         {assume couldn't get our desired port}
      if anyport then begin            {OK to use any port ?}
        file_create_inetstr_serv (     {try again letting system pick port number}
          sys_sys_inetnode_any_k,      {respond to any addresses this node has}
          sys_sys_inetport_unspec_k,   {let system pick port number}
          serv,                        {returned handle to new server port}
          stat);
        end;                           {done handling re-try with any port allowed}
      sys_error_abort (stat, 'file', 'create_server', nil, 0);
      ii := serv.port;
      sys_msg_parm_int (msg_parm[1], ii);
      sys_message_parms ('email', 'smtp_server_port_nstd', msg_parm, 1);
      end
    else begin                         {we successfully created server}
      ii := serv.port;
      sys_msg_parm_int (msg_parm[1], ii);
      sys_message_parms ('email', 'smtp_server_port_normal', msg_parm, 1);
      end
    ;

  client_p := nil;                     {init to no client descriptor allocated}
{
*   Back here to wait for each new client connection.
}
loop_server:                           {back here for each new client}
  if client_p = nil then begin         {no client descriptor ?}
    smtp_client_new (client_p);        {create new client descriptor}
    string_copy (inq, client_p^.inq);  {set specific input queue to use, if any}
    end;

  file_open_inetstr_accept (           {wait for a client to connect to us}
    serv,                              {handle to internet server port}
    client_p^.conn,                    {returned handle to new stream connection}
    stat);
  if sys_error(stat) then begin
    smtp_client_log_stat_str (client_p^, stat, 'Error trying to get next client connection.');
    goto loop_server;
    end;

  if not smtp_client_open (client_p^) then begin {set up descriptor to new connection}
    goto loop_server;                  {connection was closed}
    end;

  if sclient
    then begin                         {only single client at a time allowed}
      smtp_client_thread (client_p^);  {process this client synchronously}
      client_p := nil;                 {thread routine always closes client}
      end
    else begin                         {multiple simultaneous clients allowed}
      sys_thread_create (              {launch separate thread to handle this client}
        sys_threadproc_p_t(addr(smtp_client_thread)), {thread routine}
        sys_int_adr_t(client_p),       {thread routine argument}
        id_thread,                     {ID of newly created thread}
        stat);
      if sys_error(stat) then begin
        smtp_client_log_stat_str (client_p^, stat, 'Error on attempt to launch thread for client.');
        smtp_client_close (client_p);  {close connection to this client}
        goto loop_server;
        end;
      sys_thread_release (id_thread, stat); {release thread resources on thread exit}
      client_p := nil;                 {force creating a new descriptor next time}
      if sys_error(stat) then begin
        smtp_client_log_err (client_p^, stat, 'email', 'smtp_client_thread_release', nil, 0);
        end;
      end
    ;
  goto loop_server;                    {back to wait for next client}
  end;                                 {end of SERVER program mode case}
{
*************************************************************
*
*   Program mode is ENQUEUE.
}
mode_enqueue_k: begin
  if list_to.n <= 0 then begin         {no target addresses ?}
    sys_message_bomb ('email', 'email_adr_none', nil, 0);
    end;
  if fnam_msg.len <= 0 then begin      {no mail message file ?}
    sys_message_bomb ('email', 'email_msg_in_none', nil, 0);
    end;
  if inq.len <= 0 then begin           {no input queue name}
    smtp_queue_opts_get (              {read the top level queue OPTIONS file}
      qdir,                            {name of top level queue directory}
      inq,                             {empty, only read top level OPTIONS file}
      qopts,                           {returned info read from OPTIONS file}
      stat);
    sys_error_abort (stat, '', '', nil, 0);
    if qopts.inq.len > 0
      then begin                       {input queue name found in OPTIONS file}
        string_copy (qopts.inq, inq);
        end
      else begin                       {no input queue file name is available}
        sys_message_bomb ('email', 'email_queue_in_none', nil, 0);
        end
      ;
    end;

  smtp_queue_opts_get (                {get all the options for this specific queue}
    qdir,                              {name of top level queue directory}
    inq,                               {generic name of specific queue}
    qopts,                             {returned info read from OPTIONS file}
    stat);
  sys_error_abort (stat, '', '', nil, 0);

  smtp_queue_create_ent (              {create new entry in mail queue}
    inq,                               {generic mail queue name}
    conn_c,                            {handle to open control file}
    conn_a,                            {handle to open addresses list file}
    conn_m,                            {handle to open mail message file}
    stat);
  sys_msg_parm_vstr (msg_parm[1], inq);
  sys_error_abort (stat, 'email', 'email_queue_entry_create', msg_parm, 1);
{
*   Copy the target addresses into the queue addresses list file.
}
  string_list_pos_abs (list_to, 1);    {init to first address in list}
  sys_msg_parm_vstr (msg_parm[1], conn_a.tnam);
  while list_to.str_p <> nil do begin  {once for each entry in list}
    file_write_text (list_to.str_p^, conn_a, stat); {write this address to file}
    if sys_error_check (stat, 'email', 'email_write_queue_a', msg_parm, 1)
      then goto leave_enqueue;
    string_list_pos_rel (list_to, 1);  {advance to next target address in list}
    end;                               {back to handle this new target address}
{
*   Copy the mail message into the queue message file.
}
  file_open_read_text (fnam_msg, '', conn, stat); {open input message file}
  sys_msg_parm_vstr (msg_parm[1], fnam_msg);
  if sys_error_check (stat, 'email', 'email_msg_in_open', msg_parm, 1)
    then goto leave_enqueue;

  sys_msg_parm_vstr (msg_parm[1], conn.tnam); {parm for EMAIL_MSG_IN_READ}
  sys_msg_parm_vstr (msg_parm[2], conn_m.tnam); {parm for EMAIL_WRITE_QUEUE_M}

loop_copy_m:                           {back here to copy each message file line}
  file_read_text (conn, str, stat);    {read line from input message file}
  if file_eof(stat) then goto done_copy_m; {hit end of input message file ?}
  if sys_error_check (stat, 'email', 'email_msg_in_read', msg_parm[1], 1)
    then goto done_copy_m;
  file_write_text (str, conn_m, stat); {write line to output message file in queue}
  if sys_error_check (stat, 'email', 'email_write_queue_m', msg_parm[2], 1)
    then goto done_copy_m;
  goto loop_copy_m;
done_copy_m:
  file_close (conn);                   {close input message file}

leave_enqueue:                         {common enqueue exit point if queue ent open}
  b := not sys_error(stat);            {set flag to delete entry on error}
  smtp_queue_create_close (            {close queue entry we just created}
    conn_c, conn_a, conn_m,            {connection handles to queue entry files}
    b,                                 {delete entry on any error}
    stat2);
  sys_error_abort (stat2, 'email', 'email_queue_entry_create', nil, 0);
  if sys_error(stat) then sys_bomb;    {bomb program due to earlier error ?}
{
*   Send on all the entries in this queue using a different process, if
*   AUTOSEND is enabled.
}
  smtp_autosend (                      {process queue entries, if enabled}
    qdir,                              {name of top level queue directory}
    inq,                               {generic name of specific queue}
    false,                             {don't wait around for autosend}
    stat);
  sys_msg_parm_vstr (msg_parm[1], inq);
  sys_error_print (stat, 'email', 'smtp_autosend', msg_parm, 1);
  sys_error_none (stat);               {reset any error condition from AUTOSEND}
  end;
{
*************************************************************
}
    end;                               {end of major program mode cases}
  end.
