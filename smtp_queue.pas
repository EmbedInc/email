{   Module of general utility routines for manipulating SMTP queues.
*
*   See the EMAIL documentation file for an overview of the queueing
*   mechanism.
}
module smtp_queue;
define smtp_queue_opts_get;
define smtp_autosend;
%include 'email2.ins.pas';

const
  n_cmds_k = 17;                       {number of OPTIONS file commands}
  cmd_len_k = 10;                      {number of chars in longest OPTIONS file cmd}
  cmd_memlen_k = cmd_len_k + 1;        {number of chars allocated per command name}
  cmds_len_k = n_cmds_k * cmd_memlen_k; {number of chars in whole commands list}

type                                   {format of one OPTIONS file command name}
  cmd_t =
    array[1..cmd_memlen_k] of char;
  cmds_t =                             {format of complete list of OPTIONS commands}
    array[1..n_cmds_k] of cmd_t;

var
  cmds: cmds_t := [                    {all the valid OPTIONS file command names}
    'LOCALSYS  ',                      {1}
    'REMOTESYS ',                      {2}
    'SENDMAIL  ',                      {3}
    'INQ       ',                      {4}
    'PORT      ',                      {5}
    'SMTP_CMD  ',                      {6}
    'AUTOSEND  ',                      {7}
    'REM_RESP  ',                      {8}
    'POP3      ',                      {9}
    'BOUNCEFROM',                      {10}
    'REMOTEPSWD',                      {11}
    'REMOTEUSER',                      {12}
    'USERPUT   ',                      {13}
    'PSWDGET   ',                      {14}
    'PSWDPUT   ',                      {15}
    'PASSWORD  ',                      {16}
    'RECVDOM   ',                      {17}
    ];
{
********************************************************************************
*
*   SMTP_QUEUE_OPTS_GET (QTOP_DIR, QLOC_DIR, OPTS, STAT)
*
*   Read the OPTIONS files in the top level and specific queue directories.  The
*   combined information is returned in OPTS.  QTOP_DIR is the pathname of the
*   top level queue directory, and QLOC_DIR is the name of the specific queue
*   directory within the QTOP_DIR directory.  QLOC_DIR may be of zero length, in
*   which case only the top level options file is read.  It is no an error if
*   the local queue does not exist, or the OPTIONS file within that queue does
*   not exist.
}
var
  options: string_var16_t :=
    [str := 'options', len := 7, max := sizeof(options.str)];
  smtp_prog: string_var4_t :=
    [str := 'smtp', len := 4, max := sizeof(smtp_prog.str)];

procedure smtp_queue_opts_get (        {read OPTIONS files and return info}
  in      qtop_dir: univ string_var_arg_t; {name of top level queue directory}
  in      qloc_dir: univ string_var_arg_t; {optional name of specific queue within top}
  out     opts: smtp_queue_options_t;  {returned values from OPTIONS files}
  out     stat: sys_err_t);            {returned completion status code}
  val_param;

var
  tnam, tnam2: string_treename_t;      {scratch pathnames}
  i: sys_int_machine_t;                {scratch integer}
  finfo: file_info_t;                  {info about a system pathname}
  bouncefrom: boolean;                 {BOUNCEFROM explicitly set}

label
  done_local;
{
************************************
*
*   Local subroutine DEFAULT_SMTP_CMD (S)
*
*   Set S to the default SMTP_CMD value.
}
procedure default_smtp_cmd (
  in out  s: univ string_var_arg_t);

var
  tnam: string_treename_t;             {scratch pathname}

begin
  tnam.max := sizeof(tnam.str);        {init local var string}

  sys_cognivis_dir ('com'(0), tnam);   {get Cognivision commands directory name}
  string_pathname_join (               {create pathname to default SMTP program}
    tnam, smtp_prog, s);
  end;
{
************************************
*
*   Local subroutine READ_FILE (FNAM)
*   This routine is local to SMTP_QUEUE_OPTS_GET.
*
*   Read and process the options file FNAM.  It is not an error if the options
*   file does not exist.
}
procedure read_file (                  {read and process options file name}
  in      fnam: string_treename_t);    {options file name}
  val_param;

var
  conn: file_conn_t;                   {handle to options file connection}
  buf: string_var8192_t;               {one line input buffer}
  cmd: string_var32_t;                 {command name parsed from input line}
  parm: string_var8192_t;              {command parameter}
  pick: sys_int_machine_t;             {number of keyword picked from list}
  p: string_index_t;                   {BUF parse index}

label
  loop_cmd, done_cmd, err_parm, eof, leave;

