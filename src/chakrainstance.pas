unit chakrainstance;

{$i ccwssettings.inc}

interface

uses
  Classes,
  SysUtils,
  BaseUnix,
  Unix,
  contnrs,
  ChakraCommon,
  ChakraCoreClasses,
  ChakraCoreUtils,
  ChakraRTTIObject,
  ChakraEventObject,
  Compat,
  Console,
  webserverhosts;

type
  TCallbackProc = procedure of object;

  { TNodeModule }

  TNodeModule = class
  private
    FFileName: UnicodeString;
    FHandle: JsvalueRef;
    FParent: TNodeModule;
    FRequire: JsValueRef;
  public
    constructor Create(AParent: TNodeModule);

    property FileName: UnicodeString read FFileName;
    property Handle: JsValueRef read FHandle;
    property Parent: TNodeModule read FParent;
    property Require: JsValueRef read FRequire;
  end;

  TChakraInstance = class;

  TChakraTimedEvent = record
    action: JsValueRef;
    TimeOut: LongWord;
    Timestamp: QWord;
    DoRepeat: Boolean;
  end;

  { TChakraSystemObject }

  TChakraSystemObject = class(TNativeRTTIObject)
  private
    FChakraInstance: TChakraInstance;
    FSite: TWebserverSite;
    FTimedEvents: array of TChakraTimedEvent;
    procedure ProcessEvents;
  public
    constructor Create(AInstance: TChakraInstance);
  published
    function log(Arguments: PJsValueRefArray; CountArguments: word): JsValueRef;
    function setTimeout(Arguments: PJsValueRefArray; CountArguments: word): JsValueRef;
    function setInterval(Arguments: PJsValueRefArray; CountArguments: word): JsValueRef;
    function eval(Arguments: PJsValueRefArray; CountArguments: word): JsValueRef;
  end;

  { TChakraInstance }

  TChakraInstance = class(TChakraCoreRuntime)
  private
    FManager: TWebserverSiteManager;
    FSite: TWebserverSite;
    FAlias, FBasePath: string;
    FContext: TChakraCoreContext;
    FSystemObject: TChakraSystemObject;
    FReadPipe, FWritePipe: THandle;
    FProc: TCallbackProc;
    FHandlers: array of TCallbackProc;
    FConsole: TConsole;
    FTicks: LongWord;
    FMainModule: TNodeModule;
    FModules: TObjectList;
    procedure ContextLoadModule(Sender: TObject; Module: TChakraModule);
    procedure ContextNativeObjectCreated(Sender: TObject; NativeObject: TNativeObject);
    procedure ConsolePrint(Sender: TObject; const Text: UnicodeString;
      Level: TInfoLevel = ilNone);
    function FindModule(ARequire: JsValueRef): TNodeModule; overload;
    function FindModule(const AFileName: UnicodeString): TNodeModule; overload;
    procedure LoadModule(Module: TNodeModule; const FileName: UnicodeString);
    function LoadPackage(const FileName: UnicodeString): JsValueRef;
    function Require(CallerModule: TNodeModule; const Path: UnicodeString): JsValueRef;
    function Resolve(const Request, CurrentPath: UnicodeString): UnicodeString;
    function ResolveDirectory(const Request: UnicodeString; out FileName: UnicodeString): Boolean;
    function ResolveFile(const Request: UnicodeString; out FileName: UnicodeString): Boolean;
    function ResolveIndex(const Request: UnicodeString; out FileName: UnicodeString): Boolean;
    function ResolveModules(const Request: UnicodeString; out FileName: UnicodeString): Boolean;
    function RunModule(Module: TNodeModule): JsValueRef;
  public
    constructor Create(Manager: TWebserverSiteManager; Site: TWebserverSite);
      reintroduce;
    destructor Destroy; override;
    procedure ExecuteFile(const ScriptFileNames: array of string); overload;
    procedure ExecuteFile(ScriptFilename: string); overload;
    procedure ProcessHandlers;
    procedure AddEventHandler(Handler: TCallbackProc);
    procedure RemoveEventHandler(Handler: TCallbackProc);
    procedure OutputException(e: Exception; Section: string = '');
    procedure ReadCallback(ATimeout: longword);
    procedure Callback(Proc: TCallbackProc);
    property Context: TChakraCoreContext read FContext;
  end;

