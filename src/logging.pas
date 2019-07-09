unit logging;

{$i ccwssettings.inc}

interface

uses
  Classes,
  SysUtils,
  SyncObjs,
  dateutils,
  Variants;

type
  TLoglevel = (llDebug=0, llNotice=1, llWarning=2, llError=3, llFatal=4);

var
  GlobalLogLevel: TLoglevel;

procedure dolog(LogLevel: TLogLevel; Message: array of string); overload;
procedure dolog(Loglevel: TLoglevel; msg: string); overload;
procedure LogToFile(filename: string);
function DumpExceptionCallStack(E: Exception): string;
procedure LogException(E: Exception); overload;
procedure LogException(E: Exception; Section: string); overload;

implementation

var CS: TCriticalSection;

var
  FileHandle: Textfile;
  DoLogToFile: Boolean;

procedure LogToFile(filename: string);
begin
  AssignFile(Filehandle, filename);
  rewrite(Filehandle);
  DoLogToFile:=True;

end;

procedure dolog(LogLevel: TLogLevel; Message: array of string);
var
  i: Integer;
  target: TextFile;
begin
  if LogLevel<GlobalLogLevel then
    Exit;

  Write('[', TimeToStr(Time),'] ');
  case LogLevel of
    llDebug:   Write('  [Debug] ');
    llNotice:  Write(' [Notice] ');
    llWarning: Write('[Warning] ');
    llError:   Write('  [Error] ');
    llFatal:   Write('  [Fatal] ');
  end;
  if DoLogToFile then
    target:=FileHandle
  else
    target:=StdOut;

  CS.Enter;
  try
    for i:=Low(Message) to High(Message) do
      Write(target, Message[i]);
    Writeln(target);
  finally
    CS.Leave;
  end;
  Flush(Target);
end;

procedure dolog(Loglevel: TLoglevel; msg: string);
var
  s: string;
begin
  if LogLevel<GlobalLogLevel then
    Exit;
  case Loglevel of
    llDebug:   s:='['+string(TimeToStr(Time))+']   [Debug] '+msg;
    llNotice:  s:='['+string(TimeToStr(Time))+']  [Notice] '+msg;
    llWarning: s:='['+string(TimeToStr(Time))+'] [Warning] '+msg;
    llError:   s:='['+string(TimeToStr(Time))+']   [Error] '+msg;
    llFatal:   s:='['+string(TimeToStr(Time))+']   [Fatal] '+msg;
    else
               s:='['+string(TimeToStr(Time))+'] [???????] '+msg;
  end;
  CS.Enter;
  if DoLogToFile then
  begin
    Writeln(Filehandle, s);
    Flush(Filehandle);
  end else
  begin
    Writeln(StdOut, s);
    Flush(StdOut);
  end;
  CS.Leave;
end;

function DumpExceptionCallStack(E: Exception): string;
var
  I: Integer;
  Frames: PPointer;
begin
  if E <> nil then
  begin
    Result := 'Exception class: ' + E.ClassName + LineEnding +
    'Message: ' + E.Message + LineEnding;
  end else
    Result := 'Stacktrace:' + LineEnding;
  Result := Result + BackTraceStrFunc(ExceptAddr);
  Frames := ExceptFrames;
  for I := 0 to ExceptFrameCount - 1 do
    Result := Result + LineEnding + BackTraceStrFunc(Frames[I]);
end;

procedure LogException(E: Exception);
begin
  dolog(llError, [DumpExceptionCallStack(e)]);
end;

procedure LogException(E: Exception; Section: string);
begin
  dolog(llError, ['[', Section, '] ', DumpExceptionCallStack(e)]);
end;

initialization
  GlobalLogLevel:=llDebug;
  DoLogToFile:=False;
  CS:=TCriticalSection.Create;
finalization
  CS.Free;
end.
