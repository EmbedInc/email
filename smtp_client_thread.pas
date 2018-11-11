{   Subroutine SMTP_CLIENT_THREAD (CL)
*
*   Handle all the interaction with one SMTP client.  This subroutine is
*   intended to be run in a separate thread.  The client descriptor will be
*   closed and deallocated.
}
module smtp_client_thread;
define smtp_client_thread;
%include 'email2.ins.pas';

procedure smtp_client_thread (         {thread routine for one SMTP client}
  in out  cl: smtp_client_t);          {client descriptor, passed by reference}

const
  max_msg_parms = 1;                   {max parameters we can pass to a message}

var
  outq: string_leafname_t;             {specific output queue name}
  qdir: string_treename_t;             {true name of Cognivision SMTPQ directory}
  temp_p: smtp_client_p_t;             {temp pointer for deallocating CL}
  turn: boolean;                       {TRUE if reversing send/recv roles}
  received: boolean;                   {at least one message was received and queued}
  msg_parm:                            {parameter references for messages}
    array[1..max_msg_parms] of sys_parm_msg_t;
  stat: sys_err_t;                     {completion status code}

begin
  qdir.max := sizeof(qdir.str);
  outq.max := sizeof(outq.str);
{
*   Process requests from the client.
}
  turn := false;                       {dis-allow role reversal}
  received := smtp_recv (cl, turn, stat); {receive mail from this client}
  if sys_error(stat) then begin
    smtp_client_log_stat_str (cl, stat, 'Error receiving mail from client.');
    end;
{
*   Done with this client.  Deallocate all state associated with this client
*   and return.  Returning will terminate the thread if this routine was run
*   in a separate thread.
}
  temp_p := addr(cl);                  {make local pointer to client descriptor}

  if received
    then begin                         {at least one mail message was received}
      sys_cognivis_dir ('smtpq'(0), qdir); {get full name of mail queues directory}
      string_copy (cl.inq, outq);      {save name of queue we dumped incoming mail into}
      smtp_client_close (temp_p);      {close client connection, dealloc resources}
      smtp_autosend (                  {process queue entries, if enabled}
        qdir,                          {name of top level queue directory}
        outq,                          {name of queue to deliver mail from}
        true,                          {wait for subordinate processes to complete}
        stat);
      if sys_error(stat) then begin
        sys_msg_parm_vstr (msg_parm[1], outq);
        smtp_client_wrlock;
        sys_error_print (stat, 'email', 'smtp_autosend', msg_parm, 1);
        smtp_client_wrunlock;
        end;
      end
    else begin                         {no message was received}
      smtp_client_close (temp_p);      {close client connection, dealloc resources}
      end
    ;
  end;
