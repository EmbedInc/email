{   Module of routines used for reading SMTP queues.
*
*   For a general discussion of the SMTP queue mechanism, see the header comments
*   in module SMTP_QUEUE.PAS.
}
module smtp_queue_read;
define smtp_queue_read_open;
define smtp_queue_read_ent;
define smtp_queue_read_ent_close;
define smtp_queue_read_close;
%include 'email2.ins.pas';
{
********************************************************************************
*
*   Subroutine SMTP_QUEUE_READ_OPEN (QNAME, MEM, QCONN, STAT)
*
*   Open a connection for reading entries from an SMTP queue.  QNAME is the name
*   of the specific SMTP queue to open.
*
*   MEM is the parent memory context to use.  All our memory will be allocated
*   under a subordinate memory context.  QCONN is the returned handle to the
*   newly created queue connection.
}
procedure smtp_queue_read_open (       {open an SMTP queue for read}
  in      qname: univ string_var_arg_t; {name of queue to open}
  in out  mem: util_mem_context_t;     {parent mem context for our new mem context}
  out     qconn: smtp_qconn_read_t;    {returned handle to queue read connection}
  out     stat: sys_err_t);            {returned completion status code}
  val_param;

var
  conn: file_conn_t;                   {scratch low level connection handle}
  tnam, tnam2: string_treename_t;      {scratch path names}
  info: file_info_t;                   {info about a directory entry (unused)}

label
  next_ent, done_ents, abort;

begin
  tnam.max := sizeof(tnam.str);        {init local var strings}
  tnam2.max := sizeof(tnam2.str);

  qconn.qdir.max := sizeof(qconn.qdir.str); {init QCONN var string length fields}

  util_mem_context_get (mem, qconn.mem_p); {create subordinate memory context}

  string_list_init (qconn.list_ents, qconn.mem_p^); {init entries list}
  qconn.list_ents.deallocable := true;
  string_list_init (qconn.list_adr, qconn.mem_p^); {init dest addresses list}
  qconn.list_adr.deallocable := true;

  sys_cognivis_dir ('smtpq'(0), tnam); {get top level queue directory name}
  string_pathname_join (tnam, qname, tnam2); {make raw specific queue dir name}
  string_treename (tnam2, qconn.qdir); {make full queue directory tree name}

  smtp_queue_opts_get (                {read OPTIONS files and return info}
    tnam,                              {name of top queue directory}
    qname,                             {name of specific queue directory}
    qconn.opts,                        {returned info from OPTIONS files}
    stat);
  if sys_error(stat) then goto abort;
{
*   Make a list of all the control files in this queue.
}
  file_open_read_dir (qconn.qdir, conn, stat); {open queue directory for read}
  if sys_error(stat) then goto abort;

next_ent:                              {back here each new directory entry to read}
  file_read_dir (conn, [], tnam, info, stat); {read this directory entry}
  if file_eof(stat) then goto done_ents; {hit end of queue directory ?}
  if sys_error(stat) then begin        {hard error ?}
    file_close (conn);                 {close our connection to the directory}
    goto abort;
    end;
  if                                   {this entry is a control file ?}
      (tnam.len >= 1) and ((tnam.str[1] = 'c') or (tnam.str[1] = 'C'))
      then begin
    qconn.list_ents.size := tnam.len;  {add this file name to list}
    string_list_line_add (qconn.list_ents);
    string_copy (tnam, qconn.list_ents.str_p^);
    end;
  goto next_ent;                       {back to read next directory entry}
done_ents:                             {done reading the queue directory}
  file_close (conn);                   {close our connection to the directory}
  string_list_pos_abs (qconn.list_ents, 1); {position to first message in list}

  qconn.ent_open := false;             {indicate no queue entry currently open}
  return;                              {normal return}

abort:                                 {clean up to ret with err, STAT already set}
  util_mem_context_del (qconn.mem_p);  {deallocate all our dynamic memory}
  end;                                 {return with error}
{
********************************************************************************
*
*   Subroutine SMTP_QUEUE_READ_ENT (QCONN, TO_LIST_P, MCONN_P, STAT)
*
*   Open the next queue entry for read.  QCONN is the queue connection handle
*   returned from SMTP_QUEUE_READ_OPEN.
*
*   TO_LIST_P is returned pointing to the list of destination addresses for this
*   mail message.  The list position is initialized to before the start of the
*   first entry.
*
*   MCONN_P is returned pointing to the file connection handle to the mail
*   message file.  The caller must not close MCONN_P^ separately.  This is
*   handled internally when this whole queue entry is closed.
*
*   STAT is returned with the status EMAIL_STAT_QUEUE_END_K when the end of the
*   queue is reached.  TO_LIST_P and MCONN_P are invalid unless STAT indicates
*   normal completion.
*
*   No entry must be currently open.  A previous entry must be closed before
*   attempting to open the next entry.
}
procedure smtp_queue_read_ent (        {read next SMTP queue entry}
  in out  qconn: smtp_qconn_read_t;    {handle to queue read connection}
  out     to_list_p: string_list_p_t;  {list of destination addresses for this msg}
  out     mconn_p: file_conn_p_t;      {handle to open message file connection}
  out     stat: sys_err_t);            {set to EMAIL_STAT_QUEUE_END_K on queue end}
  val_param;

