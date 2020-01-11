{   Module of routines used for communicating over the internet.
}
module inet;
define inet_cstr_crlf_put;
define inet_str_crlf_put;
define inet_vstr_crlf_put;
define inet_vstr_crlf_get;
%include 'email2.ins.pas';

const
  cr_k = chr(13);                      {carriage return character}
  lf_k = chr(10);                      {line feed character}

var
  crlf: string_var4_t :=               {var string with carriage return, line feed}
    [max := sizeof(crlf.str), len := 2, str := [cr_k, lf_k, chr(0), chr(0)]];
{
*********************************************************************
*
*   Subroutine INET_VSTR_CRLF_PUT (VSTR, CONN, STAT)
*
*   Send the string in VSTR, followed by carriage return and line feed.
*   CONN is the connection handle to the internet stream to write to.
}
procedure inet_vstr_crlf_put (         {send CRLF terminated string, vstring format}
  in      vstr: univ string_var_arg_t; {string, doesn't include CRLF}
  in out  conn: file_conn_t;           {handle to internet stream to write to}
  out     stat: sys_err_t);            {returned completion status code}
  val_param;

begin
  if debug_inet >= 5 then begin
    writeln ('> ', vstr.str:vstr.len);
    end;

  file_write_inetstr (                 {send the string as passed in}
    vstr.str,                          {data buffer}
    conn,                              {internet stream connection handle}
    vstr.len,                          {number of bytes to write}
    stat);
  if sys_error(stat) then return;
  file_write_inetstr (                 {send the CRLF to terminate the line}
    crlf.str,                          {data buffer}
    conn,                              {internet stream connection handle}
    crlf.len,                          {number of bytes to write}
    stat);
  end;
{
*********************************************************************
*
*   Subroutine INET_CSTR_CRLF_PUT (CSTR, CONN, STAT)
*
*   Send the string in CSTR, followed by carriage return and line feed.
*   CSTR is a C-style string, which must be NULL terminated.
*   CONN is the connection handle to the internet stream to write to.
}
procedure inet_cstr_crlf_put (         {send CRLF terminated string, C format}
  in      cstr: univ string;           {string, NULL terminated, no CRLF}
  in out  conn: file_conn_t;           {handle to internet stream to write to}
  out     stat: sys_err_t);            {returned completion status code}
  val_param;

var
  vstr: string_var8192_t;              {var string copy of input string}

begin
  vstr.max := sizeof(vstr.str);        {init local var string}

  string_vstring (vstr, cstr, -1);     {convert input string to var string}
  inet_vstr_crlf_put (vstr, conn, stat); {send the var string}
  end;
{
*********************************************************************
*
*   Subroutine INET_STR_CRLF_PUT (STR, CONN, STAT)
*
*   Send the string in STR, followed by carriage return and line feed.
*   STR may be padded with blanks (which will be ignored), or NULL-terminated.
*   CONN is the connection handle to the internet stream to write to.
}
procedure inet_str_crlf_put (          {send CRLF terminated string, 80 chars max}
  in      str: string;                 {string, blank padded or NULL term, no CRLF}
  in out  conn: file_conn_t;           {handle to internet stream to write to}
  out     stat: sys_err_t);            {returned completion status code}
  val_param;

var
  vstr: string_var132_t;               {var string copy of input string}

begin
  vstr.max := sizeof(vstr.str);        {init local var string}

  string_vstring (vstr, str, 80);      {convert input string to var string}
  inet_vstr_crlf_put (vstr, conn, stat); {send the var string}
  end;
{
*********************************************************************
*
*   Subroutine INET_VSTR_CRLF_GET (VSTR, CONN, STAT)
*
*   Get the next CRLF-terminated string from an internet stream.  CONN
*   is the connection to the internet stream.  VSTR will be returned
*   without the CRLF.
}
procedure inet_vstr_crlf_get (         {receive CRLF terminated string}
  in out  vstr: univ string_var_arg_t; {returned string, CRLF removed}
  in out  conn: file_conn_t;           {handle to internet stream to read from}
  out     stat: sys_err_t);            {returned completion status code}
  val_param;

var
  olen: sys_int_adr_t;                 {amount of data actually read}
  c: char;                             {one character input buffer}
  cr: boolean;                         {TRUE if last character was CR}
  long_p: ^string_var8192_t;

label
  loop;

begin
  vstr.len := 0;                       {init returned string to empty}
  cr := false;                         {init to last character wasn't CR}

loop:                                  {back here each new character to read}
  file_read_inetstr (                  {read next char from internet stream}
    conn,                              {handle to internet stream connection}
    sizeof(c),                         {amount of data to read}
    [],                                {wait until all data is available}
    c,                                 {input buffer}
    olen,                              {amount of data actually read}
    stat);
  if sys_error(stat) then begin
    if debug_inet >= 5 then begin
      sys_error_print (stat, 'email', 'err_inet_byte_read', nil, 0);
      end;
    return;
    end;

  if cr then begin                     {previous character was carriage return ?}
    if c = lf_k then begin             {just hit end of terminating sequence ?}
      if debug_inet >= 5 then begin
        long_p := univ_ptr(addr(vstr));
        writeln ('< ', long_p^.str:long_p^.len);
        end;
      return;
      end;
    string_append1 (vstr, cr_k);       {CR was part of string data}
    end;

  if c = cr_k
    then begin                         {this char could be start of CRLF sequence ?}
      cr := true;
      end
    else begin                         {this is an ordinary character}
      cr := false;
      string_append1 (vstr, c);
      end
    ;
  goto loop;
  end;