function LoadFile(const FileName: string): string;
function ExecuteCallback(Obj: TNativeObject; FuncName: string; Args: PJsValueRef; ArgCount: Word): JsValueRef; overload;
function ExecuteCallback(Obj: TNativeObject; FuncName: string; const Args: array of JsValueRef): JsValueRef; overload;

implementation

uses
  chakraevents,
  logging,
  xmlhttprequest;

function LoadFile(const FileName: string): string;
var
  FileStream: TFileStream;
  S: UTF8String;
begin
  Result := '';

  FileStream := TFileStream.Create(FileName, fmOpenRead);
  try
    if FileStream.Size = 0 then
      Exit;

    SetLength(S, FileStream.Size);
    FileStream.Read(S[1], FileStream.Size);

    Result := S;
  finally
    FileStream.Free;
  end;
end;

function ExecuteCallback(Obj: TNativeObject; FuncName: string; Args: PJsValueRef; ArgCount: Word): JsValueRef;
begin
  Result:=JsGetProperty(Obj.Instance, FuncName);
  if Assigned(Result) and (JsGetValueType(Result) = JsFunction) then
    Result := JsCallFunction(Result, Args, ArgCount)
  else
    Result := JsUndefinedValue;
end;

function ExecuteCallback(Obj, ThisObj: TNativeObject; FuncName: string;
  const Args: array of JsValueRef): JsValueRef;
begin
  Result:=JsGetProperty(Obj.Instance, FuncName);
  if Assigned(Result) and (JsGetValueType(Result) = JsFunction) then
    Result := JsCallFunction(Result, Args, ThisObj.Instance)
  else
    Result := JsUndefinedValue;
end;

function ExecuteCallback(Obj: TNativeObject; FuncName: string;
  const Args: array of JsValueRef): JsValueRef;
begin
  Result:=JsGetProperty(Obj.Instance, FuncName);
  if Assigned(Result) and (JsGetValueType(Result) = JsFunction) then
    Result := JsCallFunction(Result, Args, Obj.Instance)
  else
    Result := JsUndefinedValue;
end;

function Require_Callback(Callee: JsValueRef; IsConstructCall: bool; Arguments: PJsValueRef; ArgCount: Word;
CallbackState: Pointer): JsValueRef; cdecl;
var
  DataModule: TChakraInstance absolute CallbackState;
  Args: PJsValueRefArray absolute Arguments;
  CallerModule: TNodeModule;
  Path: UnicodeString;
begin
  Result := JsUndefinedValue;
  try
    if ArgCount <> 2 then
      raise Exception.Create('require: module name not specified');

    if JsGetValueType(Args^[1]) <> JsString then
      raise Exception.Create('require: module name not a string value');

    CallerModule := DataModule.FindModule(Callee);
    Path := JsStringToUnicodeString(Args^[1]);
    if PathDelim <> '/' then
      Path := UnicodeStringReplace(Path, '/', PathDelim, [rfReplaceAll]);

    Result := DataModule.Require(CallerModule, Path);
  except
    on E: EChakraCoreScript do
      JsThrowError(WideFormat('%s (%d, %d): [%s] %s', [E.ScriptURL, E.Line + 1, E.Column + 1, E.ClassName, E.Message]));
    on E: Exception do
      JsThrowError(WideFormat('[%s] %s', [E.ClassName, E.Message]));
  end;
end;

{ TNodeModule }

constructor TNodeModule.Create(AParent: TNodeModule);
begin
  inherited Create;
  FParent:=AParent;
end;

{ TChakraSystemObject }

procedure TChakraSystemObject.ProcessEvents;
var
  i: Integer;
  CurrentTime: QWord;
