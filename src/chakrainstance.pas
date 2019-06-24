unit chakrainstance;

{$mode objfpc}{$H+}

interface

uses
  Classes,
  SysUtils,
  {$IFDEF MSWINDOWS}
  Windows,
  expipe,
  {$ELSE}
  BaseUnix,
  Unix,
  {$ENDIF}
  ChakraCommon,
  ChakraCoreClasses,
  ChakraCoreUtils,
  ChakraRTTIObject,
  Compat,
  Console,
  webserverhosts;

type
  TCallbackProc = procedure of object;

  { TChakraSystemObject }

  TChakraSystemObject = class(TNativeRTTIObject)
  private
    FSite: TWebserverSite;
  published
    function log(Arguments: PJsValueRefArray; CountArguments: word): JsValueRef;
    function setTimeout(Arguments: PJsValueRefArray; CountArguments: word): JsValueRef;
    function readFile(Arguments: PJsValueRefArray; CountArguments: word): JsValueRef;
    function writeFile(Arguments: PJsValueRefArray; CountArguments: word): JsValueRef;
    function load(Arguments: PJsValueRefArray; CountArguments: word): JsValueRef;
    function save(Arguments: PJsValueRefArray; CountArguments: word): JsValueRef;
    function eval(Arguments: PJsValueRefArray; CountArguments: word): JsValueRef;
  end;

  { TChakraInstance }

  TChakraInstance = class(TChakraCoreRuntime)
  private
    FManager: TWebserverSiteManager;
    FSite: TWebserverSite;
    FAlias, FBasePath: UnicodeString;
    FContext: TChakraCoreContext;
    FConsole: TConsole;
    FSystemObject: TChakraSystemObject;
    FThread: TThread;
    FReadPipe, FWritePipe: THandle;
    FProc: TCallbackProc;
    FHandlers: array of TCallbackProc;
    FTicks: LongWord;
    {$IFDEF MSWINDOWS}
    FReading: boolean;
    FNumRead: longword;
    FOverlapped: OVERLAPPED;
    {$ENDIF}
    procedure ContextLoadModule(Sender: TObject; Module: TChakraModule);
    procedure ContextNativeObjectCreated(Sender: TObject;
    {%H-}NativeObject: TNativeObject);
    procedure ConsolePrint(Sender: TObject; const Text: UnicodeString;
      Level: TInfoLevel = ilNone);
  public
    constructor Create(Manager: TWebserverSiteManager; Site: TWebserverSite; Thread: TThread= nil);
      reintroduce;
    destructor Destroy; override;
    procedure ExecuteFile(const ScriptFileNames: array of UnicodeString); overload;
    procedure ExecuteFile(ScriptFilename: UnicodeString); overload;
    procedure ProcessHandlers;
    procedure AddEventHandler(Handler: TCallbackProc);
    procedure RemoveEventHandler(Handler: TCallbackProc);
    procedure OutputException(e: Exception; Section: ansistring = '');
    procedure ReadCallback(ATimeout: longword);
    procedure Callback(Proc: TCallbackProc);
    property Context: TChakraCoreContext read FContext;
  end;

function LoadFile(const FileName: UnicodeString): UnicodeString;
function ExecuteCallback(Obj: TNativeObject; FuncName: UnicodeString; Args: PJsValueRef; ArgCount: Word): JsValueRef; overload;
function ExecuteCallback(Obj: TNativeObject; FuncName: UnicodeString; const Args: array of JsValueRef): JsValueRef; overload;

implementation

uses
  logging,
  xmlhttprequest;

function LoadFile(const FileName: UnicodeString): UnicodeString;
var
  FileStream: TFileStream;
  S: UTF8String;
begin
  Result := '';

  FileStream := TFileStream.Create(UnicodeString(FileName), fmOpenRead);
  try
    if FileStream.Size = 0 then
      Exit;

    SetLength(S, FileStream.Size);
    FileStream.Read(S[1], FileStream.Size);

    Result := UTF8ToString(S);
  finally
    FileStream.Free;
  end;
