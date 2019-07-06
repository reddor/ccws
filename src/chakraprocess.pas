unit chakraprocess;

{$i ccwssettings.inc}

interface

uses
  Classes,
  SysUtils,
  Linux,
  ChakraCommon,
  ChakraCore,
  ChakraCoreClasses,
  ChakraCoreUtils,
  ChakraRTTIObject,
  ChakraEventObject,
  chakrainstance,
  webserverhosts,
  epollsockets,
  Process;

type
  TChakraProcess = class;

  { TChakraProcessEvent }

  TChakraProcessEvent = class(TChakraEvent)
  private
    FData: string;
    FExitCode: Integer;
  published
    property data: string read FData write FData;
    property exitCode: Integer read FExitCode write FExitCode;
  end;

  { TChakraProcessDataHandler }

  TChakraProcessDataHandler = class(TCustomEpollHandler)
  private
    FTarget: TChakraProcess;
    FDataHandle: THandle;
  protected
    procedure DataReady(Event: epoll_event); override;
  public
    constructor Create(Target: TChakraProcess; Parent: TEpollWorkerThread);
    procedure SetDataHandle(Handle: THandle);
    destructor Destroy; override;
  end;

  { TChakraProcess }

  TChakraProcess = class(TNativeRTTIEventObject)
  private
    FHasTerminated: Boolean;
    FParentThread: TEpollWorkerThread;
    FParentSite: TWebserverSite;
    FProcess: TProcess;
    FDataHandler: TChakraProcessDataHandler;
    function GetExitCode: Integer;
    function GetTerminated: Boolean;
  protected
    //procedure ConstructObject(const ThisArgument:TBESENValue;Arguments:PPBESENValues;CountArguments:integer); override;
    //procedure FinalizeObject; override;
    procedure StopProcess;
  public
    constructor Create(Args: PJsValueRef = nil; ArgCount: Word = 0; AFinalize: Boolean = False); override;
    destructor Destroy; override;
  published
    function start(Arguments: PJsValueRefArray; CountArguments: word): JsValueRef;
    function stop(Arguments: PJsValueRefArray; CountArguments: word): JsValueRef;
    function setEnvironment(Arguments: PJsValueRefArray; CountArguments: word): JsValueRef;
    function write(Arguments: PJsValueRefArray; CountArguments: word): JsValueRef;
    function writeLine(Arguments: PJsValueRefArray; CountArguments: word): JsValueRef;
    function isTerminated(Arguments: PJsValueRefArray; CountArguments: word): JsValueRef;
    property exitCode: Integer read GetExitCode;
  end;

implementation

uses
  baseunix,
  unix,
  chakrawebsocket,
  logging;

{ TChakraProcessDataHandler }

procedure TChakraProcessDataHandler.DataReady(Event: epoll_event);
var
  buf: string;
  e: TChakraProcessEvent;
begin
  if (Event.Events and EPOLLIN<>0) then
  begin
    setlength(buf, FTarget.FProcess.Output.NumBytesAvailable);
    FTarget.FProcess.Output.Read(buf[1], Length(buf));
    e:=TChakraProcessEvent.Create('data');
    e.data:=buf;
    e.exitCode:=0;
    try
      FTarget.dispatchEvent(e);
    except
      dolog(llError, 'Exception in TChakraProcess.data event');
    end;
    e.Free;
  end else
  begin
    FTarget.StopProcess;
  end;
end;

constructor TChakraProcessDataHandler.Create(Target: TChakraProcess;
  Parent: TEpollWorkerThread);
begin
  inherited Create(Parent);
  FTarget:=Target;
  FDataHandle:=0;
end;

procedure TChakraProcessDataHandler.SetDataHandle(Handle: THandle);
begin
  if FDataHandle = 0 then
    FDataHandle:=Handle
  else
    Exit;
  fpfcntl(FDataHandle, F_SetFl, fpfcntl(FDataHandle, F_GetFl, 0) or O_NONBLOCK);
  AddHandle(FDataHandle);
end;

destructor TChakraProcessDataHandler.Destroy;
begin
  if FDataHandle <>0 then
    RemoveHandle(FDataHandle);
  inherited Destroy;
end;

{ TChakraProcess }

(*
procedure TChakraProcess.ConstructObject(const ThisArgument: TBESENValue;
  Arguments: PPBESENValues; CountArguments: integer);
var
  i: Integer;
  s: ansistring;
begin
  inherited ConstructObject(ThisArgument, Arguments, CountArguments);
  if CountArguments<1 then
    raise EBESENError.Create('Argument expected in constructor');

  FParentThread:=nil;
  FParentSite:=nil;

  FHasTerminated:=True;

  if Instance is TBESENInstance then
  begin
    if Assigned(TBESENInstance(Instance).Thread) and
       (TBESENInstance(Instance).Thread is TEpollWorkerThread) then
    begin
      FParentThread:=TEpollWorkerThread(TBESENInstance(Instance).Thread);
      if FParentThread is TBESENWebsocket then
        FParentSite:=TBESENWebsocket(FParentThread).Site;
    end;
  end;

  s:=ansistring(TBESEN(Instance).ToStr(Arguments^[0]^));

  if Assigned(FParentSite) then
  begin
    if(pos('/', s)<>1) then
      s:=FParentSite.Path+'bin/'+s;

    if not FParentSite.IsProcessWhitelisted(s) then
      raise EBESENError.Create('This executable may not be started from this realm');

  end;


  FProcess:=TProcess.Create(nil);
  FProcess.Executable:=s;
  FProcess.CurrentDirectory:=ExtractFilePath(s);
  for i:=1 to CountArguments-1 do
    FProcess.Parameters.Add(ansistring(TBESEN(Instance).ToStr(Arguments^[i]^)));
end;

procedure TBESENProcess.FinalizeObject;
begin
  FOnTerminate:=nil;
  StopProcess;
  inherited FinalizeObject;

  if Assigned(FProcess) then
    FreeAndNil(FProcess);
end;   *)