begin
  buf.max := sizeof(buf.str);          {init local var string}
  cmd.max := sizeof(cmd.str);
  parm.max := sizeof(parm.str);

  file_open_read_text (fnam, '', conn, stat); {try to open options file for read}
  if file_not_found(stat) then return; {not exist, return without error}
  if sys_error(stat) then return;      {hard error occurred ?}
  opts.localread := true;              {indicate the OPTIONS file was opened}

loop_cmd:                              {back here each new command from options file}
  file_read_text (conn, buf, stat);    {read next line from options file}
  if file_eof(stat) then goto eof;     {hit end of options file ?}
  string_unpad (buf);                  {remove trailing spaces}
  if buf.len <= 0 then goto loop_cmd;  {ignore empty lines}
  p := 1;                              {init input line parse index}
  while (p <= buf.len) and (buf.str[p] = ' ') {strip off leading spaces}
    do p := p + 1;
  if (p <= buf.len) and then (buf.str[p] = '*') {comment line ?}
    then goto loop_cmd;
  string_token (buf, p, cmd, stat);    {extract command keyword}
  if sys_error(stat) then begin
    sys_stat_set (email_subsys_k, email_stat_qopt_cmd_get_k, stat);
    sys_stat_parm_vstr (conn.tnam, stat);
    sys_stat_parm_int (conn.lnum, stat);
    goto leave;
    end;
  string_upcase (cmd);                 {make upper case for keyword matching}
  string_tkpick_s (                    {pick command from keywords list}
    cmd,                               {command name}
    cmds,                              {list of valid command names}
    cmds_len_k,                        {number of chars in CMDS}
    pick);                             {number of keyword picked from list}
  case pick of                         {which command is this ?}
{
*   LOCALSYS <system name>
}
1: begin
  string_token (buf, p, opts.localsys, stat); {extract local system name}
  end;
{
*   REMOTESYS <system name>
}
2: begin
  string_token (buf, p, opts.remotesys, stat); {extract remote system name}
  end;
{
*   SENDMAIL
}
3: begin
  opts.sendmail := true;
  end;
{
*   INQ <generic queue name>
}
4: begin
  string_token (buf, p, opts.inq, stat); {extract input queue name}
  end;
{
*   PORT <server port ID on remote system>
}
5: begin
  string_token_int (buf, p, i, stat);  {get port number in I}
  if string_eos(stat)
    then begin                         {no parameter was present}
      opts.port := 0;                  {reset to indicate default}
      end
    else begin                         {yes, there was a parameter}
      opts.port := i;
      end
    ;
  end;
{
*   SMTP_CMD <smtp command name>
}
6: begin
  while (p <= buf.len) and (buf.str[p] = ' ') {skip over blanks after "SMTP_CMD"}
    do p := p + 1;
  if p > buf.len
    then begin                         {no command name was given}
      default_smtp_cmd (opts.smtp_cmd); {reset to default SMTP command name}
      end
    else begin                         {a non-blank command line exists}
      string_substr (buf, p, buf.len, opts.smtp_cmd); {extract raw command string}
      p := buf.len + 1;                {indicate input line all used up}
      end
    ;
  end;
{
*   AUTOSEND <ON or OFF>
}
7: begin
  string_token_bool (                  {get and interpret ON/OFF token}
    buf, p, [string_tftype_onoff_k], opts.autosend, stat);
  end;
{
*   REM_RESP <remote system name>
}
8: begin
  string_token (buf, p, opts.rem_resp, stat); {extract remote system name}
  end;
{
*   POP3 <ON or OFF>
}
9: begin
  string_token_bool (                  {get and interpret ON/OFF token}
    buf, p, [string_tftype_onoff_k], opts.pop3, stat);
  end;
{
*   BOUNCEFROM address
}
10: begin
  string_token (buf, p, opts.bouncefrom, stat);
  if sys_error(stat) then goto done_cmd;
  string_downcase (opts.bouncefrom);
  bouncefrom := true;
  end;
{
*   REMOTEPSWD password
}
11: begin
  string_token (buf, p, opts.remotepswd, stat);
  end;
{
*   REMOTEUSER username
}
12: begin
  string_token (buf, p, opts.remoteuser, stat);
  end;
{
*   USERPUT <ON or OFF>
}
13: begin
  string_token_bool (                  {get and interpret ON/OFF token}
    buf, p, [string_tftype_onoff_k], opts.userput, stat);
  end;
{
*   PSWDGET password
}
14: begin
  string_token (buf, p, opts.pswdget, stat);
  end;
{
*   PSWDPUT password
}
15: begin
  string_token (buf, p, opts.pswdput, stat);
  end;
{
*   PASSWORD password
}
16: begin
  string_token (buf, p, opts.pswdget, stat);
  string_copy (opts.pswdget, opts.pswdput);
  end;
{
*   RECVDOM domain ... domain
}
17: begin
  opts.recvdom.len := 0;               {clear any previous domains list}
  while true do begin                  {back here each new domain name token}
    string_token (buf, p, parm, stat); {try to get next domain name}
    if string_eos(stat) then exit;     {exhausted list of domain names ?}
    if sys_error(stat) then goto err_parm;
    string_upcase (parm);              {domain names are case-insensitive}
    string_append_token (opts.recvdom, parm); {add this domain to list}
    end;                               {back to get next domain name token}
  end;
{
*   Unrecognized command.
}
otherwise
    sys_stat_set (email_subsys_k, email_stat_qopt_cmd_bad_k, stat);
    sys_stat_parm_vstr (cmd, stat);
    sys_stat_parm_vstr (conn.tnam, stat);
    sys_stat_parm_int (conn.lnum, stat);
    goto leave;
    end;                               {end of command keyword cases}
{
*   Done processing the current command.  Now check for errors.
}
done_cmd:
  if string_eos(stat) then begin       {missing parameter ?}
    sys_stat_set (email_subsys_k, email_stat_qopt_parm_err_k, stat);
    sys_stat_parm_vstr (cmd, stat);
    sys_stat_parm_vstr (conn.tnam, stat);
    sys_stat_parm_int (conn.lnum, stat);
    goto leave;
    end;

  if sys_error(stat) then begin        {error with parameter ?}