begin
  i:=0;
  CurrentTime:=GetTickCount64;
  while i < Length(FTimedEvents) do
  begin
    if FTimedEvents[i].Timestamp + FTimedEvents[i].TimeOut <= CurrentTime then
    begin
      if JsGetValueType(FTimedEvents[i].action) = JsFunction then
      begin
        try
          JsCallFunction(FTimedEvents[i].action, [], Context.Global);
        except
          on e: Exception do dolog(llError, 'Exception in timed event: ' + e.Message);
        end;
      end else
      begin
        Context.RunScript(JsStringToUnicodeString(JsValueAsJsString(FTimedEvents[i].action)), UnicodeString('<Timed Event>'));
      end;
      if FTimedEvents[i].DoRepeat then
      begin
        // adjust for jitter since this method only called in certain intervals
        FTimedEvents[i].Timestamp:=FTimedEvents[i].Timestamp + FTimedEvents[i].TimeOut;

        // in case we have been blocked for a while, lets skip some so we
        if FTimedEvents[i].Timestamp < CurrentTime - FTimedEvents[i].TimeOut then
        begin
          FTimedEvents[i].Timestamp := CurrentTime - FTimedEvents[i].TimeOut;
        end;
        Inc(i);
      end else
      begin
        JsRelease(FTimedEvents[i].action);
        FTimedEvents[i] := FTimedEvents[Length(FTimedEvents) - 1];
        Setlength(FTimedEvents, Length(FTimedEvents) - 1);
      end;
    end else
      Inc(i);
  end;
end;

constructor TChakraSystemObject.Create(AInstance: TChakraInstance);
begin
  inherited Create(nil, 0, True);
  FChakraInstance:=AInstance;
  FChakraInstance.AddEventHandler(@ProcessEvents);
end;

function TChakraSystemObject.log(Arguments: PJsValueRefArray;
  CountArguments: word): JsValueRef;
var
  s: string;
  i: Integer;
begin
  result:=JsUndefinedValue;
  if CountArguments<1 then
   Exit;

  Context.CurrentContext;
  s:='';
  for i:=0 to CountArguments-1 do
    s := s + string(JsStringToUnicodeString(JsValueAsJsString(Arguments^[i])));
  if Assigned(FSite) then
    FSite.log(llDebug, s)
  else
    dolog(llDebug, '[script] ' + string(s));
end;

function TChakraSystemObject.setTimeout(Arguments: PJsValueRefArray;
  CountArguments: word): JsValueRef;
var
  i: Integer;
begin
  result:=JsUndefinedValue;
  if CountArguments < 1 then
    Exit;

  i:=Length(FTimedEvents);
  Setlength(FTimedEvents, i + 1);
  FTimedEvents[i].DoRepeat:=False;
  FTimedEvents[i].Timestamp:=GetTickCount64;
  FTimedEvents[i].action:=Arguments^[0];
  JsAddRef(FTimedEvents[i].action);
  if CountArguments > 1 then
    FTimedEvents[i].TimeOut:=JsNumberToInt(Arguments^[1])
  else
    FTimedEvents[i].TimeOut:=0;
end;

function TChakraSystemObject.setInterval(Arguments: PJsValueRefArray;
  CountArguments: word): JsValueRef;
var
  i: Integer;
begin
  result:=JsUndefinedValue;
  if CountArguments < 1 then
    Exit;

  i:=Length(FTimedEvents);
  Setlength(FTimedEvents, i + 1);
  FTimedEvents[i].DoRepeat:=True;
  FTimedEvents[i].Timestamp:=GetTickCount64;
  FTimedEvents[i].action:=Arguments^[0];
  JsAddRef(FTimedEvents[i].action);
  if CountArguments > 1 then
    FTimedEvents[i].TimeOut:=JsNumberToInt(Arguments^[1])
  else
    FTimedEvents[i].TimeOut:=0;
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
  ModuleFileName: string;
begin
  // TODO: fix unicode
  ModuleFileName := IncludeTrailingPathDelimiter(FBasePath) + ChangeFileExt(UTF8Encode(Module.Name), '.js');
  if FileExists(ModuleFileName) then
  begin
    Module.Parse(UTF8ToString(LoadFile(ModuleFileName)));
    Module.URL := WideFormat('file://%s/%s',
      [FAlias, UTF8Decode(ChangeFileExt(UTF8Encode(Module.Name), '.js'))]);
  end;
end;

