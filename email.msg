/*   Error messages related to status codes.
/*
msg err1
  lan english -def
    End of SMTP queue encountered.
msg err2
  lan english -def
    An SMTP queue entry was already open on an attempt to open another one.
msg err3
  lan english -def
    No SMTP queue entry was open on attempt to close current entry.
msg err4
  lan english -def
    Error on trying to read command from SMTP queue options file %p1s
    on line %p2i.
msg err5
  lan english -def
    Unrecognized command "%p1s" encountered in SMTP queue options file
    %p2s on line %p3i.
msg err6
  lan english -def
    Error with parameter to command "%p1s" in SMTP queue options file
    %p2s on line %p3i.
msg err7
  lan english -def
    Too many parameters to command "%p1s" in SMTP queue options file
    %p2s on line %p3i.
msg err8
  lan english -def
    Missing parameter to command "%p1s" in SMTP queue options file
    %p2s on line %p3i.
msg err9
  lan english -def
    SMTP protocol or handshake error.
msg err10
  lan english -def
    Mail queue "%p1s" does not exist.
msg err11
  lan english -def
    Mail queue "%p1s" is full, or unrecognized errors encountered in trying
    to create files in the queue.
msg err12
  lan english -def
    No mail queue specified for incoming mail.
msg err13
  lan english -def
    The information is not stable after %p1i passes thru the "%p2s"
    environment file set.  This probably means there is a circular dependency.
msg err14
  lan english -def
    Bad command "%p1s" encountered on line %p2i in environment file "%p3s".
msg err15
  lan english -def
    Extraneous stuff found after command on line %p1i of environment file
    "%p2s".  The first unexpected token was "%p3s".
msg err16
  lan english -def
    Missing parameter to command %p1s on line %p2i of environment file "%p3s".
msg err17
  lan english -def
    Error in processing parameter "%p1s" to command in environment file
    "%p2s" on line %p3i.
msg err18
  lan english -def
    Error %p1s indicated by remote SMTP server, "%p2s".
msg err19
  lan english -def
    Unexpected end of line encountered on line %p1i of Intel HEX file %p2s.
msg err20
  lan english -def
    Checksum error on line %p1i of Intel HEX file %p2s.
msg err21
  lan english -def
    Illegal character found on line %p1i of Intel HEX file %p2s:
    .nfill
    %p3s                               /* source line
    %p4s                               /* up arrow pointing to start of error
msg err22
  lan english -def
    Unrecognized Intel HEX file record type of %p1i encountered on line %p2i
    of file %p3s.
msg err23
  lan english -def
    Unexpected data encountered in a WAV file.  File "%p1s" is not a valid
    WAV file.
msg err24
  lan english -def
    The type of data encoding in WAV file "%p2s" is not supported by this
    program.  Encoding ID = %p1i.
msg err25
  lan english -def
    The requested WAV file encoding method is not supported.  The encoding
    ID was %p1i.
msg err26
  lan english -def
    The SMTP client on %p1s claiming to be "%p2s" attempted to relay mail
    thru this server to "%p3s".
msg err27
  lan english -def
    More organizations with private part numbers enountered than can be
    handled by "%p1s".  Limit is %p2i.
msg err28
  lan english -def
    No end of file record found in HEX file.  Not a valid HEX file.
msg err28
  lan english -def
    CSV file field is empty.  Error occurred on line %p2s, field %p3s, of
    file %p1s.
/*
/*   Generic non-error message.
/*
msg retry_limit
  lan english -def
    Retry limit reached.  Giving up.
/*
/*   Generic error messages.
/*
msg err_array_overflow
  lan english -def
    Internal array size exceeded.
msg err_checksum
  lan english -def
    Bad checksum.  The data may be corrupt.
msg err_checksum_vals
  lan enslish -def
    Bad checksum.  %p1i expected, %p2i found.
msg err_cmd_bad
  lan english -def
    Unrecognized command "%p1s" on line %p2i of file %p3s.
msg err_eol
  lan english -def
    Unexpected end of line.
msg err_eol_not
  lan english -def
    More data found where end of line was expected.
msg err_no_command
  lan english -def
    No command specified.
msg err_no_indata
  lan english -def
    No input data found.
msg err_no_macadr_seq
  lan english -def
    No MAC address sequence number file found.  This machine has not been
    set up for generating unique MAC addresses.
msg err_nresp_remote
  lan english -def
    The remote unit failed to respond.
msg err_on_line
  lan english -def
    Error occurred on line %p1i of file %p2s.
msg err_parm_bad
  lan english -def
    Bad parameter "%p1s" encountered for command "%p2s".
msg err_parm_get
  lan english -def
    Error on fetching parameter for command "%p1s".
msg err_syntax_input
  lan english -def
    Syntax error in input file.
msg err_tokens_too_many
  lan english -def
    Too many tokens found on line %p1i of file %p2s.  First unexpected token
    was "%p3s".
msg wait_enter
  lan english -def
    Press ENTER to close the window:
/*
/*   Messages related to reading and writing internet streams.
/*
msg err_inet_byte_read
  lan english -def
    Error occurred on attempt to read byte from internet stream.
/*
/*   Messages related to dialup connections to remote systems.
/*
msg dialup_close_error
  lan english -def
    %p1s Error on attempt to close connection to %p2s.
msg dialup_closed
  lan english -def
    %p1s Closed connection to %p2s.
msg dialup_connected
  lan english -def
    %p1s Established new connection to %p2s.
msg dialup_error
  lan english -def
    %p1s Error on attempt to dial %p2s.
msg dialup_list
  lan english -def
    Error on attempt to list existing remote dialup connections.
msg dialup_reused
  lan english -def
    %p1s Already connected to %p2s.
/*
/*   Messages related to email issues.
/*
msg email_adr_none
  lan english -def
    No email target address.
msg email_adrfile_read
  lan english -def
    Error on read line from email addresses list file "%p1s".
msg email_adrtyp_bad
  lan english -def
    Unrecognized email address string format type ID %p1i.
msg email_client_lock
  lan english -def
    Error occurred on attempt to create private thread interlock in the
    CLIENT module.
msg email_end_else
  lan english -def
    Unexpected ELSE statement encountered.
msg email_end_endif
  lan english -def
    Unexpected ENDIF statement encountered.
msg email_env_open
  lan english -def
    Error occurred on attempt to open environment file set for email
    address translation.
msg email_exp_close
  lan english -def
    Unmatched close parenthesis encountered in expression "%p1s" while
    translating email address.
msg email_exp_eos
  lan english -def
    Unexpected end of expression string "%p1s" encountered while
    translating email address.
msg email_exp_noclose
  lan english -def
    Missing close parenthesis encountered in expression "%p1s" while
    translating email address.
msg email_exp_op
  lan english -def
    Unrecognized operator "%p1s" encountered while translating email address.
msg email_exp_err_token
  lan english -def
    Unexpected keyword "%p1s" encountered in expression while translating
    email address.
msg email_if_else
  lan english -def
    Synatax error in MAIL.ADR environment file set.  Redundant ELSE
    statement encountered within ELSE clause.  If statement started on line
    %p1i of file %p2s.
msg email_if_eof
  lan english -def
    End of environment file set encountered before end of IF statement.
    If statement started on line %p1i of file %p2s.
msg email_msg_in_none
  lan english -def
    No input email message given.
msg email_msg_in_open
  lan english -def
    Error on attempt to open input email message file "%p1s".
msg email_msg_in_read
  lan english -def
    Error on attempt to read from input email message file "%p1s".
msg email_no_alias_out
  lan english -def
    No alias found for this name.  Addresses of the form "<name>.out"
    must have an alias for <name> declared in the mail.adr environment
    file set.
msg email_queue_entry_read_close
  lan english -def
    Error occurred on attempt to close read of mail queue entry.
    Mail message file name was "%p1s".
msg email_queue_entry_create
  lan english -def
    Error occurred on attempt to create entry in email queue "%p1s".
msg email_queue_entry_read_next
  lan english -def
    Error on attempt to open next mail queue entry for read.
msg email_queue_in_none
  lan english -def
    No mail queue specified for incoming mail.
msg email_queue_read_close
  lan english -def
    Error on attempt to close email queue open for read.
    Queue name was "%p1s".
msg email_queue_write_close
  lan english -def
    Error on attempt to close email queue entry after creation.
msg email_rqmeth_unimp
  lan english -def
    Unknown or unimplemented remote system mail request method encountered
    in routine %p1s.  Request method ID was %p2i.
msg email_sendmail_err
  lan english -def
    SENDMAIL program was unsuccessful in sending mail message "%p1s".
msg email_tktyp_bad
  lan english -def
    Unrecognized email address token type ID %p1i.
msg email_token_type_bad
  lan english -def
    Unrecognized incremental email address token type.  Token was "%p1s"
    of type ID %p2i.
msg email_translate_loop
  lan english -def
    Maximum allowed number of passes thru the MAIL.ADR environemt file
    set reached on attempt to translate email address.  This is probably
    due to a circular reference.
msg email_write_queue_a
  lan english -def
    Error on trying to write to email queue entry addresses list file "p1s".
msg email_write_queue_m
  lan english -def
    Error on trying to write to email queue entry mail message file "p1s".
msg pop3_server_port_normal
  lan english -def
    POP3 server established on port %p1i.
msg pop3_server_port_nstd
  lan english -def
    Unable to establish POP3 server at standard server port.  Established
    at port %p1i instead.
msg smtp_autosend
  lan english -def
    Error occurred on trying to process all entries in SMTP queue "%p1s",
    due to AUTOSAVE enabled.
msg smtp_client_getadr
  lan english -def
    Unable to get remote SMTP client address and port, closing connection.
msg smtp_client_thread_release
  lan english -def
    Error on attempt to release SMTP client thread.
msg smtp_get_remote_adr
  lan english -def
    Error trying to get address of node "%p1s".
msg smtp_queue_create_a
  lan english -def
    Error on trying to create mail queue addresses file "%p1s".
msg smtp_queue_create_m
  lan english -def
    Error on trying to create mail queue message file "%p1s".
msg smtp_queue_read_close
  lan english -def
    Error trying to close mail queue "%p1s" open for reading.
msg smtp_queue_read_open
  lan english -def
    Error trying to open mail queue "%p1s" for reading.
msg smtp_receive
  lan english -def
    Error on trying to receive email from SMTP client on machine "%p1s".
msg smtp_send_queue
  lan english -def
    Error occurred on trying to send contents of mail queue "%p1s".
msg smtp_server_port_normal
  lan english -def
    SMTP server established on port %p1i.
msg smtp_server_port_nstd
  lan english -def
    Unable to establish SMTP server at standard server port.  Established
    at port %p1i instead.
/*
/*   Message related to reading email message headers.
/*
msg ehead_close_err
  lan english -def
    Error encountered on attempt to end reading email message header.
msg ehead_read_err
  lan english -def
    Error encountered on attempt to read command from email message header.
msg ehead_open_err
  lan english -def
    Error encountered on attempt to start reading email message header.
/*
/*   Messages related to quoted printable data.
/*
msg qprint_read_char
  lan english -def
    Error occurred on attempt to read a decoded character from a quoted
    printable data stream.
msg qprint_read_char_str
  lan english -def
    Error occurred on attempt to decode a character from a quoted printable
    string.
msg qprint_read_close
  lan english -def
    Error occurred on attempt to end decoding a quoted printable data stream
    and deallocate resources.
msg qprint_read_open_conn
  lan english -def
    Error occurred on attempt to set up for interpreting an existing text
    data stream as quoted printable.