err_parm:                              {jump here on bad parameter}
    sys_stat_set (email_subsys_k, email_stat_qopt_parm_err_k, stat);
    sys_stat_parm_vstr (cmd, stat);
    sys_stat_parm_vstr (conn.tnam, stat);
    sys_stat_parm_int (conn.lnum, stat);
    goto leave;
    end;

  string_token (buf, p, parm, stat);   {try to extract one more token}
  if not string_eos(stat) then begin   {didn't hit end of line ?}
    sys_stat_set (email_subsys_k, email_stat_qopt_parm_extra_k, stat);
    sys_stat_parm_vstr (cmd, stat);
    sys_stat_parm_vstr (conn.tnam, stat);
    sys_stat_parm_int (conn.lnum, stat);
    goto leave;
    end;

  goto loop_cmd;                       {no errors, go process next command}
{
*   End of input file encountered.
}
eof:
{
*   Command exit point once file is opened.
}
leave:
  file_close (conn);                   {try to close input file}
  end;
{
************************************
*
*   Start of main routine SMTP_QUEUE_OPTS_GET.
}
begin
  tnam.max := sizeof(tnam.str);        {init local var strings}
  tnam2.max := sizeof(tnam2.str);
{
*   Init OPTS static fields and set to default values.
}
  opts.localsys.max := sizeof(opts.localsys.str);
  opts.recvdom.max := sizeof(opts.recvdom.str);
  opts.remotesys.max := sizeof(opts.remotesys.str);
  opts.rem_resp.max := sizeof(opts.rem_resp.str);
  opts.remotepswd.max := sizeof(opts.remotepswd.str);
  opts.remoteuser.max := sizeof(opts.remoteuser.str);
  opts.inq.max := sizeof(opts.inq.str);
  opts.smtp_cmd.max := sizeof(opts.smtp_cmd.str);
  opts.pswdget.max := sizeof(opts.pswdget.str);
  opts.pswdput.max := sizeof(opts.pswdput.str);
  opts.bouncefrom.max := sizeof(opts.bouncefrom.str);

  opts.localsys.len := 0;
  opts.recvdom.len := 0;
  string_generic_fnam (qloc_dir, '', opts.remotesys); {default to generic queue name}
  string_downcase (opts.remotesys);
  opts.rem_resp.len := 0;
  opts.remotepswd.len := 0;
  opts.remoteuser.len := 0;
  opts.port := 0;
  opts.inq.len := 0;
  default_smtp_cmd (opts.smtp_cmd);
  opts.pswdget.len := 0;
  opts.pswdput.len := 0;
  opts.bouncefrom.len := 0;
  opts.sendmail := false;
  opts.autosend := false;
  opts.pop3 := false;
  opts.userput := false;
  opts.localqueue := false;
  opts.localread := false;

  bouncefrom := false;                 {init to BOUNCEFROM not explicitly set}
{
*   Read top level options file.
}
  string_pathname_join (qtop_dir, options, tnam); {make file pathname}
  read_file (tnam);                    {process the file}
  if sys_error(stat) then return;
  opts.localread := false;             {the global OPTIONS file was read, not local}
{
*   Read options file for this specific queue.
}
  if qloc_dir.len > 0 then begin       {we actually have specific queue name ?}
    string_pathname_join (qtop_dir, qloc_dir, tnam2); {pathname of queue directory}
    file_info (                        {get info about local queue pathname}
      tnam2,                           {file system object inquiring about}
      [file_iflag_type_k],             {want to know file type}
      finfo,                           {returned info about the file system object}
      stat);
    if sys_error(stat) then begin      {assume local queue doesn't exist ?}
      sys_error_none (stat);           {local queue not exist isn't an error}
      goto done_local;                 {done trying to read local OPTIONS file}
      end;
    if finfo.ftype <> file_type_dir_k  {local queue name isn't a directory ?}
      then goto done_local;            {abort trying to read local OPTIONS file}
    opts.localqueue := true;           {the specified local queue exists}
    string_pathname_join (tnam2, options, tnam); {make file pathname}
    read_file (tnam);                  {process the file}
    end;
done_local:                            {all done attempting to read local OPTIONS}

  if opts.rem_resp.len = 0 then begin  {remote system repsonse name not set ?}
    string_copy (opts.remotesys, opts.rem_resp); {default to outgoing rem sys name}
    end;

  if not bouncefrom then begin         {BOUNCEFROM not explicitly set ?}
    if opts.localsys.len > 0 then begin {the local system name is available ?}
      string_vstring (opts.bouncefrom, 'autoreply@'(0), -1);
      string_append (opts.bouncefrom, opts.localsys);
      end;
    end;
  end;
{
********************************************************************
*
*   Subroutine SMTP_AUTOSEND (QTOP_DIR, QLOC_DIR, STAT)
*
*   De-queue all the entries in the indicated mail queue by running a command
*   in a separate process.  The process is left to complete on its own.  This
*   routine returns as soon as the process is launched.
*
*   The command line for the new process can be partially controlled with the
*   SMTP_CMD command in the OPTIONS files.  See the description for the
*   SMTP_CMD and AUTOSEND commands, above.
*
*   Nothing will be done if AUTOSEND is disabled for the indicated queue.
}
procedure smtp_autosend (              {de-queue queue entries in separate process}
  in      qtop_dir: univ string_var_arg_t; {name of top level queue directory}
  in      qloc_dir: univ string_var_arg_t; {name of specific queue directory}
  in      sync: boolean;               {run proc synchronously, get exit status}
  out     stat: sys_err_t);            {returned completion status code}
  val_param;

var
  cmd: string_var8192_t;               {complete command line}
  token: string_var32_t;               {scratch token for number conversion, etc}
  opts: smtp_queue_options_t;          {info read from OPTIONS files}
  stdin, stdout, stderr: sys_sys_iounit_t; {I/O handles for new process}
  proc_id: sys_sys_proc_id_t;          {ID of new process}
  tf: boolean;                         {true/false status returned by process}
  exstat: sys_sys_exstat_t;            {child process exit status}

begin
  cmd.max := sizeof(cmd.str);          {init local var strings}
  token.max := sizeof(token.str);

  smtp_queue_opts_get (                {read OPTIONS files for this queue}
    qtop_dir,                          {name of top level queue directory}
    qloc_dir,                          {generic name of specific queue}
    opts,                              {returned information from OPTIONS file}
    stat);
  if sys_error(stat) then return;

  if not opts.autosend then return;    {not supposed to AUTOSEND from this queue ?}

  string_copy (opts.smtp_cmd, cmd);    {init command with program name}
  string_appends (cmd, ' -client -outq '(0));
  string_append (cmd, qloc_dir);
  string_appends (cmd, ' -debug '(0));
  string_f_int (token, debug_smtp);
  string_append (cmd, token);

  if (debug_smtp >= 5) then begin      {supposed to show status to STDOUT ?}
    writeln ('Running: ', cmd.str:cmd.len);
    end;

  if (debug_smtp >= 7) or sync
    then begin                         {wait for command, show output}
      sys_run_wait_stdsame (cmd, tf, exstat, stat);
      if not tf then begin             {error ?}
        if debug_smtp >= 5 then begin
          writeln ('Command failed, exit status was ', exstat, '.');
          end;
        end;
      end
    else begin                         {start command, no further interaction}
      sys_run (                        {run the command in a separate process}
        cmd,                           {command line to execute}
        sys_procio_none_k,             {no I/O connection to parent process}
        stdin, stdout, stderr,         {I/O handles for new process, unused}
        proc_id,                       {returned ID of new process}
        stat);
      if sys_error(stat) then return;
      sys_proc_release (proc_id, stat); {release any interest in the process}
      end
    ;
  end;
