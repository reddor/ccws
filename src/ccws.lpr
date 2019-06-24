program ccws;

uses
    {$IFDEF UNIX}
    cthreads,
    cwstring,
    {$ENDIF}
    console in 'chakracore/samples/HostSample/Console.pas',
    Classes,
    SysUtils,
    webserver,
    unix,
    baseunix,
    linux,
    logging,
    webserverhosts,
    chakraserverconfig,
    chakraevents,
    chakrainstance,
    epollsockets,
    buildinfo,
    {$IFDEF CGISUPPORT}
    externalproc,
    fcgibridge,
    {$ENDIF}
    sslclass;

  {.$R *.res}

  var
    isdebug: Boolean;
    shutdown: Boolean;
    testmode: Boolean;
    hasforked: Boolean;
    locallibssl: Boolean;
    oa,na : PSigActionRec;
    ConfigurationPath: ansistring;

  procedure ForkToBackground;
  begin
    if hasforked then
      Exit;

    hasforked:=True;

    Writeln('Forking to background...');

    Close(input);
    Close(output);

    Assign(output,ChangeFileExt(ParamStr(0), '.std'));
    ReWrite(output);
    stdout:=output;
    Close(stderr);
    Assign(stderr,ChangeFileExt(ParamStr(0), '.err'));
    ReWrite(stderr);

    LogToFile(ChangeFileExt(ParamStr(0), '.log'));

    if FpFork()<>0 then
      Halt;

  end;

  procedure WritePid(p: TPid);
  var t: Textfile;
  begin
    Assignfile(t, ChangeFileExt(ParamStr(0), '.pid'));
    {$i-}rewrite(t);{$i+}
    if ioresult=0 then
    begin
      Writeln(t, p);
      Closefile(t);
    end;
  end;

  procedure DoSig(sig: longint); cdecl;
  begin
    case sig of
      SIGHUP:
      begin
        dolog(llNotice, 'SIGHUP received');
        // Dispatch SIGHUP
      end;
      SIGINT:
      begin
        dolog(llNotice, 'SIGINT received');
        if shutdown then
        begin
          dolog(llError, 'Forcing shutdown...');
          Halt(1);
        end;
        shutdown:=True;
      end;
      SIGTERM:
      begin
        dolog(llNotice, 'SIGTERM received');
        if shutdown then
        begin
          dolog(llError, 'Forcing shutdown...');
          Halt(1);
        end;
        shutdown := True;
      end;
      SIGPIPE:
      begin
        dolog(llNotice, 'SIGPIPE received');
      end;
      SIGQUIT:
      begin
        dolog(llNotice, 'SIGQUIT received');
      end;
    end;
  end;

  procedure ShowHelp;
  begin
    Writeln('Usage:');
    Writeln;
    Writeln('  '+ExtractFileName(Paramstr(0))+' -debug <config path>');
    Writeln;
    Writeln('  -debug        - debugmode, don''t fork the process to background');
    Writeln('  <config path> - alternative configuration path');
  end;

  procedure CheckParameters;
  var
    i: Integer;
    s: ansistring;
    GotPath: Boolean;
  begin
    GotPath:=False;
    testmode:=False;
    locallibssl:=False;

    if ParamCount = 0 then
    begin
      Exit;
    end;

    for i:=1 to ParamCount do
    begin
      s:=Paramstr(i);
      if pos('-', s)=1 then
      begin
        if s = '-debug' then
          isdebug:=true
        else
        if s = '-locallibssl' then
          locallibssl:=true
        else
        if s = '-test' then
        begin
          testmode:=true;
        end else
        begin
          Writeln('Invalid parameter '+s);
          Writeln;
          ShowHelp;
          Halt(1);
        end;
      end else
      begin
        if not GotPath then
        begin
          GotPath:=True;
          ConfigurationPath:=s
        end else
        begin
          Writeln('Invalid parameter: '+s);
          Writeln;
          ShowHelp;
          Halt(1);
        end;
      end;
    end;

    if ConfigurationPath[Length(ConfigurationPath)]<>'/' then
      ConfigurationPath:=ConfigurationPath + '/';

    if not DirectoryExists(ConfigurationPath) then
    begin
      Writeln('Invalid directory '+ConfigurationPath);
      Halt(1);
    end;
  end;

  procedure IncreaseRLimits;
  var
    Limit: TRLimit;
    i, OldLimit: Integer;
  begin
    i:=FpGetRLimit(RLIMIT_NOFILE, @Limit);
    if i=0 then
    begin
      OldLimit:=Limit.rlim_cur;
      if Limit.rlim_max > Limit.rlim_cur then
      begin
        Limit.rlim_cur:=Limit.rlim_max;
        i:=FpSetRLimit(RLIMIT_NOFILE, @Limit);
        if i=0 then
          dolog(llNotice, 'Increased RLIMIT_NOFILE from '+IntToStr(OldLimit)+' to '+IntToStr(Limit.rlim_max));
      end;
    end;
    if i<>0 then
      dolog(llWarning, 'Could not get/set RLIMIT_NOFILE');
  end;

  begin
    isdebug:=False;
    ConfigurationPath:=ExtractFilePath(ParamStr(0));
    CheckParameters;

    {$IFDEF OPENSSL_SUPPORT}
    InitializeOpenSSL(locallibssl);
    {$ENDIF}


    if not FileExists(ConfigurationPath + 'settings.js') then
    begin
      Writeln(ConfigurationPath+'settings.js could not be found!');
      Halt(1);
    end;

    try
      new(na);
      new(oa);
      na^.sa_Handler:=SigActionHandler(@DoSig);
      fillchar(na^.Sa_Mask,sizeof(na^.sa_mask),#0);
      na^.Sa_Flags:=0;
      {$ifdef Linux}
      na^.Sa_Restorer:=Nil;
      {$endif}

      if fpSigAction(SIGINT,na,oa)<>0 then
        dolog(llError, 'Could not set up signalhandler!');
      if fpSigAction(SIGTERM,na,oa)<>0 then
        dolog(llError, 'Could not set up signalhandler!');
      if fpSigAction(SIGQUIT,na,oa)<>0 then
        dolog(llError, 'Could not set up signalhandler!');
      if fpSigAction(SIGPIPE,na,oa)<>0 then
        dolog(llError, 'Could not set up signalhandler!');

      if testmode then
      begin
        if not isdebug then
          GlobalLogLevel:=llError;
        isdebug:=True;
      end;

      dolog(llNotice, FullServerName);
      if not isdebug then
      begin
        ForkToBackground;
      end else
        dolog(llNotice, 'Running in Debug Mode');

      IncreaseRLimits;
      {$IFDEF OPENSSL_SUPPORT}
      if IsSSLloaded then
        dolog(llNotice, 'Using '+SSLeayversion(0))
      else
        dolog(llWarning, 'Could not load OpenSSL');
      {$ENDIF}

      WritePid(fpGetPid);

      shutdown:=False;

      ServerManager:=TWebserverManager.Create(ConfigurationPath, testmode);
      if not ServerManager.Execute(ConfigurationPath+'settings.js') then
      begin
        dolog(llError, 'Startup failed!');
        Halt(1);
      end;
      dolog(llNotice, 'Loading complete');

      if testmode then
      begin
        ServerManager.Process;
        Sleep(20);
        ServerManager.Process;
        Sleep(20);
        ServerManager.Process;
        Sleep(20);
        ServerManager.Process;
      end else
      while not shutdown do
      begin
        Sleep(20);
        ServerManager.Process;
      end;

      dolog(llNotice, 'Shutting down');
      ServerManager.Destroy;

      FreeMem(na);
      Freemem(oa);


    except
      on e: Exception do
        dolog(llError, 'A serious program error has occured: '+ e.Message);
    end;

    dolog(llNotice, 'Good bye');
  end.


