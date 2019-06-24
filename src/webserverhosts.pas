unit webserverhosts;
{
 managment classes for sites

 a "site" in besenws terminology describes a single website with all data and scripts.

 Copyright (C) 2016 Simon Ley

 This program is free software: you can redistribute it and/or modify
 it under the terms of the GNU Lesser General Public License as published
 by the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU Lesser General Public License
 along with this program.  If not, see <http://www.gnu.org/licenses/>.
}
{$i ccwssettings.inc}

interface

uses
  Classes,
  SysUtils,
  syncobjs,
  contnrs,
  httphelper,
  epollsockets,
  logging;

const
  CustomStatusPageMin = 400;
  CustomStatusPageMax = 511;

type
  TWebserverSiteManager = class;
  TWebserverSite = class;

  { TWebserverSite }

  TWebserverSite = class
  private
    FCS: TCriticalSection;
    FName, FPath: UnicodeString;
    FParent: TWebserverSiteManager;
    FCustomHandlers: TFPObjectHashTable;
    FScriptDirs: array of record
      Dir: UnicodeString;
      Script: UnicodeString;
    end;
    FResponseHeaders: array of record
      Name: UnicodeString;
      Value: UnicodeString;
    end;
    FIndexNames: array of UnicodeString;
    FWhitelistedProcesses: array of UnicodeString;
    FForwards: TFPStringHashTable;
    FCustomStatusPages: array[CustomStatusPageMin..CustomStatusPageMax] of UnicodeString;
    procedure ClearItem(Item: TObject; const Key: AnsiString; var Continue: Boolean);
  public
    constructor Create(Parent: TWebserverSiteManager; Path: UnicodeString);
    destructor Destroy; override;
    procedure log(Level: TLoglevel; Msg: UnicodeString);
    procedure AddScriptDirectory(directory, filename: UnicodeString);
    procedure AddForward(target, NewTarget: UnicodeString);
    procedure AddIndexPage(name: UnicodeString);
    function IsScriptDir(target: UnicodeString; out Script, Params: UnicodeString): Boolean;
    function IsForward(target: UnicodeString; out NewTarget: UnicodeString): Boolean;
    procedure AddResponseHeader(const name, value: UnicodeString);
    procedure AddHostAlias(HostName: UnicodeString);
    procedure AddCustomHandler(url: UnicodeString; Handler: TEpollWorkerThread);
    procedure AddCustomStatusPage(StatusCode: Word; URI: UnicodeString);
    procedure ApplyResponseHeader(const Response: THTTPReply);
    procedure AddWhiteListProcess(const Executable: UnicodeString);
    function IsProcessWhitelisted(const Executable: UnicodeString): Boolean;
    function GetCustomStatusPage(StatusCode: Word): UnicodeString;
    function GetCustomHandler(url: UnicodeString): TEpollWorkerThread;
    function GetIndexPage(var target: UnicodeString): UnicodeString;
    property Path: UnicodeString read FPath;
    property Name: UnicodeString read FName;
    property Parent: TWebserverSiteManager read FParent;
  end;

  { TWebserverSiteManager }

  TWebserverSiteManager = class
  private
    FDefaultHost: TWebserverSite;
    FHosts: array of TWebserverSite;
    FHostsByName: TFPObjectHashTable;
    FPath: UnicodeString;
    FSharedScriptsDir: UnicodeString;
    FHostToDelete: TWebserverSite;
    Procedure HostNameDeleteIterator(Item: TObject; const Key: AnsiString; var Continue: Boolean);
  public
    constructor Create(const BasePath: UnicodeString);
    destructor Destroy; override;
    function UnloadSite(Path: UnicodeString): Boolean;
    function AddSite(Path: UnicodeString): TWebserverSite;
    function GetSite(Hostname: UnicodeString): TWebserverSite;
    property Path: UnicodeString read FPath;
    property DefaultHost: TWebserverSite read FDefaultHost write FDefaultHost;
  end;


function IntToFilesize(Size: longword): UnicodeString;

implementation

uses
  webserver,
  chakraserverconfig;

function FileToStr(const aFilename: UnicodeString): UnicodeString;
var
  f: File;
begin
  Assignfile(f, aFilename);
  {$I-}Reset(f,1); {$I+}
  if ioresult=0 then
  begin
    Setlength(result, FileSize(f));
    Blockread(f, result[1], Filesize(f));
    CloseFile(f);
  end else
    result:='{}';
end;

procedure WriteFile(const aFilename, aContent: UnicodeString);
var
  f: file;
