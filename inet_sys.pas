{   System dependent routines for communicating over the internet.
*
*   This version is for the Microsoft Win32 environment.
}
module inet_sys;
define inet_connect;
define inet_disconnect;
%include 'email2.ins.pas';
%include 'sys_sys2.ins.pas';
{
********************************************************************
*
*   Subroutine INET_CONNECT (RINFO, NEW_CONN, STAT)
*
*   Make sure a connection exists to the remote system described in RINFO,
*   if enabled.  NEW_CONN is returned TRUE if a new connection was established,
*   and FALSE if no new connection was established.  No attempt is made
*   to establish a connection if RINFO.CONNECT is FALSE.
}
procedure inet_connect (               {connect to remote system, if needed}
  in out  rinfo: smtp_rinfo_t;         {info about the remote system}
  out     new_conn: boolean;           {TRUE on connected if previously wasn't}
  out     stat: sys_err_t);            {returned completion status code}
  val_param;

const
  n_ras_list_k = 20;                   {max number of RAS conn we can hold info for}
  max_msg_parms = 2;                   {max parameters we can pass to a message}

var
  dialparms: rasdial_parms_t;          {parameters for dialing new connection}
  try: sys_int_machine_t;              {1-N number of this connect attempt}
  err: sys_sys_err_t;                  {system error code from last conn attempt}
  s: string_var80_t;                   {scratch string}
  phu: string_var80_t;                 {upper case desired phone book entry name}
  ras_list:                            {list of RAS connections}
    array[1..n_ras_list_k] of ras_conn_t;
  n_ras: win_dword_t;                  {number of entries in RAS_LIST}
  wsize: win_dword_t;                  {memory size}
  i: sys_int_machine_t;                {scratch integer and loop counter}
  msg_parm:                            {parameter references for messages}
    array[1..max_msg_parms] of sys_parm_msg_t;

label
  loop_connect;

begin
  s.max := size_char(s.str);           {init local var strings}
  phu.max := size_char(phu.str);
  sys_error_none (stat);               {init to no error ocurred}
  new_conn := false;                   {init to no new connection established}
  rinfo.conn.sys := handle_none_k;     {init to dialup not open in any way}
  if not rinfo.connect then return;    {new connection explicilty disabled ?}

  string_copy (rinfo.phbook_ent, phu); {make upper case desired phbook entry name}
  string_upcase (phu);
{
*   Check for whether we are already connected with the desired phone book
*   entry.
}
  ras_list[1].size := sizeof(ras_list[1]); {indicate size of each array element}
  wsize := sizeof(ras_list);           {size of whole RAS_LIST array}
  stat.sys := RasEnumConnectionsA (    {get list of all existing RAS connections}
    ras_list,                          {array to receive the info}
    wsize,                             {memory size of whole array}
    n_ras);                            {number of resulting valid RAS_LIST entries}
  if debug_inet >= 1 then begin
    sys_error_print (stat, 'email', 'dialup_list', nil, 0);
    end;
  if sys_error(stat) then return;

  for i := 1 to n_ras do begin         {check thru the existing dialup connections}
    string_vstring (s, ras_list[i].phbook_entry, -1); {make var str phbook ent name}
    string_upcase (s);                 {make both names same case}
    if string_equal (s, phu) then begin {found matching entry ?}
      rinfo.conn.sys := ras_list[i].handle; {save handle to connection}
      if debug_inet >= 1 then begin
        sys_clock_str1 (sys_clock, s); {make current date/time string}
        sys_msg_parm_vstr (msg_parm[1], s);
        sys_msg_parm_vstr (msg_parm[2], phu);
        sys_message_parms ('email', 'dialup_reused', msg_parm, 2);
        end;
      return;                          {normal return on already connected}
      end;
    end;                               {back to check out next existing connection}
{
*   None of the existing connections matched the name of the desired phone book
*   entry.
*
*   Fill in RAS dial parameters.
}
  dialparms.size := sizeof(dialparms); {size of whole data structure}
  string_t_c (                         {set phone book entry name}
    rinfo.phbook_ent,
    dialparms.phbook_entry,
    size_char(dialparms.phbook_entry));
  string_t_c (                         {set phone number string}
    rinfo.phnum,
    dialparms.phnum,
    size_char(dialparms.phnum));
  dialparms.phcallback[1] := chr(0);   {don't use callback}
  string_t_c (                         {set remote login user name}
    rinfo.user,
    dialparms.user,
    size_char(dialparms.user));
  string_t_c (                         {set remote login password}
    rinfo.password,
    dialparms.password,
    size_char(dialparms.password));
  string_t_c (                         {use domain name from phone book entry}
    string_v('*'),
    dialparms.domain,
    size_char(dialparms.domain));

  try := 0;                            {init to no connect attempts yet}

loop_connect:                          {back here to retry connect after failure}
  try := try + 1;                      {make number of this connection attempt}
  if                                   {check for too many attempts to connect}
      (rinfo.n_max_dial > 0) and       {a max attempts limit exists ?}
      (try > rinfo.n_max_dial)         {exceeded the limit ?}
      then begin
    if debug_inet >= 1 then begin
      sys_message ('email', 'retry_limit');
      end;
    stat.sys := err;                   {pass back error from last connect attempt}
    return;
    end;

  err := RasDialA (                    {try to dial remote system}
    nil,                               {no extension info supplied}
    nil,                               {use default phone book file}
    dialparms,                         {additional parameters for dialing}
    ras_notify_none_k, nil,            {don't notify of progress}
    win_handle_t(rinfo.conn.sys));     {handle to this new RAS connection}
  sys_clock_str1 (sys_clock, s);       {make current date/time string}
  sys_msg_parm_vstr (msg_parm[1], s);
  if err = err_none_k then begin       {all done with no errors ?}
    if debug_inet >= 1 then begin
      sys_msg_parm_vstr (msg_parm[2], rinfo.isp);
      sys_message_parms ('email', 'dialup_connected', msg_parm, 2);
      end;
    new_conn := true;                  {indicate we created a new connection}
    sys_error_none (stat);             {indicate no error}
    return;                            {normal return when new connection created}
    end;
{
*   This attempt to establish a connection failed.  ERR is the system error
*   code describing why.
}
  if debug_inet >= 1 then begin
    stat.sys := err;
    sys_msg_parm_vstr (msg_parm[2], rinfo.isp);
    sys_error_print (stat, 'email', 'dialup_error', msg_parm, 2);
    end;

  if rinfo.conn.sys <> handle_none_k then begin {need to close handle ?}
    stat.sys := RasHangUpA (rinfo.conn.sys); {close the RAS connection}
    rinfo.conn.sys := handle_none_k;   {indicate no connect attempt currently open}
    if sys_error(stat) then return;
    end;

  sys_wait (rinfo.sec_redial_wait);    {wait as specified before trying again}
  goto loop_connect;                   {try to establish connection again}
  end;
{
********************************************************************
*
*   Subroutine INET_DISCONNECT (RINFO, STAT)
*
*   Disconnect from a remote system.  This routine may only be called
*   if a previous call to INET_CONNECT returned NEW_CONN TRUE and reported
*   no error.
}
procedure inet_disconnect (            {disconnect from remote system}
  in out  rinfo: smtp_rinfo_t;         {info about the remote system}
  out     stat: sys_err_t);            {returned completion status code}
  val_param;

const
  max_msg_parms = 2;                   {max parameters we can pass to a message}

var
  s: string_var80_t;                   {scratch var string}
  msg_parm:                            {parameter references for messages}
    array[1..max_msg_parms] of sys_parm_msg_t;

begin
  s.max := size_char(s.str);           {init local var string}
  sys_error_none (stat);               {init to no error occurred}

  stat.sys := RasHangUpA (rinfo.conn.sys); {try to close the RAS connection}

  sys_clock_str1 (sys_clock, s);       {make current date/time string}
  if debug_inet >= 1 then begin
    sys_msg_parm_vstr (msg_parm[1], s);
    sys_msg_parm_vstr (msg_parm[2], rinfo.isp);
    end;

  if sys_error(stat)
    then begin                         {error on attempt to close connection}
      if debug_inet >= 1 then begin
        sys_error_print (stat, 'email', 'dialup_close_err', msg_parm, 2);
        end;
      end
    else begin                         {connection closed without error}
      rinfo.conn.sys := handle_none_k;
      if debug_inet >= 1 then begin
        sys_message_parms ('email', 'dialup_closed', msg_parm, 2);
        end;
      end
    ;
  end;