function TChakraProcess.GetTerminated: Boolean;
begin
  if Assigned(FProcess) then
    result:=not FProcess.Running
  else
    result:=True;
end;

function TChakraProcess.GetExitCode: Integer;
begin
  if Assigned(FProcess) then
    result:=FProcess.ExitCode
  else
    result:=-1;
end;

procedure TChakraProcess.StopProcess;
var
  e: TChakraProcessEvent;
begin
  if Assigned(FProcess) then
  begin
    if Assigned(FDataHandler) then
    begin
      FDataHandler.DelayedFree;
      FDataHandler:=nil;
    end;

    if FHasTerminated then
      Exit;

    dolog(llDebug, 'Terminating process '+string(FProcess.Executable));
    FProcess.Terminate(0);
    FHasTerminated:=True;

    e:=TChakraProcessEvent.Create('terminate');
    e.data:='';
    e.exitCode:=FProcess.ExitCode;
    dispatchEvent(e);
    e.Free;
  end;
end;

constructor TChakraProcess.Create(Args: PJsValueRef; ArgCount: Word;
  AFinalize: Boolean);
var
  i: Integer;
  s: ansistring;
  ci: TChakraInstance;
begin
  inherited Create(Args, ArgCount, AFinalize);
  if ArgCount<1 then
    raise Exception.Create('Argument expected in constructor');

  FParentThread:=nil;
  FParentSite:=nil;

  FHasTerminated:=True;

  if Context.Runtime is TChakraInstance then
  begin
    ci:=TChakraInstance(Context.Runtime);
    if Assigned(ci.Thread) and
       (ci.Thread is TEpollWorkerThread) then
    begin
      FParentThread:=TEpollWorkerThread(ci.Thread);
      if FParentThread is TChakraWebsocket then
        FParentSite:=TChakraWebsocket(FParentThread).Site;
    end;
  end;

  s:=JsStringToUTF8String(JsValueAsJsString(Args[0]));

  if Assigned(FParentSite) then
  begin
    if(pos('/', s)<>1) then
      s:=FParentSite.Path+'bin/'+s;

    if not FParentSite.IsProcessWhitelisted(s) then
      raise Exception.Create('Target executable is not whitelisted');

  end;

  FProcess:=TProcess.Create(nil);
  FProcess.Executable:=s;
  FProcess.Options:=[poStderrToOutPut];
  FProcess.CurrentDirectory:=ExtractFilePath(s);
  for i:=1 to ArgCount-1 do
    FProcess.Parameters.Add(JsStringToUTF8String(JsValueAsJsString(Args[i])));
end;

destructor TChakraProcess.Destroy;
begin
  inherited Destroy;
  if Assigned(FProcess) then
    FreeAndNil(FProcess);
end;

function TChakraProcess.start(Arguments: PJsValueRefArray; CountArguments: word
  ): JsValueRef;
begin
  result:=JsUndefinedValue;
  if Assigned(FProcess) then
  begin
    if FProcess.Running then
      Exit;

    dolog(llDebug, 'Starting process '+FProcess.Executable);
    if Assigned(FParentThread) then
    begin
      FDataHandler:=TChakraProcessDataHandler.Create(Self, FParentThread);
      FProcess.Options:=[poUsePipes, poStderrToOutPut];
    end;

    FProcess.Execute;
    FHasTerminated:=False;

    if Assigned(FDataHandler) then
    begin
      FDataHandler.SetDataHandle(FProcess.Output.Handle);
    end;
  end;
end;

function TChakraProcess.stop(Arguments: PJsValueRefArray; CountArguments: word
  ): JsValueRef;
begin
  result:=JsUndefinedValue;
  StopProcess;
end;

function TChakraProcess.setEnvironment(Arguments: PJsValueRefArray;
  CountArguments: word): JsValueRef;
var
  i: Integer;
begin
  result:=JsUndefinedValue;
  if Assigned(FProcess) then
    for i:=0 to CountArguments-1 do
      FProcess.Environment.Add(JsStringToUTF8String(JsValueAsJsString(Arguments^[i])));
end;

function TChakraProcess.write(Arguments: PJsValueRefArray; CountArguments: word
  ): JsValueRef;
var
  i: Integer;
  s: ansistring;
begin
  result:=JsUndefinedValue;
  if (not Assigned(FProcess)) or (not Assigned(FDataHandler)) or (CountArguments=0) then
    Exit;

  s:='';
  for i:=0 to CountArguments-1 do
  begin
    if i>0 then s:=s+' ';
    s:=s + JsStringToUTF8String(JsValueAsJsString(Arguments^[i]));
  end;
  if s<>'' then
    FProcess.Input.WriteBuffer(s[1], Length(s));
end;

function TChakraProcess.writeLine(Arguments: PJsValueRefArray;
  CountArguments: word): JsValueRef;
var
  i: Integer;
  s: ansistring;
begin
  result:=JsUndefinedValue;
  if (not Assigned(FProcess)) or (not Assigned(FDataHandler)) or (CountArguments=0) then
    Exit;

  s:='';
  for i:=0 to CountArguments-1 do
  begin
    if i>0 then s:=s+' ';
    s:=s + JsStringToUTF8String(JsValueAsJsString(Arguments^[i]));
  end;
  s:=s + #10;
  FProcess.Input.WriteBuffer(s[1], Length(s));
end;

function TChakraProcess.isTerminated(Arguments: PJsValueRefArray;
  CountArguments: word): JsValueRef;
begin
  Result:=BooleanToJsBoolean(GetTerminated);
end;

end.