begin
  Assignfile(f, aFilename);
  {$I-}Rewrite(f, 1);{$I+}
  if ioresult = 0 then
  begin
    {$I-}BlockWrite(f, aContent[1], Length(aContent));{$I+}
    if ioresult<>0 then
      dolog(llError, aFilename+': Could not write to disk!');
    Closefile(f);
  end;
end;

{ TWebserverSite }

procedure TWebserverSite.ClearItem(Item: TObject; const Key: AnsiString;
  var Continue: Boolean);
begin
  Item.free;
end;

constructor TWebserverSite.Create(Parent: TWebserverSiteManager;
  Path: UnicodeString);
begin
  FCS:=TCriticalSection.Create;
  FForwards:=TFPStringHashTable.Create;
  FCustomHandlers:=TFPObjectHashTable.Create(False);

  FParent:=Parent;
  FName:=Path;
  FPath:=FParent.Path+Path+'/';

  AddIndexPage('index.htm');
  AddIndexPage('index.html');
end;

destructor TWebserverSite.Destroy;
begin
  FForwards.Free;
  FCustomHandlers.Iterate(@ClearItem);
  FCustomHandlers.Free;
  FCS.Free;
  Setlength(FScriptDirs, 0);
  log(llNotice, 'Site unloaded');
  inherited Destroy;
end;

procedure TWebserverSite.log(Level: TLoglevel; Msg: UnicodeString);
begin
  dolog(Level, '['+FName+'] '+Msg);
end;

function IntToFilesize(Size: longword): UnicodeString;

function Foo(A: longword): UnicodeString;
var
  b: longword;
begin
  result:=IntToStr(Size div A);

  if a=1 then
    Exit;

  b:=(Size mod a)div (a div 1024);
  b:=(b*100) div 1024;

  if b<10 then
    result:=result+'.0'+IntToStr(b)
  else
    result:=result+'.'+IntTOStr(b);
end;

begin
  if Size<1024 then
    result:=Foo(1)+' B'
  else if Size < 1024*1024 then
    result:=Foo(1024) + ' kB'
  else if Size < 1024*1024*1024 then
    result:=Foo(1024*1024) + ' mB'
  else
    result:=Foo(102*1024*1024) + ' gB';
end;

procedure TWebserverSite.AddScriptDirectory(directory, filename: UnicodeString);
var
  i: Integer;
begin
  i:=Length(FScriptDirs);
  Setlength(FScriptDirs, i+1);
  FScriptDirs[i].script:=filename;
  FScriptDirs[i].dir:=directory;
end;

procedure TWebserverSite.AddForward(target, NewTarget: UnicodeString);
begin
  FForwards[target]:=NewTarget;
end;

procedure TWebserverSite.AddIndexPage(name: UnicodeString);
var
  i: Integer;
begin
  i:=Length(FIndexNames);
  Setlength(FIndexNames, i+1);
  FIndexNames[i]:=name;
end;

function TWebserverSite.IsScriptDir(target: UnicodeString; out Script, Params: UnicodeString
  ): Boolean;
var
  i: Integer;
begin
  result:=False;
  for i:=0 to Length(FScriptDirs)-1 do
  if Pos(FScriptDirs[i].dir, target)>0 then
  begin
    result:=True;
    Script:=FScriptDirs[i].script;
    Params:=Copy(target, Length(FScriptDirs[i].dir), Length(Target));
    Exit;
  end;
end;

function TWebserverSite.IsForward(target: UnicodeString; out NewTarget: UnicodeString
  ): Boolean;
begin
  NewTarget:=FForwards[target];
  result:=NewTarget<>'';
end;

procedure TWebserverSite.AddResponseHeader(const name, value: UnicodeString);
var
  i: Integer;
  add:Boolean;
begin
  FCS.Enter;
  try
    add:=True;
    for i:=0 to Length(FResponseHeaders)-1 do
    if FResponseHeaders[i].name = name then
    begin
      if value='' then
      begin
        FResponseHeaders[i]:=FResponseHeaders[Length(FResponseHeaders)-1];
        Setlength(FResponseHeaders, Length(FResponseHeaders)-1);
      end else
        FResponseHeaders[i].value:=value;
      add:=False;
      Break;
    end;
    if add then
    begin
      i:=Length(FResponseHeaders);
      Setlength(FResponseHeaders, i+1);
      FResponseHeaders[i].name:=name;
      FResponseHeaders[i].value:=value;
    end;
  finally
    FCS.Leave;
  end;
end;

procedure TWebserverSite.AddHostAlias(HostName: UnicodeString);
begin
  FParent.FHostsByName.Add(HostName, Self);
end;

procedure TWebserverSite.AddCustomHandler(url: UnicodeString;
  Handler: TEpollWorkerThread);
begin
  FCustomHandlers.Add(url, Handler);
end;