procedure TChakraInstance.ContextNativeObjectCreated(Sender: TObject;
  NativeObject: TNativeObject);
begin

end;

procedure TChakraInstance.ConsolePrint(Sender: TObject;
  const Text: UnicodeString; Level: TInfoLevel);
begin
  case Level of
    ilError: dolog(llError, UTF8Encode(Text));
    ilInfo: dolog(llNotice, UTF8Encode(Text));
    ilNone: dolog(llDebug, UTF8Encode(Text));
    ilWarn: dolog(llWarning, UTF8Encode(Text));
  end;
end;

function TChakraInstance.FindModule(ARequire: JsValueRef): TNodeModule;
var
  I: Integer;
begin
  Result := nil;

  for I := 0 to FModules.Count - 1 do
    if TNodeModule(FModules[I]).Require = ARequire then
    begin
      Result := TNodeModule(FModules[I]);
      Break;
    end;
end;

function TChakraInstance.FindModule(const AFileName: UnicodeString
  ): TNodeModule;
var
  I: Integer;
begin
  Result := nil;

  for I := 0 to FModules.Count - 1 do
    if WideSameText(AFileName, TNodeModule(FModules[I]).FileName) then
    begin
      Result := TNodeModule(FModules[I]);
      Break;
    end;
end;

procedure TChakraInstance.LoadModule(Module: TNodeModule;
  const FileName: UnicodeString);
var
  WrapScript: UnicodeString;
begin
  if ExtractFileExt(FileName) = '.json' then
    WrapScript := '(function (exports, require, module, __filename, __dirname) {' + sLineBreak +
      'module.exports = ' + LoadFile(UTF8Encode(FileName)) + ';' + UnicodeString(sLineBreak) + '})'
  else
    WrapScript := '(function (exports, require, module, __filename, __dirname) {' + sLineBreak +
      LoadFile(UTF8Encode(FileName)) + sLineBreak + '})';
  Module.FFileName := FileName;
  Module.FHandle := FContext.RunScript(WrapScript, FileName);
  JsSetProperty(Module.Handle, 'exports', JsCreateObject);
  JsSetProperty(Module.Handle, '__dirname', StringToJsString(ExtractFilePath(FileName)));
  JsSetProperty(Module.Handle, '__filename', StringToJsString(FileName));
  Module.FRequire := JsSetCallback(Module.Handle, 'require', @Require_Callback, Self);
end;

function TChakraInstance.LoadPackage(const FileName: UnicodeString): JsValueRef;
begin
  Result := FContext.CallFunction('parse', [StringToJsString(LoadFile(UTF8Encode(FileName)))], JsGetProperty(JsGlobal, 'JSON'));
end;

function TChakraInstance.Require(CallerModule: TNodeModule;
  const Path: UnicodeString): JsValueRef;
var
  FileName: UnicodeString;
  Module: TNodeModule;
begin
  if Assigned(CallerModule) then
    FileName := Resolve(Path, ExtractFilePath(CallerModule.FileName))
  else
    FileName := Resolve(Path, FBasePath);

  if FileName = '' then
    raise Exception.CreateFmt('Module ''%s'' not found', [Path]);

  FileName := ExpandFileName(FileName);

  Module := FindModule(FileName);
  if not Assigned(Module) then
  begin
    Module := TNodeModule.Create(CallerModule);
    try
      FModules.Add(Module);
      LoadModule(Module, FileName);
      RunModule(Module);
    except
      on E: Exception do
      begin
        if Module <> FMainModule then
          FModules.Remove(Module);
        raise;
      end;
    end;
  end;

  Result := JsGetProperty(Module.Handle, 'exports');
end;

function TChakraInstance.Resolve(const Request, CurrentPath: UnicodeString
  ): UnicodeString;
var
  BasePaths: array[0..1] of UnicodeString;
  SRequest: UnicodeString;
  I: Integer;