end;

function ExecuteCallback(Obj: TNativeObject; FuncName: UnicodeString; Args: PJsValueRef; ArgCount: Word): JsValueRef;
begin
  Result:=JsGetProperty(Obj.Instance, FuncName);
  if Assigned(Result) and (JsGetValueType(Result) = JsFunction) then
    Result := JsCallFunction(Result, Args, ArgCount)
  else
    Result := JsUndefinedValue;
end;

function ExecuteCallback(Obj, ThisObj: TNativeObject; FuncName: UnicodeString;
  const Args: array of JsValueRef): JsValueRef;
begin
  Result:=JsGetProperty(Obj.Instance, FuncName);
  if Assigned(Result) and (JsGetValueType(Result) = JsFunction) then
    Result := JsCallFunction(Result, Args, ThisObj.Instance)
  else
    Result := JsUndefinedValue;
end;

function ExecuteCallback(Obj: TNativeObject; FuncName: UnicodeString;
  const Args: array of JsValueRef): JsValueRef;
begin
  Result:=JsGetProperty(Obj.Instance, FuncName);
  if Assigned(Result) and (JsGetValueType(Result) = JsFunction) then
    Result := JsCallFunction(Result, Args, Obj.Instance)
  else
    Result := JsUndefinedValue;
end;

function PostTimedTask(Args: PJsValueRefArray; ArgCount: word;
  CallbackState: Pointer; RepeatCount: integer): JsValueRef;
var
  DataModule: TChakraInstance absolute CallbackState;
  AMessage: TTaskMessage;
  Delay: cardinal;
  FuncArgs: array[0..0] of JsValueRef;
  I: integer;
begin
  Result := JsUndefinedValue;

  if ArgCount < 2 then // thisarg, function to call, optional: delay, function args
    raise Exception.Create('Invalid arguments');

  if ArgCount >= 3 then
    Delay := JsNumberToInt(Args^[2])
  else
    Delay := 0;

  if ArgCount >= 4 then
  begin
    for I := 0 to ArgCount - 4 do
      FuncArgs[I] := Args^[I + 3];
  end;

  AMessage := TTaskMessage.Create(DataModule.Context, Args^[1], Args^[0],
    FuncArgs, Delay, RepeatCount);
  try
    DataModule.Context.PostMessage(AMessage);
  except
    AMessage.Free;
    raise;
  end;
end;

{ TChakraSystemObject }

function TChakraSystemObject.log(Arguments: PJsValueRefArray;
  CountArguments: word): JsValueRef;
var
  s: UnicodeString;
  i: Integer;
begin
  result:=JsUndefinedValue;
  if CountArguments<1 then
   Exit;

  Context.CurrentContext;
  s:='';
  for i:=0 to CountArguments-1 do
    s := s + JsStringToUnicodeString(JsValueAsJsString(Arguments^[i]));
  if Assigned(FSite) then
    FSite.log(llDebug, s)
  else
    dolog(llDebug, '[script] ' + UnicodeString(s));
end;

function TChakraSystemObject.setTimeout(Arguments: PJsValueRefArray;
  CountArguments: word): JsValueRef;
begin
  result:=JsUndefinedValue;
end;

function TChakraSystemObject.readFile(Arguments: PJsValueRefArray;
  CountArguments: word): JsValueRef;
var
  s: UnicodeString;
begin
  Result:=JsUndefinedValue;

  if CountArguments<1 then
    Exit;

  if not Assigned(FSite) then
    Exit;

  WriteLn('not implemented');
end;

function TChakraSystemObject.writeFile(Arguments: PJsValueRefArray;
  CountArguments: word): JsValueRef;
begin
  Result:=JsUndefinedValue;

  if CountArguments<2 then
    Exit;

  if not Assigned(FSite) then
    Exit;

  Writeln('not implemented');
end;

function TChakraSystemObject.load(Arguments: PJsValueRefArray;
  CountArguments: word): JsValueRef;
