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
  TLogItems = array of Variant;

var
  GlobalLogLevel: TLoglevel;

procedure dolog(LogLevel: TLogLevel; const Message: TLogItems); overload;
procedure dolog(Loglevel: TLoglevel; msg: string); overload;
procedure LogToFile(filename: string);

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

procedure dolog(LogLevel: TLogLevel; const Message: TLogItems);
var
  i: Integer;
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
  for i:=Low(Message) to High(Message) do
    Write(Message[i]);
  Writeln;
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
    Writeln(StdOut, s);

  CS.Leave;
end;

initialization
  GlobalLogLevel:=llDebug;
  DoLogToFile:=False;
  CS:=TCriticalSection.Create;
finalization
  CS.Free;
end.