begin
  Result := '';
  if Request = '' then
    Exit;

  if Request[1] = '/' then
    BasePaths[0] := {$ifdef MSWINDOWS}ExtractFileDrive(CurrentPath){$else}''{$endif};
  if (Request[1] = PathDelim) or
    ((Length(Request) > 1) and (Request[1] = '.') and (Request[2] = PathDelim)) or
    ((Length(Request) > 2) and (Request[1] = '.') and (Request[2] = '.') and (Request[3] = PathDelim)) then
    BasePaths[0] := CurrentPath;
  BasePaths[1] := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + '..' + PathDelim + '..' + PathDelim +
    'ext' + PathDelim + 'node' + PathDelim + 'lib';

  SRequest := Request;
  if PathDelim <> '/' then
    SRequest := UnicodeStringReplace(SRequest, '/', PathDelim, [rfReplaceAll]);

  for I := Low(BasePaths) to High(BasePaths) do
  begin
    if ResolveFile(IncludeTrailingPathDelimiter(BasePaths[I]) + SRequest, Result) then
      Exit;
    if ResolveDirectory(IncludeTrailingPathDelimiter(BasePaths[I]) + SRequest, Result) then
      Exit;
  end;

  if not ResolveModules(Request, Result) then
    Result := '';
end;

function TChakraInstance.ResolveDirectory(const Request: UnicodeString; out
  FileName: UnicodeString): Boolean;
var
  Package, Main: UnicodeString;
begin
  FileName := '';

  Package := IncludeTrailingPathDelimiter(Request) + 'package.json';
  if FileExists(Package) then
  begin
    Main := IncludeTrailingPathDelimiter(Request) + JsStringToUnicodeString(JsGetProperty(LoadPackage(Package), 'main'));
    if PathDelim <> '/' then
      Main := UnicodeStringReplace(Main, '/', PathDelim, [rfReplaceAll]);

    Result := ResolveFile(Main, FileName) or ResolveIndex(Main, FileName);
    if Result then
      Exit;
  end;

  Result := ResolveIndex(Request, FileName);
end;

function TChakraInstance.ResolveFile(const Request: UnicodeString; out
  FileName: UnicodeString): Boolean;
begin
  Result := False;
  FileName := '';

  if FileExists(Request) and not DirectoryExists(Request) then
  begin
    FileName := Request;
    Result := True;
  end
  else if FileExists(Request + '.js') then
  begin
    FileName := Request + '.js';
    Result := True;
  end
  else if FileExists(Request + '.json') then
  begin
    FileName := Request + '.json';
    Result := True;
  end
  else if FileExists(Request + '.node') then
  begin
    FileName := Request + '.node';
    Result := True;
  end;
end;

function TChakraInstance.ResolveIndex(const Request: UnicodeString; out
  FileName: UnicodeString): Boolean;
begin
  Result := False;
  FileName := '';

  if FileExists(IncludeTrailingPathDelimiter(Request) + 'index.js') then
  begin
    FileName := IncludeTrailingPathDelimiter(Request) + 'index.js';
    Result := True;
  end
  else if FileExists(IncludeTrailingPathDelimiter(Request) + 'index.json') then
  begin
    FileName := IncludeTrailingPathDelimiter(Request) + 'index.json';
    Result := True;
  end
  else if FileExists(IncludeTrailingPathDelimiter(Request) + 'index.node') then
  begin
    FileName := IncludeTrailingPathDelimiter(Request) + 'index.node';
    Result := True;
  end
end;

function TChakraInstance.ResolveModules(const Request: UnicodeString; out
  FileName: UnicodeString): Boolean;
var
  NodeModulePaths: array of UnicodeString;
  I: Integer;
begin
  Result := False;
  FileName := '';

  // TODO global paths etc.
  SetLength(NodeModulePaths, 1);
  NodeModulePaths[0] := IncludeTrailingPathDelimiter(FBasePath) + 'node_modules';

  for I := 0 to High(NodeModulePaths) do
  begin
    Result := ResolveFile(IncludeTrailingPathDelimiter(NodeModulePaths[I]) + Request, FileName);
    if Result then
      Break;
    Result := ResolveDirectory(IncludeTrailingPathDelimiter(NodeModulePaths[I]) + Request, FileName);
    if Result then
      Break;
  end;
end;

