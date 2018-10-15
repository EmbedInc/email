{   Routines for sending mail using MX lookup to find the host machines to send
*   to.
}
module smtp_send_queue_mx;
define smtp_send_queue_mx;
%include 'email2.ins.pas';
{
********************************************************************************
*
*   Local subroutine ADR_DOMAIN (ADR, DOM)
*
*   Find the domain name in the email address ADR, and return it in DOM.  When
*   a domain can't be found, DOM is returned the empty string.
}
procedure adr_domain (                 {get domain of email address}
  in      adr: univ string_var_arg_t;  {email address to parse}
  in out  dom: univ string_var_arg_t); {returned domain}
  val_param; internal;

var
  p: string_index_t;                   {index into input string}

begin
  dom.len := 0;                        {init to domain not found}

  p := adr.len;                        {start parsing at end of input string}
  while true do begin                  {scan backwards thru input string}
    if p < 1 then return;              {exhausted input string ?}
    if adr.str[p] = '@' then exit;     {found separator before domain name ?}
    p := p - 1;                        {back one character and check again}
    end;
  if p >= adr.len then return;         {separator at end ?}

  string_substr (                      {extract domain name from source string}
    adr,                               {source string}
    p + 1,                             {start index}
    adr.len,                           {end index}
    dom);                              {output string}
  end;
{
********************************************************************************
*
*   Local subroutine DOMAIN_HOST (DOMAIN, HOST)
*
*   Return the name of the single most preferred MX host for the domain DOMAIN
*   in HOST.  HOST is returned the empty string on any error.
}
procedure domain_host (                {get most preferred MX host for a domain}
  in      domain: univ string_var_arg_t; {domain name}
  in out  host: univ string_var_arg_t); {returned name of host to send mail to}
  val_param; internal;

var
  mxdom_p: sys_mxdom_p_t;              {pointer to MX records for a domain}
  mxrec_p: sys_mxrec_p_t;              {pointer to current MX record}
  best_p: sys_mxrec_p_t;               {pointer to best MX record found so far}
  stat: sys_err_t;                     {completion status}

begin
  host.len := 0;                       {init to not returning with a host name}

  sys_mx_lookup (util_top_mem_context, domain, mxdom_p, stat); {get MX records}
  if sys_error_check (stat, '', '', nil, 0)
    then return;

  mxrec_p := mxdom_p^.list_p;          {init to first host in list}
  best_p := mxrec_p;                   {init best host found so far}
  while true do begin                  {scan remainder of list}
    mxrec_p := mxrec_p^.next_p;        {advance to next host in list}
    if mxrec_p = nil then exit;        {end of list}
    if mxrec_p^.ttl < best_p^.ttl then begin {found a better host ?}
      best_p := mxrec_p;               {update pointer to best found so far}
      end;
    end;                               {back to check next list entry}

  string_copy (best_p^.name_p^, host); {return name of the best host}

  sys_mx_dealloc (mxdom_p);            {deallocate MX records}
  end;
{
********************************************************************************
*
*   Local subroutine ADR_HOST (ADR, HOST)
*
*   Return the MX host to send mail to for the destination mail address ADR.
*
*   HOST is returned the empty string on any error.
}
procedure adr_host (                   {get MX host for a email address}
  in      adr: univ string_var_arg_t;  {email address}
  in out  host: univ string_var_arg_t); {returned name of host to send mail to}
  val_param; internal;

var
  domain: string_var256_t;             {domain name}

begin
  domain.max := size_char(domain.str); {init local var string}
  host.len := 0;                       {init to not returning with a host name}

  adr_domain (adr, domain);            {get domain email address is to}
  if domain.len = 0 then return;
  domain_host (domain, host);          {get MX host for the domain}
  end;
{
********************************************************************************
*
*   Subroutine SMTP_SEND_QUEUE_MX (QCONN, STAT)
*
*   Send all the messages in the queue open on QCONN.  The remote machines to
*   send to are determined by doing MX lookups on the domains of the destination
*   addresses.
}
procedure smtp_send_queue_mx (         {send all mail queue to hosts using MX lookup}
  in out  qconn: smtp_qconn_read_t;    {open connection for reading the queue}
  out     stat: sys_err_t);            {returned completion status code}
  val_param;

var
  adr_p: string_list_p_t;              {points to list of destination addresses}
  mconn_p: file_conn_p_t;              {points to connection to mail message}
  adrleft: string_list_t;              {remaining addresses to send this message to}
  host: string_var1024_t;              {current MX host to send to}
  adrhost: string_list_t;              {addresses for the current MX host}
  adrerr: string_list_t;               {addresses unable to send to}
  h: string_var1024_t;                 {scratch host name}
  fnam: string_leafname_t;             {scratch file leafname}
  tnam: string_treename_t;             {scratch file full treename}
  conn: file_conn_t;                   {scratch I/O connection}
  qrclose: smtp_qrclose_t;             {option flags for closing a queue entry}

label
  wadr_err;

