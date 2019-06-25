unit webserverhosts;

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
    FName, FPath: string;
    FParent: TWebserverSiteManager;
    FCustomHandlers: TFPObjectHashTable;
    FScriptDirs: array of record
      Dir: string;
      Script: string;
    end;
    FResponseHeaders: array of record
      Name: string;
      Value: string;
    end;
    FIndexNames: array of string;
    FWhitelistedProcesses: array of string;
    FForwards: TFPStringHashTable;
    FCustomStatusPages: array[CustomStatusPageMin..CustomStatusPageMax] of string;
    procedure ClearItem(Item: TObject; const Key: ansistring; var Continue: Boolean);
  public
    constructor Create(Parent: TWebserverSiteManager; Path: string);
    destructor Destroy; override;
    procedure log(Level: TLoglevel; Msg: string);
    procedure AddScriptDirectory(directory, filename: string);
    procedure AddForward(target, NewTarget: string);
    procedure AddIndexPage(name: string);
    function IsScriptDir(target: string; out Script, Params: string): Boolean;
    function IsForward(target: string; out NewTarget: string): Boolean;
    procedure AddResponseHeader(const name, value: string);
    procedure AddHostAlias(HostName: string);
    procedure AddCustomHandler(url: string; Handler: TEpollWorkerThread);
    procedure AddCustomStatusPage(StatusCode: Word; URI: string);
    procedure ApplyResponseHeader(const Response: THTTPReply);
    procedure AddWhiteListProcess(const Executable: string);
    function IsProcessWhitelisted(const Executable: string): Boolean;
    function GetCustomStatusPage(StatusCode: Word): string;
    function GetCustomHandler(url: string): TEpollWorkerThread;
    function GetIndexPage(var target: string): string;
    property Path: string read FPath;
    property Name: string read FName;
    property Parent: TWebserverSiteManager read FParent;
  end;

  { TWebserverSiteManager }

  TWebserverSiteManager = class
  private
    FDefaultHost: TWebserverSite;
    FHosts: array of TWebserverSite;
    FHostsByName: TFPObjectHashTable;
    FPath: string;
    FSharedScriptsDir: string;
    FHostToDelete: TWebserverSite;
    Procedure HostNameDeleteIterator(Item: TObject; const Key: ansistring; var Continue: Boolean);
  public
    constructor Create(const BasePath: string);
    destructor Destroy; override;
    function UnloadSite(Path: string): Boolean;
    function AddSite(Path: string): TWebserverSite;
    function GetSite(Hostname: string): TWebserverSite;
    property Path: string read FPath;
    property DefaultHost: TWebserverSite read FDefaultHost write FDefaultHost;
  end;


function IntToFilesize(Size: longword): string;

implementation

uses
  webserver,
  chakraserverconfig;

function FileToStr(const aFilename: string): string;
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

procedure WriteFile(const aFilename, aContent: string);
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

procedure TWebserverSite.ClearItem(Item: TObject; const Key: ansistring;
  var Continue: Boolean);
begin
  Item.free;
end;

constructor TWebserverSite.Create(Parent: TWebserverSiteManager;
  Path: string);
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

procedure TWebserverSite.log(Level: TLoglevel; Msg: string);
begin
  dolog(Level, '['+FName+'] '+Msg);
end;

function IntToFilesize(Size: longword): string;

function Foo(A: longword): string;
var
  b: longword;
begin
  result:=string(IntToStr(Size div A));

  if a=1 then
    Exit;

  b:=(Size mod a)div (a div 1024);
  b:=(b*100) div 1024;

  if b<10 then
    result:=result+'.0'+string(IntToStr(b))
  else
    result:=result+'.'+string(IntToStr(b));
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

procedure TWebserverSite.AddScriptDirectory(directory, filename: string);
var
  i: Integer;
begin
  i:=Length(FScriptDirs);
  Setlength(FScriptDirs, i+1);
  FScriptDirs[i].script:=filename;
  FScriptDirs[i].dir:=directory;
end;

procedure TWebserverSite.AddForward(target, NewTarget: string);
begin
  FForwards[ansistring(target)]:=ansistring(NewTarget);
end;

procedure TWebserverSite.AddIndexPage(name: string);
var
  i: Integer;
begin
  i:=Length(FIndexNames);
  Setlength(FIndexNames, i+1);
  FIndexNames[i]:=name;
end;

function TWebserverSite.IsScriptDir(target: string; out Script, Params: string
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

function TWebserverSite.IsForward(target: string; out NewTarget: string
  ): Boolean;
begin
  NewTarget:=string(FForwards[ansistring(target)]);
  result:=NewTarget<>'';
end;

procedure TWebserverSite.AddResponseHeader(const name, value: string);
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

procedure TWebserverSite.AddHostAlias(HostName: string);
begin
  FParent.FHostsByName.Add(ansistring(HostName), Self);
end;

procedure TWebserverSite.AddCustomHandler(url: string;
  Handler: TEpollWorkerThread);
begin
  FCustomHandlers.Add(ansistring(url), Handler);
end;

procedure TWebserverSite.AddCustomStatusPage(StatusCode: Word; URI: string);
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

procedure TWebserverSite.AddWhiteListProcess(const Executable: string);
var
  i: Integer;
begin
  i:=Length(FWhitelistedProcesses);
  SetLength(FWhitelistedProcesses, i+1);
  FWhitelistedProcesses[i]:=Executable;
end;

function TWebserverSite.IsProcessWhitelisted(const Executable: string
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

function TWebserverSite.GetCustomStatusPage(StatusCode: Word): string;
begin
  if (StatusCode>=CustomStatusPageMin)and
     (StatusCode<=CustomStatusPageMax) then
    result:=FCustomStatusPages[StatusCode]
  else
    result:='';
end;

function TWebserverSite.GetCustomHandler(url: string): TEpollWorkerThread;
begin
  result:=TEpollWorkerThread(FCustomHandlers[ansistring(url)]);
end;

function TWebserverSite.GetIndexPage(var target: string): string;
var
  i: Integer;
begin
  for i:=Length(FIndexNames)-1 downto 0 do
  begin
    if not URLPathToAbsolutePath(target, FPath + 'web', result) then
      continue;
    if FileExists(result) then
    begin
      result:=result + FIndexNames[i];
      Exit;
    end;
  end;
end;

{ TWebserverSiteManager }

procedure TWebserverSiteManager.HostNameDeleteIterator(Item: TObject;
  const Key: ansistring; var Continue: Boolean);
begin
  if Item = FHostToDelete then
  begin
    Continue:=False;
    FHostToDelete:=nil;
    FHostsByName.Delete(ansistring(key));
  end else
    Continue:=True;
end;

constructor TWebserverSiteManager.Create(const BasePath: string);
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

function TWebserverSiteManager.UnloadSite(Path: string): Boolean;
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

function TWebserverSiteManager.AddSite(Path: string): TWebserverSite;
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

function TWebserverSiteManager.GetSite(Hostname: string): TWebserverSite;
begin
  result:=TWebserverSite(FHostsByName[ansistring(Hostname)]);
  if not Assigned(result) then
    result:=FDefaultHost;
end;

end.