var
  tnam: string_treename_t;             {scratch file pathname}
  lnam: string_leafname_t;             {scratch file name}
  buf: string_var256_t;                {for reading one line from file}
  conn: file_conn_t;                   {scratch file connection handle}
  finfo: file_info_t;                  {info about control file}

label
  loop_ent, next_adr, done_adr, next_ent2, next_ent1, eoq;

begin
  tnam.max := sizeof(tnam.str);        {init local var strings}
  lnam.max := sizeof(lnam.str);
  buf.max := sizeof(buf.str);
{
*   Return with error if we already have an entry open.
}
  if qconn.ent_open then begin         {an entry is already open ?}
    sys_stat_set (email_subsys_k, email_stat_qent_open_k, stat);
    return;
    end;
{
*   Back here to retry opening the entry for the next control file in the list.
}
loop_ent:                              {back here each new queue entry to try}
  if qconn.list_ents.str_p = nil then goto eoq; {hit end of queue ?}
  string_pathname_join (               {make name of this control file}
   qconn.qdir, qconn.list_ents.str_p^, tnam);
  file_open_bin (                      {open control file for our exclusive access}
    tnam, '',                          {file name and suffix}
    [file_rw_read_k, file_rw_write_k], {open for both read and write}
    qconn.conn_c,                      {connection handle to open control file}
    stat);
  if sys_error(stat) then goto next_ent1; {skip entry if anything not look right}
{
*   We now own the control file for this entry.  Make sure it has a non-zero
*   length.
}
  file_info (                          {request additional info about control file}
    qconn.conn_c.tnam,                 {name of file requesting info about}
    [file_iflag_len_k],                {we want file length}
    finfo,                             {returned file info}
    stat);
  if sys_error(stat) then goto next_ent2; {punt this queue entry on any error}
  if finfo.len = 0 then goto next_ent2; {this isn't a real control file ?}

  file_pos_end (qconn.conn_c, stat);   {prevent truncate on close}
  if sys_error(stat) then goto next_ent2; {punt this queue entry on any error}
{
*   Read the mail message destination addresses list file and save all the
*   addresses in the QCONN.LIST_ADR list.
}
  string_copy (qconn.list_ents.str_p^, lnam); {make local copy of control file name}
  lnam.str[1] := 'a';                  {make addresses list file local name}
  string_pathname_join (qconn.qdir, lnam, tnam); {make adr list file complete name}

  file_open_read_text (tnam, '', conn, stat); {open addresses list file for read}
  if sys_error(stat) then goto next_ent2; {skip entry if anything not look right}
  string_list_pos_start (qconn.list_adr); {reset addresses list to empty}
  string_list_trunc (qconn.list_adr);

next_adr:                              {back here each new line in adr list file}
  file_read_text (conn, buf, stat);    {read next line from addresses list file}
  if file_eof(stat) then goto done_adr; {hit end of addresses list ?}
  if sys_error(stat) then begin        {hard error ?}
    file_close (conn);                 {clean up}
    goto next_ent2;                    {abort this queue entry}
    end;
  string_unpad (buf);                  {truncate any trailing spaces}
  if buf.len = 0 then goto next_adr;   {nothing on this line ?}
  qconn.list_adr.size := buf.len;      {add this address to list}
  string_list_line_add (qconn.list_adr);
  string_copy (buf, qconn.list_adr.str_p^);
  goto next_adr;                       {back to do next address in list}

done_adr:                              {hit end of addresses list file}
  file_close (conn);                   {close addresses list file}
{
*   Open the mail message file for read.
}
  string_copy (qconn.list_ents.str_p^, lnam); {make local copy of control file name}
  lnam.str[1] := 'm';                  {make mail message local file name}
  string_pathname_join (qconn.qdir, lnam, tnam); {make message file complete name}
  file_open_read_text (tnam, '', qconn.conn_m, stat); {open mail message file}
  if sys_error(stat) then goto next_ent2; {skip entry if anything not look right}
{
*   Return info to caller.
}
  string_list_pos_start (qconn.list_adr); {set to start of addressess list}
  to_list_p := addr(qconn.list_adr);   {return pointer to dest addresses list}
  mconn_p := addr(qconn.conn_m);       {return pointer to message file connection}
  qconn.ent_open := true;              {indicate an entry is now open}
  return;                              {normal return}
{
*   Something went wrong in trying to open the current entry after the control
*   file was already opened.
}
next_ent2:                             {abort curr entry, control file open}
  file_close (qconn.conn_c);
next_ent1:                             {abort curr entry, control file not open}
  string_list_pos_rel (qconn.list_ents, 1); {advance to next control file to try}
  goto loop_ent;                       {back to try next entry in entries list}
{
*   End of entries list encountered.
}
eoq:
  sys_stat_set (email_subsys_k, email_stat_queue_end_k, stat);
  end;
{
********************************************************************************
*
*   Subroutine SMTP_QUEUE_READ_ENT_CLOSE (QCONN, FLAGS, STAT)
*
*   Close a queue entry opened with SMTP_QUEUE_READ_ENT.  This must be done
*   before opening the next entry.  FLAGS is a set of additional operation
*   flags.  The individual flags are:
*
*     SMTP_QRCLOSE_DEL_K  -  Delete the queue entry.
*
*     SMTP_QRCLOSE_UNDELIV_K  -  The remaining destination address list entries
*       are those to which this mail message could not be delivered.  Send
*       undeliverable message notification to sender.  (This flag is not
*       implemented yet.)
}
procedure smtp_queue_read_ent_close (  {close this queue entry}
  in out  qconn: smtp_qconn_read_t;    {handle to queue read connection}
  in      flags: smtp_qrclose_t;       {flags for specific optional operations}
  out     stat: sys_err_t);            {returned completion status code}
  val_param;

var
  tnam: string_treename_t;             {scratch file pathname}
  lnam: string_leafname_t;             {scratch file name}

begin
  tnam.max := sizeof(tnam.str);        {init local var strings}
  lnam.max := sizeof(lnam.str);
{
*   Return with error if no entry is currently open.
}
  if not qconn.ent_open then begin     {no entry open ?}
    sys_stat_set (email_subsys_k, email_stat_qent_nopen_k, stat);
    return;
    end;

  file_close (qconn.conn_m);           {close mail message file}
{
*   Delete address and message files, if requested.
}
  if smtp_qrclose_del_k in flags then begin {supposed to delete queue entry ?}
    string_copy (qconn.list_ents.str_p^, lnam); {make address file name in TNAM}
    lnam.str[1] := 'a';
    string_pathname_join (qconn.qdir, lnam, tnam);
    file_delete_name (tnam, stat);     {delete address list file}

    string_copy (qconn.list_ents.str_p^, lnam); {make message file name in TNAM}
    lnam.str[1] := 'm';
    string_pathname_join (qconn.qdir, lnam, tnam);
    file_delete_name (tnam, stat);     {delete message file}
    end;                               {done trying to delete adr and msg files}
{
*   Close control file and try to delete it, if requested.
}
  file_close (qconn.conn_c);           {close control file}
  if smtp_qrclose_del_k in flags then begin {supposed to delete queue entry ?}
    file_delete_name (qconn.conn_c.tnam, stat);
    end;
  sys_error_none (stat);               {reset any error status}

  qconn.ent_open := false;             {indicate no queue entry currently open}
  string_list_pos_rel (qconn.list_ents, 1); {advance to next control file in list}
  end;
{
********************************************************************************
*
*   Subroutine SMTP_QUEUE_READ_CLOSE (QCONN, STAT)
*
*   Close the connection to an SMTP queue that was opened with subroutine
*   SMTP_QUEUE_READ_OPEN.
}
procedure smtp_queue_read_close (      {close connection to an SMTP queue}
  in out  qconn: smtp_qconn_read_t;    {handle to queue read connection}
  out     stat: sys_err_t);            {returned completion status code}
  val_param;

begin
  sys_error_none (stat);               {init to no error ocurred}

  if qconn.ent_open then begin         {a queue entry is currently open ?}
    smtp_queue_read_ent_close (qconn, [], stat); {close current entry}
    end;

  util_mem_context_del (qconn.mem_p);  {deallocate all our dynamic memory}
  end;