begin
  host.max := size_char(host.str);     {init local var strings}
  h.max := size_char(h.str);
  fnam.max := size_char(fnam.str);
  tnam.max := size_char(tnam.str);
{
*   Loop over all the messages in the queue.
}
  while true do begin                  {back here each new queue entry}
    smtp_queue_read_ent (              {open message}
      qconn,                           {connection to queue}
      adr_p,                           {returned pointer to destination addresses}
      mconn_p,                         {returned connection to message file}
      stat);
    if sys_stat_match (email_subsys_k, email_stat_queue_end_k, stat) then begin
      return;                          {end of queue, normal return point}
      end;

    string_list_copy (                 {init list of remaining adr to send this message to}
      adr_p^,                          {source list}
      adrleft,                         {new list to create}
      qconn.mem_p^);                   {parent mem context for the new list}

    string_list_init (adrerr, qconn.mem_p^); {init list of failed addresses}
    {
    *   ADRLEFT is a local list of addresses that the message needs to be sent
    *   to.  This loop keeps sending to different hosts until the message has
    *   been sent to all addresses, meaning ADRLEFT is exhausted.
    *
    *   Each iteration, the first address in ADRLEFT is used to determine the
    *   host to send to.  The remaining addresses are then scanned to find those
    *   that resolve to the same host.  This builds the list ADRHOST, which is
    *   the target addresses for that host.  Those addresses are removed from
    *   ADRLEFT.  The message is either sent successfully, or the addresses in
    *   ADRHOST are added to the ADRERR list, which is the list of addresses
    *   to which sending failed.
    }
    while true do begin                {back here until target addresses list exhausted}
      string_list_pos_abs (adrleft, 1); {init to first remaining address list entry}
      if adrleft.str_p = nil then exit; {no more addresses to send to ?}
      {
      *   Resolve host name for first target address, save in HOST.
      }
      adr_host (adrleft.str_p^, host); {make host name for this address}
      if host.len = 0 then begin       {couldn't get host name, assume bad address}
        string_list_line_del (adrleft, true); {ignore this target address}
        next;                          {back for next address list entry}
        end;

      string_list_init (adrhost, qconn.mem_p^); {init list of addresses for this host}
      string_list_str_add (adrhost, adrleft.str_p^); {add this address to list for this host}
      string_list_line_del (adrleft, true); {remove this address from pending list}
      {
      *   Scan the remaining target addresses.  Those that resolve to the same
      *   host are removed from the remaining list and added to the list for
      *   this host.
      *
      *   This section builds the ADRHOST list, and removes those addresses from
      *   the ADRLEFT list.
      }
      while true do begin              {scan remaining addresses}
        if adrleft.str_p = nil then exit; {hit end of list ?}
        adr_host (adrleft.str_p^, h);  {find host for this address}
        if string_equal(h, host) then begin {also to this host ?}
          string_list_str_add (        {add this address to list for this host}
            adrhost, adrleft.str_p^);
          string_list_line_del (adrleft, true); {remove this address from pending list}
          next;                        {back to check next pending address}
          end;
        string_list_pos_rel (adrleft, 1); {advance to next pending address}
        end;                           {back to check this next address}
      {
      *   Send the current message to the addresses in the ADRHOST list to the
      *   host HOST.
      }
      smtp_send_host (                 {send this message to this host}
        host,                          {name of host machine to send to}
        qconn.opts,                    {options in effect for this message}
        mconn_p^,                      {connection to the message file to send}
        adrhost,                       {adr to send to, returned only unsent}
        stat);
      if sys_error_check (stat, '', '', nil, 0) then begin
        sys_error_none (stat);         {don't pass this error up to caller}
        end;
      {
      *   The ADRHOST list now contains only the addresses to which the message
      *   was not successfully sent.  Add the contents of the ADRHOST list to
      *   the ADRERR list.
      }
      string_list_pos_abs (adrhost, 1); {go to first unsent adr list entry}
      while adrhost.str_p <> nil do begin {once for each unsent address in list}
        string_list_str_add (adrerr, adrhost.str_p^); {add this address to error list}
        string_list_pos_rel (adrhost, 1);
        end;
      string_list_kill (adrhost);      {deallocate the list of addresses for this host}
      end;                             {back to send this message to next host}
    {
    *   Done with attempts to send to all hosts.
    *
    *   ADRERR is the list of addresses for which sending failed.  If this list
    *   is not empty, write it back to the queue as the Axxx file, and do not
    *   delete the queue entry when closing it.
    *
    *   Otherwise, just close and delete the queue entry.
    }
    qrclose := [smtp_qrclose_del_k];   {init to delete the queue entry on close}
    if adrerr.n > 0 then begin         {failed to send to one or more addresses ?}
      string_copy (qconn.conn_c.fnam, fnam); {get full leafname of entry control file}
      fnam.str[1] := 'a';              {make name of addresses list file}
      string_pathname_join (qconn.qdir, fnam, tnam); {make addresses file full treename}
      file_open_write_text (tnam, '', conn, stat); {open addresses file for write}
      if sys_error(stat) then goto wadr_err;
      string_list_pos_start (adrerr);  {position to before first error list entry}
      while true do begin              {loop over the error list entries}
        string_list_pos_rel (adrerr, 1); {to next list entry}
        if adrerr.str_p = nil then exit; {hit end of list ?}
        file_write_text (adrerr.str_p^, conn, stat); {write this address to file}
        if sys_error(stat) then begin
          sys_error_none (stat);       {don't pass up errors trying to write new adr file}
          file_close (conn);
          goto wadr_err;
          end;
        end;                           {back for next list entry}
      file_close (conn);               {close the new addresses file}
      qrclose := [];                   {don't delete queue entry when closed}
wadr_err:                              {skip to here on error writing new addresses file}
      end;
    string_list_kill (adrerr);         {deallocate errors list for this message}

    smtp_queue_read_ent_close (        {close this queue entry}
      qconn,                           {connection to the queue}
      qrclose,                         {optional flags}
      stat);
    if sys_error(stat) then return;
    end;                               {back to do next message in the queue}
  end;
