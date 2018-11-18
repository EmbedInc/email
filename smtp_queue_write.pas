{   Module of routines used for writing SMTP queues.
*
*   For a general discussion of the SMTP queue mechanism, see the header comments
*   in module SMTP_QUEUE.PAS.
}
module smtp_queue_write;
define smtp_queue_create_ent;
define smtp_queue_create_close;
%include 'email2.ins.pas';

const
  max_seq_k = 999;                     {max allowed queue sequence number}
  seq_fw_k = 3;                        {sequence number field width}
{
********************************************************************************
*
*   SMTP_QUEUE_CREATE_ENT (QNAME, CONN_C, CONN_A, CONN_M, STAT)
*
*   Create a new mail queue entry.  QNAME is the generic mail queue name to
*   create the entry within.  This is also the subdirectory name within the
*   generic Embed "smptq" directory.  The CONN_x arguments are the returned
*   connection handles to the control file, addresses list file, and mail
*   message file, respectively.
*
*   The A and M files are open for text write.  The C file is open for binary
*   read and write.  This is an interlock file only; no I/O should be performed
*   to it.  The caller must not close any of the three file connections.  This
*   must be done with routine SMTP_QUEUE_CREATE_CLOSE.
}
procedure smtp_queue_create_ent (      {create a new mail queue entry}
  in      qname: univ string_var_arg_t; {generic name of queue to create entry in}
  out     conn_c: file_conn_t;         {handle to open control file}
  out     conn_a: file_conn_t;         {handle to open addresses list file}
  out     conn_m: file_conn_t;         {handle to open mail message file}
  out     stat: sys_err_t);            {returned completion status code}
  val_param;

var
  tnam: string_treename_t;             {specific queue directory leafname}
  tnam2: string_treename_t;            {scratch path name}
  seq_n: sys_int_machine_t;            {queue entry sequence number}
  seq: string_var16_t;                 {sequence number string}
  gnam: string_leafname_t;             {queue entry file leaf name}
  finfo: file_info_t;                  {info about control file}

label
  abort_a, abort_c;