function TChakraInstance.RunModule(Module: TNodeModule): JsValueRef;
begin
  FContext.CallFunction(Module.Handle, [JsGetProperty(Module.Handle, 'exports'), Module.Require, Module.Handle,
    StringToJsString(Module.FileName), StringToJsString(ExtractFilePath(Module.FileName))], Module.Handle);
  Result := JsGetProperty(Module.Handle, 'exports');
end;

constructor TChakraInstance.Create(Manager: TWebserverSiteManager;
  Site: TWebserverSite);
begin
  inherited Create([ccroEnableExperimentalFeatures,
    ccroDispatchSetExceptionsToDebugger]);

  FModules:=TObjectList.Create();
  FManager:=Manager;
  FSite:=Site;

  FBasePath := string(ExtractFilePath(ParamStr(0)));
  FAlias := string(ChangeFileExt(ExtractFileName(ParamStr(0)), ''));

  FContext := TChakraCoreContext.Create(Self);
  FContext.OnLoadModule := @ContextLoadModule;
  FContext.OnNativeObjectCreated := @ContextNativeObjectCreated;
  FContext.Activate;

  TConsole.Project('Console');
  TChakraEvent.Project('Event');
  TChakraEventListener.Project('GlobalEventListener');
  TXMLHTTPRequest.Project('XMLHttpRequest');

  FConsole := TConsole.Create;
  FConsole.OnLog:=@ConsolePrint;
  JsSetProperty(FContext.Global, 'console', FConsole.Instance);

  FMainModule := TNodeModule.Create(nil);
  FModules.Add(FMainModule);

  FSystemObject:=TChakraSystemObject.Create(Self);
  JsSetProperty(FContext.Global, 'system', FSystemObject.Instance);

  if Assignpipe(FReadPipe, FWritePipe) <> 0 then
    raise Exception.Create('Could not create message pipe');
end;

destructor TChakraInstance.Destroy;
begin
  FConsole.Free;
  FModules.Free;
  FContext.Free;
  inherited Destroy;
end;

procedure TChakraInstance.ExecuteFile(
  const ScriptFileNames: array of string);
var
  i: integer;
begin
  for i := 0 to Length(ScriptFileNames) - 1 do
    ExecuteFile(ScriptFileNames[i]);
end;

procedure TChakraInstance.ExecuteFile(ScriptFilename: string);
var
  OldPath, S: string;
begin
  OldPath := FBasePath;
  S := ExtractFilePath(UTF8Encode(ScriptFilename));
  if S <> '' then
    FBasePath := S;

  LoadModule(FMainModule, UTF8ToString(ScriptFileName));
  RunModule(FMainModule);

//  FContext.RunScript(UTF8ToString(LoadFile(ScriptFilename)), UTF8ToString(ExtractFileName(ScriptFilename)));
  FBasePath := OldPath;
end;

procedure TChakraInstance.ProcessHandlers;
var
  i: Integer;
begin
  Inc(FTicks);
  for i:=0 to Length(FHandlers)-1 do
    FHandlers[i]();
  ReadCallback(0);
end;

procedure TChakraInstance.AddEventHandler(Handler: TCallbackProc);
var
  i: Integer;
begin
  for i:=0 to Length(FHandlers)-1 do
  if (TMethod(FHandlers[i]).Code = TMethod(Handler).Code) and
     (TMethod(FHandlers[i]).Data = TMethod(Handler).Data)  then
  begin
    dolog(llError, 'event handler already declared');
    Exit;
  end;
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
    if (TMethod(FHandlers[i]).Code = TMethod(Handler).Code) and
       (TMethod(FHandlers[i]).Data = TMethod(Handler).Data)  then
    begin
      FHandlers[i]:=FHandlers[Length(FHandlers)-1];
      Setlength(FHandlers, Length(FHandlers)-1);
      Exit;
    end;
  end;
  dolog(llError, 'Could not find event handler');
end;

procedure TChakraInstance.OutputException(e: Exception; Section: string);
var
  s: string;
begin
  if e is EChakraCoreScript then
    s:='['+string(EChakraCoreScript(e).ScriptURL)+':'+string(IntToStr(EChakraCoreScript(e).Line))+'] '+string(EChakraCoreScript(e).Source)+#13#10+string(e.Message)
  else
    s:=string(e.Message);
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
