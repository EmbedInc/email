{   Routines for sending a single mail message to a single host.
}
module smtp_send_host;
define smtp_send_host;
%include 'email2.ins.pas';
{
********************************************************************************
*
*   Subroutine SMTP_SEND_HOST (HOST, OPTS, MCONN, ADRLIST, STAT)
*
*   Send a single mail message to a single host machine.
*
*   HOST is the name of the host machine to send to.
*
*   OPTS is the set of options that apply to the queue the message is in.  The
*   following fields in OPTS may be used:
*
*     LOCALSYS
*     REMOTEPSWD
*     REMOTEUSER
*     SMTP_CMD
*     BOUNCEFROM
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
}
procedure smtp_send_host (             {send a mail message to specified host}
  in      host: univ string_var_arg_t; {name of host machine to send to}
  in      opts: smtp_queue_options_t;  {options that apply to the message's queue}
  in out  mconn: file_conn_t;          {connection to the message}
  in out  adrlist: string_list_t;      {list of addresses}
  out     stat: sys_err_t);            {returned completion status code}
  val_param;

var
  node: sys_inet_adr_node_t;           {internet address of the remote host}
  hconn: file_conn_t;                  {connection to the remote host}
  null: string_var4_t;                 {null string}

label
  leave;

begin
  null.max := size_char(null.str);     {init local var string}
  null.len := 0;

  file_inet_name_adr (host, node, stat); {get address of the host machine}
  if sys_error(stat) then return;

  file_open_inetstr (                  {open internet connection to the remote host}
    node,                              {internet address of the host machine}
    smtp_port_k,                       {port on host to connect to}
    hconn,                             {returned connection to the host}
    stat);
  if sys_error(stat) then return;

  smtp_resp_check (hconn, stat);       {get and check initial response from server}
  if sys_error(stat) then goto leave;

  smtp_send_message (                  {send message over existing connection}
    hconn,                             {existing connection to the host}
    true,                              {do SMTP initial handshake before sending}
    mconn,                             {connection to message file, positioned at start}
    adrlist,                           {list of destination addresses for this message}
    opts,                              {options for the queue the message is from}
    stat);

leave:
  file_close (hconn);                  {close the connection to the host}
  end;