begin
  Result:=JsUndefinedValue;
end;

function TChakraSystemObject.save(Arguments: PJsValueRefArray;
  CountArguments: word): JsValueRef;
begin
  Result:=JsUndefinedValue;
end;

function TChakraSystemObject.eval(Arguments: PJsValueRefArray;
  CountArguments: word): JsValueRef;
begin
  Result:=JsUndefinedValue;
  if CountArguments<2 then
   Exit;

  result:=Context.RunScript(JsStringToUnicodeString(JsValueAsJsString(Arguments^[1])),
  JsStringToUnicodeString(JsValueAsJsString(Arguments^[0])));
end;

{ TChakraInstance }

procedure TChakraInstance.ContextLoadModule(Sender: TObject; Module: TChakraModule);
var
  ModuleFileName: UnicodeString;
begin
  ModuleFileName := IncludeTrailingPathDelimiter(FBasePath) +
    UnicodeString(ChangeFileExt(UnicodeString(Module.Name), '.js'));
  if FileExists(ModuleFileName) then
  begin
    Module.Parse(LoadFile(ModuleFileName));
    Module.URL := WideFormat('file://%s/%s',
      [FAlias, UnicodeString(ChangeFileExt(UnicodeString(Module.Name), '.js'))]);
  end;
end;

procedure TChakraInstance.ContextNativeObjectCreated(Sender: TObject;
  NativeObject: TNativeObject);
begin

end;

procedure TChakraInstance.ConsolePrint(Sender: TObject; const Text: UnicodeString;
  Level: TInfoLevel);
begin
  case Level of
    ilError: Write('[Error] ');
    ilInfo: Write(' [Info] ');
    ilNone: Write('  [Log] ');
    ilWarn: Write(' [Warn] ');
  end;
  Writeln(Text);
end;

constructor TChakraInstance.Create(Manager: TWebserverSiteManager;
  Site: TWebserverSite; Thread: TThread);
begin
  inherited Create([ccroEnableExperimentalFeatures,
    ccroDispatchSetExceptionsToDebugger]);

  FManager:=Manager;

  FBasePath := UnicodeString(ExtractFilePath(ParamStr(0)));
  FAlias := UnicodeString(ChangeFileExt(ExtractFileName(ParamStr(0)), ''));

  FContext := TChakraCoreContext.Create(Self);
  FContext.OnLoadModule := @ContextLoadModule;
  FContext.OnNativeObjectCreated := @ContextNativeObjectCreated;
  FContext.Activate;

  TConsole.Project('Console');
  TXMLHTTPRequest.Project('XMLHttpRequest');
  TChakraSystemObject.Project('SystemObject');

  FConsole := TConsole.Create;
  FConsole.OnLog:=@ConsolePrint;
  JsSetProperty(FContext.Global, 'console', FConsole.Instance);


  FSystemObject:=TChakraSystemObject.Create();
  JsSetProperty(FContext.Global, 'system', FSystemObject.Instance);

  {$IFDEF MSWINDOWS}
  FOverlapped.hEvent := CreateEvent(nil, False, False, nil);
  if not CreatePipeEx(FReadPipe, FWritePipe, nil, 4096, FILE_FLAG_OVERLAPPED, 0) then
  {$ELSE}
    if Assignpipe(FReadPipe, FWritePipe) <> 0 then
  {$ENDIF}
      raise Exception.Create('Could not create message pipe');
end;

destructor TChakraInstance.Destroy;
begin
  {$IFDEF MSWINDOWS}
  CloseHandle(FReadPipe);
  CloseHandle(FWritePipe);
  CloseHandle(FOverlapped.hEvent);
  {$ELSE}

  {$ENDIF}
  FConsole.Free;
  FContext.Free;
  inherited Destroy;
end;

procedure TChakraInstance.ExecuteFile(
  const ScriptFileNames: array of UnicodeString);
var
  i: integer;