begin
  tnam.max := sizeof(tnam.str);        {init local var strings}
  tnam2.max := sizeof(tnam2.str);
  seq.max := sizeof(seq.str);
  gnam.max := sizeof(gnam.str);

  sys_cognivis_dir ('smtpq'(0), tnam); {get top level queue directory name}
  string_pathname_join (tnam, qname, tnam2); {make raw specific queue dir name}
  string_treename (tnam2, tnam);       {make full queue directory tree name}

  for seq_n := 1 to max_seq_k do begin {once for each allowable sequence number}
    gnam.str[1] := 'c';                {init static part of control file leaf name}
    gnam.len := 1;                     {init control file name to leading letter}
    string_f_int_max_base (            {make sequence number string}
      seq,                             {output string}
      seq_n,                           {input integer}
      10,                              {number base}
      seq_fw_k,                        {fixed field width}
      [string_fi_leadz_k],             {pad with leading zeros}
      stat);
    string_append (gnam, seq);         {make full control file leaf name}
    string_pathname_join (tnam, gnam, tnam2); {make full control file path name}

    file_open_bin (                    {try open control file for exclusive access}
      tnam2, '',                       {path name and suffix}
      [file_rw_read_k, file_rw_write_k], {we need read and write access}
      conn_c,                          {handle to open file connection}
      stat);
    if file_not_found(stat) then begin {queue directory not exist ?}
      sys_stat_set (email_subsys_k, email_stat_smtp_noqueue_k, stat);
      sys_stat_parm_vstr (qname, stat);
      return;
      end;
    if sys_error(stat) then next;      {assume control file is busy}

    file_info (                        {get control file length}
      conn_c.tnam,                     {name of file to get info about}
      [file_iflag_len_k],              {we want to know file length}
      finfo,                           {returned file info}
      stat);
    if sys_error(stat) then goto abort_c; {can't get control file length}
    if finfo.len <> 0 then goto abort_c; {length isn't 0, not a new entry ?}
    {
    *   The C file is open.  Now try to open the A and M files.
    }
    gnam.str[1] := 'a';                {make addressess list file name}
    string_pathname_join (tnam, gnam, tnam2); {make full path name}
    file_open_write_text (tnam2, '', conn_a, stat); {create the addresses file}
    if sys_error(stat) then goto abort_c;

    gnam.str[1] := 'm';                {make mail message file name}
    string_pathname_join (tnam, gnam, tnam2); {make full path name}
    file_open_write_text (tnam2, '', conn_m, stat); {create the message file}
    if sys_error(stat) then goto abort_a;

    if debug_smtp >= 10 then begin
      smtp_client_wrlock;
      writeln ('Created entry ', seq_n, ' in queue ', qname.str:qname.len);
      smtp_client_wrunlock;
      end;
    return;

abort_a:                               {abort this seq number with A and C files open}
    file_close (conn_a);

abort_c:                               {abort this seq number with C file open}
    file_pos_end (conn_c, stat);       {prevent truncating file on close}
    sys_error_none (stat);             {ignore any error}
    file_close (conn_c);               {close our connection to this control file}
    end;                               {back to try next control file in sequence}
{
*   We ran thru all the allowable sequence numbers and didn't successfully create
*   a new control file.
}
  sys_stat_set (email_subsys_k, email_stat_smtp_queue_full_k, stat);
  sys_stat_parm_vstr (qname, stat);
  end;
{
********************************************************************************
*
*   Subroutine SMTP_QUEUE_CREATE_CLOSE (CONN_C, CONN_A, CONN_M, KEEP, STAT)
*
*   Close the mail queue entry opened with routine SMTP_QUEUE_CREATE_ENT.
*   CONN_C, CONN_A, and CONN_M are the connection handles returned when the
*   queue entry was opened.  These connections must not have been closed.  KEEP
*   must be TRUE if this entry is to be made permanent, and FALSE if this entry
*   is to be deleted.
*
*   All three queue file connections will be closed.  An attempt will be made to
*   delete the queue entry on any error, in which case STAT will indicate the
*   first error encountered.
}
procedure smtp_queue_create_close (    {close queue entry open for creation}
  in out  conn_c: file_conn_t;         {connection handle to control file}
  in out  conn_a: file_conn_t;         {connection handle to addresses list file}
  in out  conn_m: file_conn_t;         {connection handle to mail message file}
  in      keep: boolean;               {TRUE for keep entry, FALSE for delete}
  out     stat: sys_err_t);            {returned completion status code}
  val_param;

var
  dtm: string_var80_t;                 {date/time string}
  stat2: sys_err_t;                    {to avoid corrupting STAT with previous err}

label
  delete;

begin
  dtm.max := sizeof(dtm.str);          {init local var string}
  sys_error_none (stat);

  file_close (conn_m);                 {close all but the control file}
  file_close (conn_a);

  if keep then begin                   {make this entry permanent ?}
    sys_clock_str1 (sys_clock, dtm);   {create time/date string}
    file_write_bin (                   {write time/date string to control file}
      dtm.str,                         {output buffer}
      conn_c,                          {connection handle}
      dtm.len,                         {number of bytes to write}
      stat);
    if sys_error(stat) then goto delete;
    file_close (conn_c);               {close control file}
    return;
    end;
{
*   We were either asked to delete the entry, or an error has occurred.  In
*   either case we will now try to delete the entry while preserving the status
*   from the first error.
}
delete:
  if sys_error(stat)
    then file_delete_name (conn_m.tnam, stat2)
    else file_delete_name (conn_m.tnam, stat);
  if sys_error(stat)
    then file_delete_name (conn_a.tnam, stat2)
    else file_delete_name (conn_a.tnam, stat);
{
*   Make sure control file is empty.  A control file of length 0 is essentially
*   the same as a non-existant control file.
}
  if sys_error(stat)
    then file_pos_start (conn_c, stat2)
    else file_pos_start (conn_c, stat);
  file_close (conn_c);                 {truncate and close at current position}
  end;