procedure TWebserverSite.AddCustomStatusPage(StatusCode: Word; URI: UnicodeString);
begin
  if (StatusCode>=CustomStatusPageMin)and
     (StatusCode<=CustomStatusPageMax) then
  FCustomStatusPages[StatusCode]:=URI;
end;

procedure TWebserverSite.ApplyResponseHeader(const Response: THTTPReply);
var
  i: Integer;
begin
  FCS.Enter;
  try
    for i:=0 to Length(FResponseHeaders)-1 do
      Response.header.Add(FResponseHeaders[i].name, FResponseHeaders[i].Value);
  finally
    FCS.Leave;
  end;
end;

procedure TWebserverSite.AddWhiteListProcess(const Executable: UnicodeString);
var
  i: Integer;
begin
  i:=Length(FWhitelistedProcesses);
  SetLength(FWhitelistedProcesses, i+1);
  FWhitelistedProcesses[i]:=Executable;
end;

function TWebserverSite.IsProcessWhitelisted(const Executable: UnicodeString
  ): Boolean;
var
  i: Integer;
begin
  result:=False;
  for i:=0 to Length(FWhitelistedProcesses)-1 do
  if FWhitelistedProcesses[i] = Executable then
  begin
    result:=True;
    Exit;
  end;
end;

function TWebserverSite.GetCustomStatusPage(StatusCode: Word): UnicodeString;
begin
  if (StatusCode>=CustomStatusPageMin)and
     (StatusCode<=CustomStatusPageMax) then
    result:=FCustomStatusPages[StatusCode]
  else
    result:='';
end;

function TWebserverSite.GetCustomHandler(url: UnicodeString): TEpollWorkerThread;
begin
  result:=TEpollWorkerThread(FCustomHandlers[url]);
end;

function TWebserverSite.GetIndexPage(var target: UnicodeString): UnicodeString;
var
  i: Integer;
  s: ansiString;
begin
  for i:=Length(FIndexNames)-1 downto 0 do
  begin
    if not URLPathToAbsolutePath(target, FPath + 'web', s) then
      continue;
    result:=s + FIndexNames[i];
    if FileExists(result) then
      Exit;
  end;
  result:='';
end;

{ TWebserverSiteManager }

procedure TWebserverSiteManager.HostNameDeleteIterator(Item: TObject;
  const Key: AnsiString; var Continue: Boolean);
begin
  if Item = FHostToDelete then
  begin
    Continue:=False;
    FHostToDelete:=nil;
    FHostsByName.Delete(key);
  end else
    Continue:=True;
end;

constructor TWebserverSiteManager.Create(const BasePath: UnicodeString);
begin
  FPath:=BasePath+'sites/';
  FSharedScriptsDir:=BasePath+'shared/scripts/';
  FDefaultHost:=nil; //TWebserverSite.Create(Self, 'default');
  FHostsByName:=TFPObjectHashTable.Create(false);
end;

destructor TWebserverSiteManager.Destroy;
var
  i: Integer;
begin
  for i:=0 to Length(FHosts)-1 do
  begin
    FHosts[i].Free;
  end;
  Setlength(FHosts, 0);
  FHostsByName.Free;
  inherited Destroy;
end;

function TWebserverSiteManager.UnloadSite(Path: UnicodeString): Boolean;
var
  i: Integer;
begin
  result:=False;
  for i:=0 to Length(FHosts)-1 do
  if FHosts[i].FName = Path then
  begin
    if FDefaultHost = FHosts[i] then
      FDefaultHost:=nil;

    repeat
      FHostToDelete:=FHosts[i];
      FHostsByName.Iterate(@HostNameDeleteIterator);
    until Assigned(FHostToDelete);
    FHostToDelete:=nil;

    FHosts[i].Free;
    FHosts[i]:=FHosts[Length(FHosts)-1];
    Setlength(FHosts, Length(FHosts)-1);
    Exit;
  end;
end;

function TWebserverSiteManager.AddSite(Path: UnicodeString): TWebserverSite;
var
  i: Integer;
begin
  for i:=0 to Length(FHosts)-1 do
  if FHosts[i].FPath = Path then
  begin
    result:=FHosts[i];
    Exit;
  end;
  result:=TWebserverSite.Create(Self, Path);
  i:=Length(FHosts);
  Setlength(FHosts, i+1);
  FHosts[i]:=result;
  dolog(llNotice, 'Loaded site "'+Path+'"');
  // result.AddHostAlias(Hostname);
end;

function TWebserverSiteManager.GetSite(Hostname: UnicodeString): TWebserverSite;
begin
  result:=TWebserverSite(FHostsByName[Hostname]);
  if not Assigned(result) then
    result:=FDefaultHost;
end;

end.

