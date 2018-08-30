{   Program TEST_EMAIL [<email address>]
*
*   Test email address manipulation.  If an email address is given on the
*   command line, that address will be read in and translated thru the
*   MAIL.ADR environment file set.  The result will be printed and the
*   program will exit.  This mode is intended for checking email addresses.
*
*   If nothing is given on the command line, the program will enter an
*   interactive mode.  A current email address is maintained and acted
*   on by commands.  The address is initialized to empty, and written out
*   in different formats after each command that modifies it.  Commands are:
*
*   DEL [<token type>]
*
*     Delete the specified address token if <token type> is given.  Otherwise
*     delete the entire address.  Token type names are:
*
*     DOM_FIRST  -  First domain name
*     DOM_LAST  -  Last domain name
*     SYS_FIRST  -  First system name
*     SYS_LAST  -  Last system name
*     USER  -  User name
*
*   ADD <address string>
*
*     Add the incremental address to the current address.
*
*   NEW <address string>
*
*     Replace the current address with the address indicated by <address string>.
*
*   XL
*
*     Translate the address thru the MAIL.ADR environment file set.
*
*   Q
*
*     Quit the program.
}
program test_email;
%include 'base.ins.pas';
%include 'email.ins.pas';

var
  adr: email_adr_t;                    {descriptor for current email address}
  pick: sys_int_machine_t;             {number of token picked from list}
  p: string_index_t;                   {input line parse index}
  tktyp: email_tktyp_k_t;              {indicates an address token type}
  quit: boolean;                       {TRUE if supposed to quit program after cmd}
  ibuf,                                {one line input buffer}
  obuf,                                {one line output buffer}
  parm:                                {command parameter}
    %include '/cognivision_links/dsee_libs/string/string132.ins.pas';
  cmd:                                 {current command name}
    %include '/cognivision_links/dsee_libs/string/string32.ins.pas';
  stat: sys_err_t;                     {completion status code}

  prompt: string_var4_t :=             {command prompt}
    [str := ': ', len := 2, max := 4];

label
  cmd_loop, error;
{
**************************************************************
*
*   Local subroutine PRINT_INFO
*
*   Print info about the current email address.
}
procedure print_info;

begin
  writeln ('Info: "', adr.info.str:adr.info.len, '"');
  email_adr_t_string (adr, email_adrtyp_at_k, obuf);
  writeln (obuf.str:obuf.len);
  email_adr_t_string (adr, email_adrtyp_bang_k, obuf);
  writeln (obuf.str:obuf.len);
  end;
{
**************************************************************
*
*   Start of main program.
}
begin
  email_adr_create (adr, util_top_mem_context); {create and init curr email adr}

  string_cmline_init;                  {init for command line processing}
  string_cmline_token (parm, stat);    {get email address from cmdline if present}
  if not string_eos(stat) then begin   {found something on command line ?}
    sys_error_abort (stat, '', '', nil, 0); {hard error on reading command line ?}
    string_cmline_end_abort;           {no more tokens allowed on command line}
    email_adr_string_add (adr, parm);  {make address from command line argument}
    email_adr_translate (adr);         {translate thru environment files}
    print_info;                        {show user the result}
    return;                            {all done}
    end;

  quit := false;                       {init to not quit after next command}

cmd_loop:                              {back here each new command}
  string_prompt (prompt);              {write prompt to user}
  string_readin (ibuf);                {get next command line from user}
  p := 1;                              {init parse index}
  string_token (ibuf, p, cmd, stat);   {extract command name}
  if string_eos(stat) then goto cmd_loop; {ignore empty command lines}
  string_upcase (cmd);                 {make upper case for keyword matching}
  string_tkpick80 (cmd,
    'DEL ADD XL Q NEW',
    pick);
  case pick of
{
*   DEL [<token type>]
}
1: begin
  string_token (ibuf, p, parm, stat);  {get token type if present}
  if string_eos(stat)
    then begin                         {no token type present}
      email_adr_delete (adr);          {delete old address}
      email_adr_create (adr, util_top_mem_context); {create new empty address}
      end
    else begin                         {token type is in PARM}
      string_upcase (parm);            {make upper case for keyword matching}
      string_tkpick80 (parm,
        'DOM_FIRST DOM_LAST SYS_FIRST SYS_LAST USER',
        pick);
      case pick of
1:      tktyp := email_tktyp_dom_first_k;
2:      tktyp := email_tktyp_dom_last_k;
3:      tktyp := email_tktyp_sys_first_k;
4:      tktyp := email_tktyp_sys_last_k;
5:      tktyp := email_tktyp_user_k;
otherwise
        goto error;
        end;                           {end of token type cases}
      email_adr_tkdel (adr, tktyp);    {delete the specified address token}
      end
    ;
  end;
{
*   ADD <address string>
}
2: begin
  if p > ibuf.len then goto error;     {command parameter missing ?}
  string_substr (ibuf, p, ibuf.len, parm); {read rest of command line}
  p := ibuf.len + 1;                   {indicate nothing left on command line}
  email_adr_string_add (adr, parm);    {add string to current email address}
  end;
{
*   XL
}
3: begin
  email_adr_translate (adr);
  end;
{
*   Q
}
4: begin
  quit := true;
  end;
{
*   NEW <address string>
}
5: begin
  string_token (ibuf, p, parm, stat);  {get address string}
  if sys_error(stat) then goto error;
  email_adr_delete (adr);
  email_adr_create (adr, util_top_mem_context);
  email_adr_string_add (adr, parm);    {string becomes new current email address}
  end;
{
*   Unrecognized command.
}
otherwise
  goto error;
  end;
{
*   Done processing current command.
}
  string_token (ibuf, p, parm, stat);  {check for unused tokens after command}
  if not sys_error(stat) then begin    {found an unused token ?}
error:
    writeln ('*** ERROR ***');
    quit := false;
    end;

  if quit then return;                 {asked to exit program ?}
  print_info;                          {show current address state}
  goto cmd_loop;                       {back to process next command}
  end.
