{   Public include file for EMAIL library.  This library contains routines for
*   email handling.
}
const
{
*   Error status values related to the EMAIL subsystem.
}
  email_subsys_k = -16;                {our subsystem ID}

  email_stat_queue_end_k = 1;          {end of queue encountered}
  email_stat_qent_open_k = 2;          {a queue entry is already open}
  email_stat_qent_nopen_k = 3;         {no queue entry currently open}
  email_stat_qopt_cmd_get_k = 4;       {error reading command from OPTIONS file}
  email_stat_qopt_cmd_bad_k = 5;       {unrecognized command in SMTP OPTIONS file}
  email_stat_qopt_parm_err_k = 6;      {err with command parm in OPTIONS file}
  email_stat_qopt_parm_extra_k = 7;    {too many parms in SMTP queue OPTIONS file}
  email_stat_qopt_parm_missing_k = 8;  {missing parm in SMTP queue OPTIONS file}
  email_stat_smtp_err_k = 9;           {general SMTP comm or handshaking error}
  email_stat_smtp_noqueue_k = 10;      {no such mail queue}
  email_stat_smtp_queue_full_k = 11;   {mail queue full or unrecognized error}
  email_stat_smtp_no_in_queue_k = 12;  {no mail input queue specified}
  email_stat_mailfeed_loop_k = 13;     {circular dependency in MAILFEED env set}
  email_stat_envcmd_bad_k = 14;        {bad command in environment file set}
  email_stat_envline_extra_k = 15;     {extra email after env file command}
  email_stat_envparm_missing_k = 16;   {missing parm to env file command}
  email_stat_envparm_err_k = 17;       {bad parameter to env file command}
  email_stat_smtp_resp_err_k = 18;     {error response from SMTP server}
  email_stat_mail_relay_k = 26;        {client tried to relay mail thru us}
{
*   Other constants.
}
  smtp_port_k = 25;                    {standard SMTP server port number}
  smtp_maxcladr_k = 1;                 {max simultaneous clients from same address}