begin
  for i := 0 to Length(ScriptFileNames) - 1 do
    ExecuteFile(ScriptFileNames[i]);
end;

procedure TChakraInstance.ExecuteFile(ScriptFilename: UnicodeString);
var
  OldPath, S: UnicodeString;
begin
  OldPath := FBasePath;
  S := ExtractFilePath(ScriptFilename);
  if S <> '' then
    FBasePath := S;
  FContext.RunScript(LoadFile(ScriptFilename),
      UnicodeString(ExtractFileName(ScriptFilename)));
  FBasePath := OldPath;
end;

procedure TChakraInstance.ProcessHandlers;
var
  i: Integer;
begin
  Inc(FTicks);
  for i:=0 to Length(FHandlers)-1 do
    FHandlers[i]();
end;

procedure TChakraInstance.AddEventHandler(Handler: TCallbackProc);
var
  i: Integer;
begin
  i:=Length(FHandlers);
  Setlength(FHandlers, i+1);
  FHandlers[i]:=Handler;
end;

procedure TChakraInstance.RemoveEventHandler(Handler: TCallbackProc);
var
  i: Integer;
begin
  for i:=0 to Length(FHandlers)-1 do
  begin
    if @FHandlers[i] = @Handler then
    begin
      FHandlers[i]:=FHandlers[Length(FHandlers)-1];
      Setlength(FHandlers, Length(FHandlers)-1);
      Exit;
    end;
  end;
end;

procedure TChakraInstance.OutputException(e: Exception; Section: ansistring);
var
  s: ansistring;
begin
  if e is EChakraCoreScript then
    s:='['+(EChakraCoreScript(e).ScriptURL)+':'+IntToStr(EChakraCoreScript(e).Line)+'] '+EChakraCoreScript(e).Source+#13#10+e.Message
  else
    s:=e.Message;
  if Section <> '' then
    s:='['+Section+'] '+s;

  if Assigned(FSite) then
    s:='['+FSite.Name+'] '+s;

  dolog(llError, s);
end;

procedure TChakraInstance.ReadCallback(ATimeout: longword);
{$IFNDEF MSWINDOWS}
var
  FDSet: TFDSet;
  TimeOut: TTimeVal;
{$ENDIF}
begin
  {$IFDEF MSWINDOWS}
  if not FReading then
  begin
    FProc := nil;
    if ReadFile(FReadPipe, FProc, SizeOf(FProc), FNumRead, @FOverlapped) then
    begin
      if Assigned(FProc) then
        FProc();
      Exit;
    end;
  end;
  if GetLastError <> ERROR_IO_PENDING then
    raise Exception.Create('Pipe read error');
  FReading := True;

  if WaitForSingleObject(FOverlapped.hEvent, ATimeout) = WAIT_OBJECT_0 then
  begin
    if Assigned(FProc) then
      FProc();
    FReading := False;

  end;
  {$ELSE}
  TimeOut.tv_sec := ATimeout div 1000;
  TimeOut.tv_usec := (ATimeOut mod 1000) * 1000;
  fpFD_ZERO(FDSet);
  fpFD_SET(FReadPipe, FDSet);
  fpSelect(FReadPipe + 1, @FDSet, nil, nil, @TimeOut);
  if fpFD_ISSET(FReadPipe, FDSet) <> 0 then
  begin
    if (FpRead(FReadPipe, FProc, SizeOf(FProc)) = SizeOf(FProc)) and Assigned(FProc) then
      FProc();
  end;
  {$ENDIF}
end;

procedure TChakraInstance.Callback(Proc: TCallbackProc);
{$IFDEF MSWINDOWS}
var
  NumWritten: DWORD;
{$ENDIF}
begin
  {$IFDEF MSWINDOWS}
  NumWritten := 0;
  WriteFile(FWritePipe, Proc, SizeOf(Proc), NumWritten, nil);
  {$ELSE}
  FpWrite(FWritePipe, Proc, sizeof(Proc));
  {$ENDIF}
end;

end.
