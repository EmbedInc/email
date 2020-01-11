{   Program SENDMAIL <destination address 1> [...<destination address N>]
*
*   Send a mail message to the indicated destination addresses.  The body
*   of the mail message is read from standard input until an end of file
*   is received.
*
*   This program is intended to replace the Unix SENDMAIL program
*   /usr/lib/sendmail, since it is nearly impossible to get that program
*   to do what you want.
*
*   SENDMAIL only routes messages from one program to another.  It must
*   therefore ultimately translate the destination address into the
*   pathname and command line arguments of another mailer program.
*   The original address is translated thru the "mail.adr" environment file
*   set.  The first domain name of the resulting address is stripped off
*   and used to decide which mailer to invoke.
}
program sendmail;
%include 'base.ins.pas';
%include 'email.ins.pas';

const
  max_msg_parms = 16;                  {max parameters we can pass to a message}
  max_unique_fnam_k = 32;              {max allowed unique name sequence number}

var
  y: sys_int_machine_t;                {year}
  tf: boolean;                         {TRUE/FALSE returned by mailer command}
  unique_n: sys_int_machine_t;         {number to generate unique name from}
  adr_n: sys_int_machine_t;            {number of dest address currently doing}
  n_msg: sys_int_machine_t;            {number of messages in MSG_PARM}
  msg:                                 {scratch message name}
    %include '(cog)lib/string80.ins.pas';
  fnam_unique,                         {unique file name component}
  suffix_script:                       {script file name suffix on this system}
    %include '(cog)lib/string_leafname.ins.pas';
  tnam,                                {scratch tree name}
  fnam_body,                           {name of file containing message body}
  fnam_shell,                          {name of file containing optional shell script}
  fnam_script,                         {name of file containing mailer script}
  fnam_temp:                           {temp file prefix for use in scripts}
    %include '(cog)lib/string_treename.ins.pas';
  conn_lock: file_conn_t;              {handle to interlock file}
  conn_out: file_conn_t;               {scratch connection handle to output file}
  conn_in: file_conn_t;                {scratch connection handle to input file}
  adr: email_adr_t;                    {descriptor for destination email address}
  adr_from: email_adr_t;               {descriptor for source email address}
  adry: email_adr_t;                   {scratch email address descriptor}
  tzone: sys_tzone_k_t;                {our time zone ID}
  hours_west: real;                    {hours west of CUT for our time zone}
  daysave: sys_daysave_k_t;            {our daylight savings time strategy}
  date: sys_date_t;                    {current date expansion}
  str_year,                            {strings for various date components}
  str_month,
  str_day,
  str_hour,
  str_minute,
  str_second:
    %include '(cog)lib/string4.ins.pas';
  pick: sys_int_machine_t;             {number of token picked from list}
  mailer_try: sys_int_machine_t;       {number of attempt to run mailer}
  p: string_index_t;                   {parse index}
  retry_message: boolean;              {print retry message when TRUE}
  done_header: boolean;                {TRUE when done copying message header}
  from_created: boolean;               {TRUE if FROM adress descriptor created}
  mailer,                              {mailer name from first domain name}
  sys,                                 {first system name of mail address}
  sys_local:                           {local system name for editing return address}
    %include '(cog)lib/string80.ins.pas';
  adr_full,                            {full mail address sent on to mailer program}
  adr2,                                {address with first system name removed}
  buf,                                 {one line buffer}
  adr_send,                            {sender's email address}
  info_site,                           {info string for local site}
  cmd,                                 {command string for executing mailer}
  token:                               {scratch token}
    %include '(cog)lib/string256.ins.pas';
  exstat: sys_sys_exstat_t;            {unused}
  msg_parm:                            {parameter references for messages}
    array[1..max_msg_parms] of sys_parm_msg_t;
  stat: sys_err_t;                     {completion status code}

label
  next_name, done_read_lsys, next_adr, retry_mailer, loop_copy1, no_edit,
  done_copy1, loop_copy2, done_copy2, loop_copy3, leave;

begin
  string_cmline_init;                  {initialize for reading command line}
  adr_n := 0;                          {init to before processing first address}
{
*   Determine a unique file name we can use.  It will be /tmp/sendmailN,
*   where N is an integer greater than zero.  An interlock file will be left
*   open for write the whole time.  This insures that no other concurrent
*   invocations of the SENDMAIL program will pick the same file name.
*   The unique file name will be put in FNAM_UNIQUE.  This will be used
*   as a prefix for all other file names.
}
  unique_n := 0;                       {make initial unique file name number}
next_name:                             {back here to try new unique name}
  unique_n := unique_n + 1;            {make new unique number}
  if unique_n > max_unique_fnam_k then begin {past limit, assume something wrong ?}
    sys_message_bomb ('sendmail_prog', 'unique_name_too_many', nil, 0);
    end;
  string_f_int (token, unique_n);      {make string from unique number}
  string_vstring (tnam, '/tmp/sendmail'(0), -1);
  string_append (tnam, token);         {make full unique file name}
  string_treename (tnam, fnam_unique); {put file name into system format}
  file_open_write_bin (fnam_unique, '', conn_lock, stat); {try to open lock file}
  if sys_error(stat) then goto next_name; {couldn't open lock file, try new name}
{
*   The lock file has been opened.  Its name is in FNAM_UNIQUE.
}
  case sys_os_k of                     {set script file suffix for this system}
sys_os_win32_k: begin                  {Microsoft Win32 API}
      string_vstring (suffix_script, '.bat', 4);
      end;
otherwise                              {default is no particular suffix is required}
    suffix_script.len := 0;
    end;                               {end of OS cases}

  string_copy (fnam_unique, fnam_script); {make mailer script file name}
  string_appendn (fnam_script, '_script', 7);
  string_append (fnam_script, suffix_script);

  string_copy (fnam_unique, fnam_shell); {make optional shell script file name}
  string_appendn (fnam_shell, '_shell', 6);
  string_append (fnam_shell, suffix_script);

  string_copy (fnam_unique, fnam_body); {make file name for holding message body}
  string_appendn (fnam_body, '_body', 5);

  string_copy (fnam_unique, fnam_temp); {make temporary file name for shell scripts}
  string_appendn (fnam_temp, '__', 2);
{
*   Set all the strings that relate to the current date and time.
}
  sys_timezone_here (                  {get info about current time zone}
    tzone,                             {time zone ID}
    hours_west,                        {hours west of CUT}
    daysave);                          {daylight savings time strategy}
  sys_clock_to_date (                  {make date descriptor of current time}
    sys_clock,                         {the current time}
    tzone,                             {ID of our time zone}
    hours_west,                        {hours west of CUT}
    daysave,                           {daylight savings time strategy to use}
    date);                             {returned date descriptor}

  sys_date_string (date, sys_dstr_year_k, 4, str_year, stat);
  sys_date_string (date, sys_dstr_mon_k, 2, str_month, stat);
  sys_date_string (date, sys_dstr_day_k, 2, str_day, stat);
  sys_date_string (date, sys_dstr_hour_k, 2, str_hour, stat);
  sys_date_string (date, sys_dstr_min_k, 2, str_minute, stat);
  sys_date_string (date, sys_dstr_sec_k, 2, str_second, stat);
{
*   Get the static info for the local system.  This comes from the
*   LOCAL_SYSTEM message in the MAILERS file.  The first line is the
*   local system name.  The second line contains info text that will be
*   added to any user-specific info in the return address.
}
  sys_local.len := 0;                  {init to local system name not known}
  info_site.len := 0;                  {init to no local site text available}

  file_open_read_msg (                 {open the message for read}
    string_v('mailers'(0)),            {generic message file name}
    string_v('local_system'(0)),       {name of message within file}
    nil,                               {message parameter references}
    0,                                 {number of parameters passed to message}
    conn_in,                           {connection handle to message text}
    stat);
  if not sys_error_check (stat, 'sendmail_prog', 'open_message_system', nil, 0)
      then begin                       {message opened successfully}

    file_read_msg (conn_in, sys_local.max, sys_local, stat); {read local sys name}
    if sys_error_check (stat, 'sendmail_prog', 'read_system', nil, 0)
        then begin
      sys_local.len := 0;              {indicate local system name not known}
      end;
    if file_eof(stat) then goto done_read_lsys;

    file_read_msg (conn_in, info_site.max, info_site, stat); {get site info text}
    if sys_error_check (stat, 'sendmail_prog', 'read_system', nil, 0)
        then begin
      info_site.len := 0;
      end;

done_read_lsys:                        {all done reading LOCAL_SYSTEM message}
    file_close (conn_in);              {close connection to message}
    end;
{
*   Make the file for holding the mail message body.  The mail message
*   body is read from standard input.
}
  file_open_stream_text (              {make connection for reading standard input}
    sys_sys_iounit_stdin_k,            {system I/O unit to connect to}
    [file_rw_read_k],                  {desired read/write access}
    conn_in,                           {returned connection handle}
    stat);
  sys_error_abort (stat, 'sendmail_prog', 'open_stdin', nil, 0);

  file_open_write_text (fnam_body, '', conn_out, stat); {open body file for write}
  sys_error_abort (stat, 'sendmail_prog', 'open_body_write', nil, 0);
{
*   Copy the message body into the temporary message file.
*   The return address will be translated, if appropriate.
}
  done_header := false;                {init to next line is still in header}
  adr_send.len := 0;                   {init to sender's address unknown}
  from_created := false;               {init to FROM descriptor not created yet}

loop_copy1:                            {back here to copy next message body line}
  file_read_text (conn_in, buf, stat); {read one line from source}
  if file_eof(stat) then goto done_copy1; {hit end of message body text ?}
  sys_error_abort (stat, 'sendmail_prog', 'read_body', nil, 0);
  string_unpad (buf);                  {delete trailing spaces}
  done_header :=                       {no more header after first blank line}
    done_header or (buf.len <= 0);

  if                                   {this is the start of a new header line ?}
      (not done_header) and            {still within the header ?}
      (buf.str[1] <> ' ')              {not continued from previous command line ?}
      then begin
    p := 1;                            {init BUF parse index}
    string_token (buf, p, token, stat); {get first token from this line}
    if sys_error(stat) then goto no_edit;
    string_upcase (token);             {make upper case for keyword matching}
    string_tkpick80 (token,
      'FROM: DATE:',
      pick);
    case pick of
{
*   FROM: <address>
}
1: begin
  if from_created then begin           {FROM address descriptor already exists ?}
    email_adr_delete (adr_from);       {delete old FROM address}
    end;
  email_adr_create (adr_from, util_top_mem_context); {create FROM email address}
  from_created := true;                {FROM address now definately exists}
  string_substr (buf, p, buf.len, token); {get rest of line after FROM:}
  email_adr_string_add (adr_from, token); {build address from address string}
  if                                   {only edit if coming from a local user}
      (adr_from.dom_first = 0) and     {no domain name ?}
      (adr_from.sys_first = 0) and     {no system name ?}
      (adr_from.user > 0)              {user name exists ?}
      then begin
    if adr_from.info.len <= 0 then begin {no info string specified ?}
      email_adr_create (adry, util_top_mem_context); {create scratch email address}
      email_adr_string_add (adry, token); {make another copy of address}
      email_adr_translate (adry);      {translate to get info string, if any}
      string_copy (adry.info, adr_from.info); {use info text from translated name}
      email_adr_delete (adry);         {done with temporary address descriptor}
      if info_site.len > 0 then begin  {local site info string exists ?}
        string_appendn (adr_from.info, ', ', 2); {separate the two info strings}
        string_append (adr_from.info, info_site); {append local site info string}
        end;
      end;
    email_adr_tkadd (                  {add local system name to return address}
      adr_from, sys_local, email_tktyp_sys_first_k);
    end;
  email_adr_t_string (adr_from, email_adrtyp_at_k, adr_send); {convert adr back to string}
  string_vstring (buf, 'From: '(0), -1); {build new return address line}
  if adr_from.info.len > 0 then begin  {there is an info string ?}
    string_append_token (buf, adr_from.info);
    string_append1 (buf, ' ');
    end;
  string_append1 (buf, '<');
  string_append (buf, adr_send);
  string_append1 (buf, '>');
  end;                                 {end of FROM: header command case}
{
*   DATE: <dweek>, <day> <mon> <year> <hh>:<mm>:<ss> <TZ>
*
*   This section works around the bug in Domain/OS mailer where year 100 is
*   reported instead of year 2000.  Note that the DATE: syntax is more
*   flexible than shown above (see RFC 822), but that this is what the
*   Domain/OS mailer produces.  If a year is detected less than 2000, then
*   the current date/time is substituted.
*
*   Each field is checked for matching the Domain/OS syntax above.  Nothing
*   is done if a mismatch is found or the year is at least 2000.  Otherwise
*   the whole DATE: command is replaced by one with the current date/time.
}
2: begin
  string_token (buf, p, token, stat);  {check day of week field}
  if sys_error(stat) then goto no_edit;
  if (token.len <= 1) or else (token.str[token.len] <> ',')
    then goto no_edit;

  string_token (buf, p, token, stat);  {check day of month field}
  if sys_error(stat) then goto no_edit;
  string_t_int (token, y, stat);
  if sys_error(stat) then goto no_edit;
  if (y < 1) or (y > 31) then goto no_edit;

  string_token (buf, p, token, stat);  {check month abbreviation field}
  if sys_error(stat) then goto no_edit;
  if token.len <> 3 then goto no_edit;

  string_token (buf, p, token, stat);  {check year field}
  if sys_error(stat) then goto no_edit;
  string_t_int (token, y, stat);
  if sys_error(stat) then goto no_edit;
  if y >= 2000 then goto no_edit;
  {
  *   This appears to be a Domain/OS erroneous date with the year less than
  *   2000.
  }
  string_vstring (buf, 'Date: '(0), -1); {init new date string}
  sys_date_string (date, sys_dstr_daywk_abbr_k, string_fw_freeform_k, token, stat);
  string_append (buf, token);

  string_appendn (buf, ', ', 2);
  sys_date_string (date, sys_dstr_day_k, string_fw_freeform_k, token, stat);
  string_append (buf, token);

  string_append1 (buf, ' ');
  sys_date_string (date, sys_dstr_mon_abbr_k, string_fw_freeform_k, token, stat);
  string_append (buf, token);

  string_append1 (buf, ' ');
  string_append (buf, str_year);

  string_append1 (buf, ' ');
  string_append (buf, str_hour);
  string_append1 (buf, ':');
  string_append (buf, str_minute);
  string_append1 (buf, ':');
  string_append (buf, str_second);

  string_append1 (buf, ' ');
  sys_date_string (date, sys_dstr_tz_abbr_k, string_fw_freeform_k, token, stat);
  string_append (buf, token);
  end;                                 {end of DATE: header command case}

      end;                             {end of header command cases}
no_edit:                               {jump here to not edit this line}
    end;                               {done trying to edit this line}

  file_write_text (buf, conn_out, stat); {write line to temp message body file}
  sys_error_abort (stat, 'sendmail_prog', 'write_body', nil, 0);
  goto loop_copy1;                     {back to copy next line in message}

done_copy1:                            {hit end of message body}
  file_close (conn_in);                {close connection to message body source}
  file_close (conn_out);               {all done writing temporary message body file}
  if not from_created then begin       {no FROM address found in message header ?}
    email_adr_create (adr_from, util_top_mem_context); {create empty FROM address}
    end;
{
*   Back here each new destination address to send the same message to.
}
next_adr:                              {back here each new destination address}
  string_cmline_token (buf, stat);     {get address and info string}
  adr_n := adr_n + 1;                  {make number of this destination address}
  if adr_n <= 1
    then begin                         {this is first command line token}
      string_cmline_req_check (stat);  {at least one destination address required}
      end
    else begin                         {this is not first destination address}
      if string_eos(stat) then goto leave; {exhausted destination address list ?}
      sys_msg_parm_int (msg_parm[1], adr_n);
      sys_error_abort (stat, 'string', 'cmline_arg_error', msg_parm, 1);
      end
    ;

  email_adr_create (adr, util_top_mem_context); {create an email address descriptor}
  email_adr_string_add (adr, buf);     {init with address as given on command line}
  email_adr_translate (adr);           {translate thru environment file set}
{
*   The fully translated email address is in address descriptor ADR.
*   Now use this to set the following strings:
*
*   MAILER  -  Name of mailer to use.  This comes from the first domain name.
*     The mailer script will be the expansion of message mailer_<mailer>.
*   ADR_FULL  -  Full mail address after first domain name removed to make
*     mailer name.
*   SYS  -  First system name.
*   ADR2  -  Same as ADR_FULL with first system name removed.
}
  if adr.dom_first > 0
    then begin                         {a domain name exists}
      string_list_pos_abs (adr.names, adr.dom_first); {go to first domain name}
      string_copy (adr.names.str_p^, mailer); {first domain name becomes mailer name}
      email_adr_tkdel (adr, email_tktyp_dom_first_k); {remove from adr descriptor}
      string_upcase (mailer);          {mailer names are case-insensitive}
      end
    else begin                         {no domain name exists}
      mailer.len := 0;                 {make mailer name}
      end
    ;

  email_adr_t_string (                 {make string from current email address}
    adr,                               {input address descriptor}
    email_adrtyp_at_k,                 {use "@" instead of "!" notation}
    adr_full);                         {returned string}

  if adr.sys_first > 0
    then begin                         {a system name exists}
      string_list_pos_abs (adr.names, adr.sys_first); {go to first system name}
      string_copy (adr.names.str_p^, sys); {make copy of first system name}
      email_adr_tkdel (adr, email_tktyp_sys_first_k); {remove from adr descriptor}
      end
    else begin                         {no system name exists}
      sys.len := 0;
      end
    ;

  email_adr_t_string (                 {make string from current email address}
    adr,                               {input address descriptor}
    email_adrtyp_at_k,                 {use "@" instead of "!" notation}
    adr2);                             {output string, address without first system}
{
*   Create the script file by expanding the appropriate MAILER_xxx message.
}
  mailer_try := 0;                     {init number of times tried to run mailer}
  retry_message := false;              {init to not print message on mailer retry}
  string_vstring (msg, 'mailer_'(0), -1); {fixed part of message name}
  string_append (msg, mailer);         {append mailer name to message name}

retry_mailer:                          {back here to retry with default mailer}
  if mailer_try >= 1 then begin        {this is a re-try ?}
    if mailer_try >= 2 then begin      {already failed twice ?}
      sys_msg_parm_vstr (msg_parm[1], adr_full);
      sys_message_bomb ('sendmail_prog', 'undeliverable', msg_parm, 1);
      end;
    if retry_message then begin
      sys_message ('sendmail_prog', 'mailer_retry');
      end;
    string_vstring (msg, 'mailer_'(0), -1); {make default mailer message name}
    end;
  mailer_try := mailer_try + 1;        {count one more try to run mailer}

  sys_msg_parm_vstr (msg_parm[1], fnam_script); {pathname of mailer script file}
  sys_msg_parm_vstr (msg_parm[2], fnam_shell); {pathname of optional shell script}
  sys_msg_parm_vstr (msg_parm[3], fnam_body); {pathname of message body file}
  sys_msg_parm_vstr (msg_parm[4], adr_full); {full destination mail address}
  sys_msg_parm_vstr (msg_parm[5], sys); {first destination system name}
  sys_msg_parm_vstr (msg_parm[6], adr2); {mail adr with first system name removed}
  sys_msg_parm_vstr (msg_parm[7], adr_send); {sender's email address}
  sys_msg_parm_vstr (msg_parm[8], adr_from.info); {sending user's info string}
  sys_msg_parm_vstr (msg_parm[9], mailer); {mailer name}
  sys_msg_parm_vstr (msg_parm[10], str_year);
  sys_msg_parm_vstr (msg_parm[11], str_month);
  sys_msg_parm_vstr (msg_parm[12], str_day);
  sys_msg_parm_vstr (msg_parm[13], str_hour);
  sys_msg_parm_vstr (msg_parm[14], str_minute);
  sys_msg_parm_vstr (msg_parm[15], str_second);
  sys_msg_parm_vstr (msg_parm[16], fnam_temp);
  n_msg := 16;                         {number of messages in MSG_PARM}

  file_open_read_msg (                 {open the message for read}
    string_v('mailers'(0)),            {generic message file name}
    msg,                               {name of message within file}
    msg_parm,                          {message parameter references}
    n_msg,                             {number of parameters passed to message}
    conn_in,                           {connection handle to message text}
    stat);
  if file_not_found(stat) then begin   {no such message exists ?}
    goto retry_mailer;                 {try again with default mailer}
    end;
  retry_message := true;               {print message on retry from now on}
  if sys_error_check (stat, 'sendmail_prog', 'open_message_script', nil, 0)
      then begin
    goto retry_mailer;                 {try again with default mailer}
    end;

  file_open_write_text (fnam_script, '', conn_out, stat); {open script for write}
  if sys_error_check (stat, 'sendmail_prog', 'open_script_write', nil, 0)
      then begin
    file_close (conn_in);              {close connection to mailer message}
    goto retry_mailer;                 {try again with default mailer}
    end;

loop_copy2:                            {back here to copy next script line}
  file_read_msg (conn_in, token.max, token, stat); {read one line from source}
  if file_eof(stat) then goto done_copy2; {hit end of source file ?}
  if sys_error_check (stat, 'sendmail_prog', 'read_script', nil, 0)
      then begin
    file_close (conn_in);              {close connection to mailer message}
    file_close (conn_out);             {close connection to script file}
    goto retry_mailer;                 {try again with default mailer}
    end;

  file_write_text (token, conn_out, stat); {write line to temp script file}
  if sys_error_check (stat, 'sendmail_prog', 'write_script', nil, 0)
      then begin
    file_close (conn_in);              {close connection to mailer message}
    file_close (conn_out);             {close connection to script file}
    goto retry_mailer;                 {try again with default mailer}
    end;
  goto loop_copy2;                     {back to copy next line in script}
done_copy2:                            {hit end of script}
  file_close (conn_in);                {close connection to script source}
  file_close (conn_out);               {all done writing temporary script file}
{
*   Read the SHELL message.  The first line will be the command submitted to
*   the system for execution.  The remaining lines are saved in the optional
*   SHELL file that may be referenced by the first line.
}
  file_open_read_msg (                 {open the message for read}
    string_v('mailers'(0)),            {generic message file name}
    string_v('shell'(0)),              {name of message within file}
    msg_parm,                          {message parameter references}
    n_msg,                             {number of parameters passed to message}
    conn_in,                           {connection handle to message text}
    stat);
  sys_error_abort (stat, 'sendmail_prog', 'open_message_shell', nil, 0);

  file_read_msg (conn_in, cmd.max, cmd, stat); {read first line of shell message}
  sys_error_abort (stat, 'sendmail_prog', 'read_shell', nil, 0);

  file_open_write_text (fnam_shell, '', conn_out, stat); {open SHELL temp file}
  sys_error_abort (stat, 'sendmail_prog', 'open_shell', nil, 0);

loop_copy3:                            {back here to copy each new line}
  file_read_msg (conn_in, token.max, token, stat); {read one line from source}
  if not file_eof(stat) then begin     {not hit end of file yet ?}
    sys_error_abort (stat, 'sendmail_prog', 'read_shell', nil, 0);
    file_write_text (token, conn_out, stat); {write line to temp script file}
    sys_error_abort (stat, 'sendmail_prog', 'write_shell', nil, 0);
    goto loop_copy3;                   {back to copy next line}
    end;

  file_close (conn_out);               {close SHELL file}
  file_close (conn_in);                {all done with SHELL message}
{
*   Execute the final mailer command.  The command line is in CMD.
}
  sys_run_wait_stdsame (cmd, tf, exstat, stat); {execute the mailer command}
  sys_msg_parm_vstr (msg_parm[1], cmd);
  if sys_error_check (stat, 'sendmail_prog', 'mailer_error', msg_parm, 1)
      then begin
    goto retry_mailer;                 {try again with default mailer}
    end;
  if not tf then begin                 {mailer command returned FALSE status ?}
    sys_message_parms ('sendmail_prog', 'mailer_failed', msg_parm, 1);
    goto retry_mailer;                 {try again with default mailer}
    end;
{
*   Message sent.  Clean up and try again with next destination address.
}
  email_adr_delete (adr);              {delete destination address descriptor}
  file_delete_name (fnam_script, stat); {delete mailer script file}
  file_delete_name (fnam_shell, stat); {delete temporary shell script file}
  goto next_adr;                       {back to process next destination address}
{
*   All messages sent.  Clean up and leave.
}
leave:
  email_adr_delete (adr_from);         {delete email source address}
  file_delete_name (fnam_body, stat);  {delete temporary files}
  file_close (conn_lock);              {release lock on this unique name}
  file_delete_name (fnam_unique, stat); {delete unique name lock file, if possible}
  end.