type
  email_tktyp_k_t = (                  {type of incremental email address token}
    email_tktyp_dom_first_k,           {first (most global) domain name}
    email_tktyp_dom_last_k,            {last (most local) domain name}
    email_tktyp_sys_first_k,           {first (farthest from user) system name}
    email_tktyp_sys_last_k,            {last (closest to user) system name}
    email_tktyp_user_k);               {user name (last token of all)}

  email_adrtyp_k_t = (                 {email address string types}
    email_adrtyp_at_k,                 {use "@" when possible (joe@acme.com)}
    email_adrtyp_bang_k);              {bang path (acme!joe.com)}

  email_adr_t = record                 {data about one email address}
    names: string_list_t;              {string list where names are stored}
    info: string_var132_t;             {info text about particular user}
    dom_first: sys_int_machine_t;      {line number of most global domain name, if any}
    dom_last: sys_int_machine_t;       {line number of most local domain name, if any}
    sys_first: sys_int_machine_t;      {line number of first system name, if any}
    sys_last: sys_int_machine_t;       {line number of last system name, if any}
    user: sys_int_machine_t;           {line number of user name, if any}
    end;

  ehead_read_t = record                {state for reading email message header}
    buf: string_var8192_t;             {line read from stream but not used yet}
    buff: boolean;                     {BUF contains a read but unused line}
    conn_p: file_conn_p_t;             {pointer to email message input stream}
    end;

  smtp_code_resp_t = array[1..3] of char; {3 digit SMTP command response code}

  smtp_queue_options_t = record        {all info that comes from queue OPTIONS files}
    localsys: string_var256_t;         {fully qualified name of local system}
    recvdom: string_var256_t;          {list of domains we handle mail for, upper case}
    remotesys: string_var256_t;        {name needed to get to remote system}
    rem_resp: string_var256_t;         {name as reported by remote system}
    remotepswd: string_var80_t;        {password for sending to remote server}
    remoteuser: string_var80_t;        {user name for sending to remote server}
    port: sys_inet_port_id_t;          {port ID of server on remote system, 0 = def}
    inq: string_leafname_t;            {default generic input queue name}
    smtp_cmd: string_treename_t;       {SMTP executable file, may be full pathname}
    pswdget: string_var80_t;           {password from clients for getting from queue}
    pswdput: string_var80_t;           {password from clients for sending to us}
    bouncefrom: string_var80_t;        {FROM address for bounce messages, lower case}
    sendmail: boolean;                 {TRUE if send mail to local SENDMAIL program}
    autosend: boolean;                 {TRUE if supposed to dequeue after write ents}
    pop3: boolean;                     {TRUE if POP3 server allowed to dump queue}
    userput: boolean;                  {clients must give user name to send to us}
    localqueue: boolean;               {local queue of specified name exists}
    localread: boolean;                {OPTIONS file was read in the local queue}
    end;

  smtp_qrclose_k_t = (                 {options for close queue entry open for read}
    smtp_qrclose_del_k,                {delete queue entry}
    smtp_qrclose_undeliv_k);           {remaining adr list ents undeliv, send msg}
  smtp_qrclose_t = set of smtp_qrclose_k_t; {all the flags in one word}

  smtp_qconn_read_t = record           {handle for reading an SMTP queue}
    qdir: string_treename_t;           {tree name of this queue directory}
    opts: smtp_queue_options_t;        {all the info from OPTIONS file set}
    mem_p: util_mem_context_p_t;       {our private memory context}
    list_ents: string_list_t;          {list of all queue control file entries}
    conn_c: file_conn_t;               {connection handle to current control file}
    list_adr: string_list_t;           {destination addresses for current entry}
    conn_m: file_conn_t;               {connection handle to current message file}
    ent_open: boolean;                 {TRUE if queue entry currently open}
    end;

  smtp_rqmeth_k_t = (                  {methods for requesting our queued mail}
    smtp_rqmeth_none_k,                {no request method specified}
    smtp_rqmeth_turn_k,                {SMTP TURN command}
    smtp_rqmeth_etrn1_k,               {simple ETRN, no option chars, see RFC 1985}
    smtp_rqmeth_etrn2_k,               {full ETRN with option chars, see RFC 1985}
    smtp_rqmeth_mqrun_k,               {MAILQRUN method (Ultranet)}
    smtp_rqmeth_qsnd_k);               {SMTP QSND command (Net1Plus)}
{
*   The following is all the information we need to send and receive email
*   to/from a remote system.  All fields may not be relevant for all remote
*   and/or local systems.  This data structure should always be initialized
*   with routine SMTP_RINFO_INIT to avoid compatibility problems when new
*   fields are added.  Fields that are not used or needed must be left as
*   set by SMTP_RINFO_INIT.
}
  smtp_rfld_k_t = (                    {IDs for some fields in SMTP_RINFO_T}
    smtp_rfld_name_k,                  {field NAME}
    smtp_rfld_mach_k,                  {field MACHINE}
    smtp_rfld_qname_k,                 {field QNAME}
    smtp_rfld_isp_k,                   {field ISP}
    smtp_rfld_domisp_k,                {field DOMAIN_ISP}
    smtp_rfld_phbook_k,                {field PHBOOK_ENT}
    smtp_rfld_phnum_k,                 {field PHNUM}
    smtp_rfld_user_k,                  {field USER}
    smtp_rfld_psw_k,                   {field PASSWORD}
    smtp_rfld_port_k,                  {field PORT_SMTP}
    smtp_rfld_sinact_k,                {field SEC_INACT_DONE}
    smtp_rfld_sact_k,                  {field SEC_ACTIVE_DONE}
    smtp_rfld_sredial_k,               {field SEC_REDIAL_WAIT}
    smtp_rfld_mdial_k,                 {field N_MAX_DIAL}
    smtp_rfld_dom_k,                   {field DOMAINS}
    smtp_rfld_meth_k,                  {field RQMETH}
    smtp_rfld_cnct_k);                 {field CONNECT}
  smtp_rfld_t = set of smtp_rfld_k_t;

  smtp_rinfo_t = record                {info about a remote dialup location}
    name: string_var80_t;              {our name for this collection of state}
    machine: string_var256_t;          {remote machine name}
    qname: string_var80_t;             {name of our queue for mail to remote sys}
    isp: string_var80_t;               {name of remote internet service provider}
    domain_isp: string_var80_t;        {ISP's domain name}
    phbook_ent: string_var80_t;        {system phonebook entry name}
    phnum: string_var80_t;             {phone number, only 0-9, #, and *}
    user: string_var80_t;              {user name to log onto remote system}
    password: string_var80_t;          {password for this user on remote system}
    port_smtp: sys_int_machine_t;      {TCP/IP port on remote machine of SMTP server}
    sec_inact_done: real;              {sec assume done on no server activity at all}
    sec_active_done: real;             {sec assume done after server activity}
    sec_redial_wait: real;             {seconds to wait between redial attempts}
    n_max_dial: sys_int_machine_t;     {max allowed total dial tries, 0 = no limit}
    domains: string_var8192_t;         {names of the domains receiving mail for}
    rqmeth: smtp_rqmeth_k_t;           {method used to request mail from remote sys}
    connect: boolean;                  {TRUE if need to actively connect to remote}
    conn: file_conn_t;                 {remote conn handle, use is system dependent}
    userset: smtp_rfld_t;              {element for each field set by the user}
    end;

  smtp_client_p_t = ^smtp_client_t;
  smtp_client_t = record               {thread arg for client, must release bef exit}
    mem_p: util_mem_context_p_t;       {pnt to private mem context for this thread}
    conn: file_conn_t;                 {client TCP/IP connection}
    adr: sys_inet_adr_node_t;          {network address of machine client is on}
    port: sys_inet_port_id_t;          {port number on client machine}
    id: sys_int_machine_t;             {unique ID number for this client}
    inq: string_leafname_t;            {input queue, empty for use default}
    open: boolean;                     {connection to client is open}
    end;
{
*   Publicly visible debug levels.
*   These debug levels are intended to be set from 0 to 10, where 0 is
*   "production" operation where no extra debug messages are printed, and
*   10 causes maximum debug messages.
}
var (email_debug)
  debug_inet: sys_int_machine_t        {debug level for INET routines}
    := 0;
  debug_smtp: sys_int_machine_t        {debug level for SMTP routines}
    := 0;
{
*   Entry points.
}
procedure ehead_read_close (           {end reading email header, release resources}
  in out  eh: ehead_read_t;            {header reading state, returned invalid}
  out     stat: sys_err_t);            {completion status}
  val_param; extern;

procedure ehead_read_cmd (             {get next command from email header}
  in out  eh: ehead_read_t;            {state for reading email message header}
  in out  cmd: univ string_var_arg_t;  {command name, ":" stripped, upper case}
  in out  body: univ string_var_arg_t; {body of whole command after ":"}
  out     stat: sys_err_t);            {completion status, EOF at end of header}
  val_param; extern;

procedure ehead_read_open (            {set up for reading an email message header}
  out     eh: ehead_read_t;            {state for reading header, initialized}
  in out  conn: file_conn_t;           {connection to raw email message stream}
  out     stat: sys_err_t);            {completion status}
  val_param; extern;

procedure email_adr_create (           {create and init email address descriptor}
  out     adr: email_adr_t;            {descriptor to create and initialize}
  in out  mem: util_mem_context_t);    {mem context to use for private memory}
  val_param; extern;

procedure email_adr_delete (           {release all resources used by adr descriptor}
  in out  adr: email_adr_t);           {adr descriptor to delete, returned useless}
  val_param; extern;

procedure email_adr_domain (           {get domain of email address}
  in out  adr: email_adr_t;            {email address description}
  in out  dom: univ string_var_arg_t); {returned full domain name, upper case}
  val_param; extern;

procedure email_adr_extract (          {extract adr and other info from email string}
  in      str: univ string_var_arg_t;  {input string, like after "FROM:", etc.}
  in out  adr: univ string_var_arg_t;  {returned just the pure email address string}
  in out  info: univ string_var_arg_t); {all the other non-address text in string}
  val_param; extern;

procedure email_adr_string_add (       {add string to existing email address}
  out     adr: email_adr_t;            {email address descriptor to add to}
  in      str: univ string_var_arg_t); {source email address string}
  val_param; extern;

procedure email_adr_t_string (         {create string from email address descriptor}
  in out  adr: email_adr_t;            {email address descriptor}
  in      adrtyp: email_adrtyp_k_t;    {desired string address format}
  in out  str: univ string_var_arg_t); {resulting email address string}
  val_param; extern;

procedure email_adr_tkadd (            {add token to email address}
  in out  adr: email_adr_t;            {email address descriptor to edit}
  in      tk: univ string_var_arg_t;   {new token to add}
  in      tktyp: email_tktyp_k_t);     {identifies the token type}
  val_param; extern;

procedure email_adr_tkdel (            {delete token from email address}
  in out  adr: email_adr_t;            {email address descriptor to edit}
  in      tktyp: email_tktyp_k_t);     {identifies which token to delete}
  val_param; extern;

procedure email_adr_translate (        {xlate email address thru mail.adr env files}
  in out  adr: email_adr_t);           {email address descriptor to translate}
  val_param; extern;

procedure inet_connect (               {connect to remote system, if needed}
  in out  rinfo: smtp_rinfo_t;         {info about the remote system}
  out     new_conn: boolean;           {TRUE on connected if previously wasn't}
  out     stat: sys_err_t);            {returned completion status code}
  val_param; extern;

procedure inet_cstr_crlf_put (         {send CRLF terminated string, C format}
  in      cstr: univ string;           {string, NULL terminated, no CRLF}
  in out  conn: file_conn_t;           {handle to internet stream to write to}
  out     stat: sys_err_t);            {returned completion status code}
  val_param; extern;

procedure inet_disconnect (            {disconnect from remote system}
  in out  rinfo: smtp_rinfo_t;         {info about the remote system}
  out     stat: sys_err_t);            {returned completion status code}
  val_param; extern;

procedure inet_str_crlf_put (          {send CRLF terminated string, 80 chars max}
  in      str: string;                 {string, blank padded or NULL term, no CRLF}
  in out  conn: file_conn_t;           {handle to internet stream to write to}
  out     stat: sys_err_t);            {returned completion status code}
  val_param; extern;

procedure inet_vstr_crlf_put (         {send CRLF terminated string, vstring format}
  in      vstr: univ string_var_arg_t; {string, doesn't include CRLF}
  in out  conn: file_conn_t;           {handle to internet stream to write to}
  out     stat: sys_err_t);            {returned completion status code}
  val_param; extern;

procedure inet_vstr_crlf_get (         {receive CRLF terminated string}
  in out  vstr: univ string_var_arg_t; {returned string, CRLF removed}
  in out  conn: file_conn_t;           {handle to internet stream to read from}
  out     stat: sys_err_t);            {returned completion status code}
  val_param; extern;

procedure smtp_autosend (              {de-queue queue entries in separate process}
  in      qtop_dir: univ string_var_arg_t; {name of top level queue directory}
  in      qloc_dir: univ string_var_arg_t; {name of specific queue directory}
  in      sync: boolean;               {run proc synchronously, get exit status}
  out     stat: sys_err_t);            {returned completion status code}
  val_param; extern;

procedure smtp_client_blacklist (      {blacklist a remote client}
  in out  cl: smtp_client_t);          {client to blacklist}
  val_param; extern;

procedure smtp_client_close (          {close conn to client and deallocate descriptor}
  in out  cl_p: smtp_client_p_t);      {pointer to client descriptor, returned NIL}
  val_param; extern;

procedure smtp_client_close_conn (     {close connection to client}
  in out  cl: smtp_client_t);          {descriptor for the client}
  val_param; extern;

procedure smtp_client_init;            {one-time initialization of CLIENT module}
  val_param; extern;

procedure smtp_client_log_err (        {write log entry describing error}
  in out  cl: smtp_client_t;           {info about the particular client}
  in      stat: sys_err_t;             {error status}
  in      subsys: string;              {name of subsystem, used to find message file}
  in      msg: string;                 {message name within subsystem file}
  in      parms: univ sys_parm_msg_ar_t; {array of parameter descriptors}
  in      n_parms: sys_int_machine_t); {number of parameters in PARMS}
  val_param; extern;

procedure smtp_client_log_stat_str (   {write log entry describing error}
  in out  cl: smtp_client_t;           {info about the particular client}
  in      stat: sys_err_t;             {error status}
  in      msg: string);                {user message, Pascal string}
  val_param; extern;

procedure smtp_client_log_stat_vstr (  {write log entry describing error}
  in out  cl: smtp_client_t;           {info about the particular client}
  in      stat: sys_err_t;             {error status}
  in      msg: univ string_var_arg_t); {user message, var string}
  val_param; extern;

procedure smtp_client_log_str (        {write log entry, Pascal string comment}
  in out  client: smtp_client_t;       {info about the particular client}
  in      str: string);                {log entry comment string}
  val_param; extern;

procedure smtp_client_log_vstr (       {write log entry, var string comment}
  in out  client: smtp_client_t;       {info about the particular client}
  in      str: univ string_var_arg_t); {log entry comment string}
  val_param; extern;

procedure smtp_client_new (            {create new initialized client descriptor}
  out     client_p: smtp_client_p_t);  {pointer to the new descriptor}
  val_param; extern;

function smtp_client_open (            {open or reject a new client connection}
  in out  cl: smtp_client_t)           {client descriptor}
  :boolean;                            {TRUE on connection accepted, FALSE on closed}
  val_param; extern;

procedure smtp_client_thread (         {thread routine for one SMTP client}
  in out  d: smtp_client_t);           {unique data for this client}
  extern;

procedure smtp_client_wrlock;          {exclusively lock write output}
  val_param; extern;

procedure smtp_client_wrunlock;        {release lock on write output}
  val_param; extern;

procedure smtp_mail_send_done (        {indicate done sending mail message}
  in out  conn: file_conn_t;           {connection handle to internet stream}
  out     stat: sys_err_t);            {returned completion status code}
  val_param; extern;

procedure smtp_mailline_get (          {get line of mail message}
  in out  conn: file_conn_t;           {connection handle to internet stream}
  in out  str: univ string_var_arg_t;  {string for this line of mail message}
  out     done: boolean;               {TRUE if hit end of mail msg, STR unused}
  out     stat: sys_err_t);            {returned completion status code}
  val_param; extern;

procedure smtp_mailline_put (          {send line of mail message}
  in      str: univ string_var_arg_t;  {mail message line to send}
  in out  conn: file_conn_t;           {connection handle to internet stream}
  out     stat: sys_err_t);            {returned completion status code}
  val_param; extern;

procedure smtp_queue_opts_get (        {read OPTIONS files and return info}
  in      qtop_dir: univ string_var_arg_t; {name of top level queue directory}
  in      qloc_dir: univ string_var_arg_t; {name of specific queue directory}
  out     opts: smtp_queue_options_t;  {returned values from OPTIONS files}
  out     stat: sys_err_t);            {returned completion status code}
  val_param; extern;

procedure smtp_queue_read_close (      {close connection to an SMTP queue}
  in out  qconn: smtp_qconn_read_t;    {handle to queue read connection}
  out     stat: sys_err_t);            {returned completion status code}
  val_param; extern;

procedure smtp_queue_read_ent (        {read next SMTP queue entry}
  in out  qconn: smtp_qconn_read_t;    {handle to queue read connection}
  out     to_list_p: string_list_p_t;  {list of destination addresses for this msg}
  out     mconn_p: file_conn_p_t;      {handle to open message file connection}
  out     stat: sys_err_t);            {set to EMAIL_STAT_QUEUE_END_K on queue end}
  val_param; extern;

procedure smtp_queue_read_ent_close (  {close this queue entry}
  in out  qconn: smtp_qconn_read_t;    {handle to queue read connection}
  in      flags: smtp_qrclose_t;       {flags for specific optional operations}
  out     stat: sys_err_t);            {returned completion status code}
  val_param; extern;

procedure smtp_queue_read_open (       {open an SMTP queue for read}
  in      qname: univ string_var_arg_t; {name of queue to open}
  in out  mem: util_mem_context_t;     {parent mem context for our new mem context}
  out     qconn: smtp_qconn_read_t;    {returned handle to queue read connection}
  out     stat: sys_err_t);            {returned completion status code}
  val_param; extern;

procedure smtp_queue_create_close (    {close queue entry open for creation}
  in out  conn_c: file_conn_t;         {connection handle to control file}
  in out  conn_a: file_conn_t;         {connection handle to addresses list file}
  in out  conn_m: file_conn_t;         {connection handle to mail message file}
  in      keep: boolean;               {TRUE for keep entry, FALSE for delete}
  out     stat: sys_err_t);            {returned completion status code}
  val_param; extern;

procedure smtp_queue_create_ent (      {create a new mail queue entry}
  in      qname: univ string_var_arg_t; {generic name of queue to create entry in}
  out     conn_c: file_conn_t;         {handle to open control file}
  out     conn_a: file_conn_t;         {handle to open addresses list file}
  out     conn_m: file_conn_t;         {handle to open mail message file}
  out     stat: sys_err_t);            {returned completion status code}
  val_param; extern;

function smtp_receive_wait (           {check for must wait for incoming mail}
  in      rinfo: smtp_rinfo_t)         {info about remote system}
  :boolean;                            {TRUE if must wait on incoming timeout}
  val_param; extern;

function smtp_recv (                   {get all mail from remote system into queue}
  in out  client: smtp_client_t;       {info on the remote client}
  in out  turn: boolean;               {in TRUE to allow TURN, TRUE on TURN received}
  out     stat: sys_err_t)             {returned completion status code}
  :boolean;                            {at least one message written to input queue}
  val_param; extern;

procedure smtp_request_mail (          {request remote system to send us mail}
  in      rinfo: smtp_rinfo_t;         {remote sys info, must already be connected}
  out     stat: sys_err_t);            {returned completion status code}
  val_param; extern;

procedure smtp_resp_check (            {get and check SMTP server response}
  in out  conn: file_conn_t;           {connection handle to internet stream}
  out     stat: sys_err_t);            {error on bad response}
  val_param; extern;

procedure smtp_resp_get (              {read entire response, return info}
  in out  conn: file_conn_t;           {connection handle to internet stream}
  out     code: smtp_code_resp_t;      {standard 3 digit response code}
  in out  str: univ string_var_arg_t;  {concatenated response string, blank sep}
  out     ok: boolean;                 {TRUE if command completed as specified}
  out     stat: sys_err_t);            {returned completion status code}
  val_param; extern;

procedure smtp_rinfo_init (            {init SMTP_RINFO_T to benign default values}
  out     rinfo: smtp_rinfo_t);        {data structure to fill in}
  val_param; extern;

procedure smtp_rinfo_read_env (        {update RINFO from data in environment files}
  in out  rinfo: smtp_rinfo_t;         {data structure to update, previously init}
  out     stat: sys_err_t);            {returned completion status code}
  val_param; extern;

procedure smtp_send (                  {send all mail in queue over existing connection}
  in out  conn: file_conn_t;           {connection handle to internet stream}
  in out  qconn: smtp_qconn_read_t;    {handle to SMTP queue open for read}
  in out  turn: boolean;               {issue TURN at end on TRUE, TRUE if TURNed}
  out     stat: sys_err_t);            {returned completion status code}
  val_param; extern;

procedure smtp_send_host (             {send a mail message to specified host}
  in      host: univ string_var_arg_t; {name of host machine to send to}
  in      opts: smtp_queue_options_t;  {options that apply to the message's queue}
  in out  mconn: file_conn_t;          {connection to the message}
  in out  adrlist: string_list_t;      {adr to send to, successfully sent adrs deleted}
  out     stat: sys_err_t);            {returned completion status code}
  val_param; extern;

procedure smtp_send_message (          {send message over existing connection}
  in out  hconn: file_conn_t;          {existing connection to the SMTP host}
  in      init: boolean;               {do SMTP initial handshake}
  in out  mconn: file_conn_t;          {connection to message file, at any position}
  in out  adrlist: string_list_t;      {list of destination addresses for this message}
  in      opts: smtp_queue_options_t;  {options that apply to the message's queue}
  out     stat: sys_err_t);            {returned completion status code}
  val_param; extern;

procedure smtp_send_queue (            {send all mail in a queue}
  in      qname: univ string_var_arg_t; {generic queue name}
  in      recv: boolean;               {try to receive incoming mail on TRUE}
  in      queue_in: univ string_var_arg_t; {name of input queue on RECV TRUE}
  out     stat: sys_err_t);            {returned completion status code}
  val_param; extern;

procedure smtp_send_queue_mx (         {send all mail in queue to hosts using MX lookup}
  in out  qconn: smtp_qconn_read_t;    {open connection for reading the queue}
  out     stat: sys_err_t);            {returned completion status code}
  val_param; extern;
