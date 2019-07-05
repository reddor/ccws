unit chakraserverconfig;

{$i ccwssettings.inc}

interface

uses
    SysUtils,
    Classes,
    //{$i besenunits.inc},
    webserverhosts,
    chakraevents,
    chakrainstance,
    ChakraCore,
    ChakraCommon,
    ChakraCoreUtils,
    ChakraRTTIObject,
    chakrawebsocket,
    webserver;

type

  { TChakraWebsocketScript }

  TChakraWebsocketScript = class(TNativeRTTIObject)
  private
    FWSInstance: TChakraWebsocket;
  public
    constructor Create(WebsocketInstance: TChakraWebsocket);
  published
    function setEnvVar(Arguments: PJsValueRefArray; CountArguments: word): JsValueRef;
    function getEnvVar(Arguments: PJsValueRefArray; CountArguments: word): JsValueRef;
    function unload(Arguments: PJsValueRefArray; CountArguments: word): JsValueRef;
  end;

  { TChakraWebserverSite }

  TChakraWebserverSite = class(TNativeRTTIObject)
  private
    FServer: TWebserver;
    FSite: TWebserverSite;
    function GetSiteName: string;
  published
    function addIndexPage(Arguments: PJsValueRefArray; CountArguments: word): JsValueRef;
    { addHostname(host) - binds a host to this site. requests made to this host will be processed by this site }
    function addHostname(Arguments: PJsValueRefArray; CountArguments: word): JsValueRef;
    { addForward(url, newUrl) - redirects requests from "url" to newUrl" using a 301 status code

      Example: site.addForward("/index.html", "/index.jsp") }
    function addForward(Arguments: PJsValueRefArray; CountArguments: word): JsValueRef;
    { addScriptAlias(urlAlias, urlTarget) - points all requests STARTING WITH "urlAlias" to "targetAlias".
      the remainder of the request url will be put in the client http-parameter property

      Example: site.addScriptAlias("/foo/", "/script.jsp");
        the request "/foo/" will become "/script.jsp"
        the request "/foo/bar" will become "/script.jsp?bar"
        the request "/foo/bar?hello" will become "/script.jsp?bar?hello"
     }
    function addScriptAlias(Arguments: PJsValueRefArray; CountArguments: word): JsValueRef;
    { addStatusPage(statusCode, target) - replaces a http status page (404 etc) with a custom page. can be static html or script }
    function addStatusPage(Arguments: PJsValueRefArray; CountArguments: word): JsValueRef;
    { addResponseHeader(name, value) - adds a default response header entry }
    function addResponseHeader(Arguments: PJsValueRefArray; CountArguments: word): JsValueRef;
    { addWebsocket(url, script) - creates a new script instance & thread with "script" loaded.
         "script" must point to a filename in the site root directory }
    function addWebsocket(Arguments: PJsValueRefArray; CountArguments: word): JsValueRef;
    { addWhitelistExecutable(filename) - adds an executable that may be executed in the site context }
    function addWhitelistExecutable(Arguments: PJsValueRefArray; CountArguments: word): JsValueRef;
    { fileExists(filename) - check if file exists. root is site's web folder }
    function fileExists(Arguments: PJsValueRefArray; CountArguments: word): JsValueRef;
    { readFile(filename) - returns the content of filename. directory root for this function is the site web folder }
    function readFile(Arguments: PJsValueRefArray; CountArguments: word): JsValueRef;
    { unload() - unloads the site. the ecmascript site object will remain in memory until the garbage collector frees it }
    function unload({%H-}Arguments: PJsValueRefArray; {%H-}CountArguments: word): JsValueRef;
    property SiteName: string read GetSiteName;
  end;

  { TChakraWebserverListener }

  TChakraWebserverListener= class(TNativeRTTIObject)
  private
    FServer: TWebserver;
    FListener: TWebserverListener;
    function GetIP: string;
    function GetPort: string;
  published
    { remove() - removes this listener }
    function remove(Arguments: PJsValueRefArray; CountArguments: word): JsValueRef;
    property ip: string read GetIP;
    property port: string read GetPort;
  end;

  { TChakraWebserverObject }

  TChakraWebserverObject = class(TNativeRTTIObject)
  private
    FServer: TWebserver;
  protected
    // procedure InitializeObject; override;
  published
    { addListener(ip, port) - adds a listening socket to ip:port. }
    function addListener(Arguments: PJsValueRefArray; CountArguments: word): JsValueRef;
    { removeListener(listener) - removes a listener }
    function removeListener(Arguments: PJsValueRefArray; CountArguments: word): JsValueRef;
    { addSite(siteName) - returns a site-object. siteName must be equal to the site directory name }
    function addSite(Arguments: PJsValueRefArray; CountArguments: word): JsValueRef;
    { setThreadCount(threadCount) - sets the number of worker threads to threadCount. number of cpu cores recommended }
    function setThreadCount(Arguments: PJsValueRefArray; CountArguments: word): JsValueRef;
    { setMimeType(fileExtension, mimeType) - overwrites the mimetype for a specific file type }
    function setMimeType(Arguments: PJsValueRefArray; CountArguments: word): JsValueRef;
    { setDefaultSite(siteObject) - sets the default site for unknown hosts }
    function setDefaultSite(Arguments: PJsValueRefArray; CountArguments: word): JsValueRef;
  end;

  { TWebserverManager }

  TWebserverManager = class
  private
    FServer: TWebserver;
    FInstance: TChakraInstance;
    FServerObject: TChakraWebserverObject;
    FPath: string;
  public
    constructor Create(const BasePath: string; TestMode: Boolean = false);
    destructor Destroy; override;
    function Execute(Filename: string): Boolean;
    procedure Process;
    property Server: TWebserver read FServer;
    property Path: string read FPath;
  end;

var
  ServerManager: TWebserverManager;

function StripBasePath(filename: string): string;

implementation

uses
  mimehelper,
  chakraprocess,
  logging;

function StripBasePath(filename: string): string;
begin
  if not Assigned(ServerManager) then
    result:=filename
  else if Pos(lowercase(Servermanager.Path), lowercase(filename))=1 then
    result:=Copy(filename, Length(ServerManager.Path), Length(filename))
  else
    result:=filename;
end;

{ TChakraWebsocketScript }

constructor TChakraWebsocketScript.Create(WebsocketInstance: TChakraWebsocket);
begin
  inherited Create(nil, 0, True);
  FWSInstance:=WebsocketInstance;
end;

function TChakraWebsocketScript.setEnvVar(Arguments: PJsValueRefArray;
  CountArguments: word): JsValueRef;
begin
  result:=JsUndefinedValue;
  if CountArguments < 2 then
    raise Exception.Create('Not enough parameters');
  if Assigned(FWSInstance) then
    FWSInstance.SetEnvVar(
      JsStringToUTF8String(JsValueAsJsString(Arguments^[0])),
      JsStringToUTF8String(JsValueAsJsString(Arguments^[1])));
end;

function TChakraWebsocketScript.getEnvVar(Arguments: PJsValueRefArray;
  CountArguments: word): JsValueRef;
begin
  result:=JsUndefinedValue;
  if CountArguments < 2 then
    raise Exception.Create('Not enough parameters');
  if Assigned(FWSInstance) then
    result:=StringToJsString(FWSInstance.GetEnvVar(JsStringToUTF8String(JsValueAsJsString(Arguments^[0]))))
  else
    result:=StringToJsString('');
end;

function TChakraWebsocketScript.unload(Arguments: PJsValueRefArray;
  CountArguments: word): JsValueRef;
begin
  result:=JsUndefinedValue;
  if Assigned(FWSInstance) then
  begin
    dolog(llNotice, 'Unloading ' + FWSInstance.url);
    FWSInstance.Site.RemoveCustomHandler(FWSInstance.url);
    FreeAndNil(FWSInstance);
  end;
end;

{ TChakraWebserverListener }

function TChakraWebserverListener.GetIP: string;
begin
  if Assigned(FListener) then
    result:=FListener.IP
  else
    result:='';
end;

function TChakraWebserverListener.GetPort: string;
begin
  if Assigned(FListener) then
    result:=FListener.Port
  else
    result:='';
end;

function TChakraWebserverListener.remove(Arguments: PJsValueRefArray;
  CountArguments: word): JsValueRef;
begin
  Result:=JsFalseValue;
  if Assigned(FListener) then
  begin
    if FServer.RemoveListener(FListener) then
    begin
      FListener:=nil;
      FServer:=nil;
      Result:=JsTrueValue;
    end;
  end;
end;

{ TChakraWebserverSite }

function TChakraWebserverSite.GetSiteName: string;
begin
  result:=FSite.Name;
end;

function TChakraWebserverSite.addIndexPage(Arguments: PJsValueRefArray;
  CountArguments: word): JsValueRef;
begin
  result:=JsUndefinedValue;
  if (CountArguments <1) or (not Assigned(FSite)) then
    Exit;
  FSite.AddIndexPage(string(JsStringToUnicodeString(JsValueAsJsString(Arguments^[0]))));
end;

function TChakraWebserverSite.addHostname(Arguments: PJsValueRefArray;
  CountArguments: word): JsValueRef;
begin
  result:=JsUndefinedValue;
  if CountArguments<1 then
    Exit;

  if not Assigned(FSite) then
    Exit;

  FSite.AddHostAlias(string(JsStringToUnicodeString(JsValueAsJsString(Arguments^[0]))));
end;

function TChakraWebserverSite.addForward(Arguments: PJsValueRefArray;
  CountArguments: word): JsValueRef;
begin
  result:=JsUndefinedValue;
  if CountArguments<2 then
    Exit;

  if not Assigned(FSite) then
    Exit;

  FSite.AddForward(string(JsStringToUnicodeString(JsValueAsJsString(Arguments^[0]))), string(JsStringToUnicodeString(JsValueAsJsString(Arguments^[1]))));
end;

function TChakraWebserverSite.addScriptAlias(Arguments: PJsValueRefArray;
  CountArguments: word): JsValueRef;
begin
  result:=JsUndefinedValue;

  if CountArguments<2 then
    Exit;

  if not Assigned(FSite) then
    Exit;

  FSite.AddScriptDirectory(string(JsStringToUnicodeString(JsValueAsJsString(Arguments^[0]))), string(JsStringToUnicodeString(JsValueAsJsString(Arguments^[1]))));
end;

function TChakraWebserverSite.addStatusPage(Arguments: PJsValueRefArray;
  CountArguments: word): JsValueRef;
begin
  result:=jsUndefinedValue;
  if not Assigned(FSite) then
    Exit;

  if CountArguments<2 then Exit;

  FSite.AddCustomStatusPage(Round(JsNumberToDouble(Arguments^[0])), string(JsStringToUnicodeString(JsValueAsJsString(Arguments^[1]))));
end;

function TChakraWebserverSite.addResponseHeader(Arguments: PJsValueRefArray;
  CountArguments: word): JsValueRef;
begin
  result:=JsUndefinedValue;
  if CountArguments<2 then
    Exit;

  FSite.AddResponseHeader(string(JsStringToUnicodeString(JsValueAsJsString(Arguments^[0]))), string(JsStringToUnicodeString(JsValueAsJsString(Arguments^[1]))));
end;

function TChakraWebserverSite.addWebsocket(Arguments: PJsValueRefArray;
  CountArguments: word): JsValueRef;
var
  url: string;
  ws: TChakraWebsocket;
begin
  result:=JsUndefinedValue;
  if not Assigned(FSite) then
    Exit;

  if CountArguments<2 then
    Exit;

  url:=string(JsStringToUnicodeString(JsValueAsJsString(Arguments^[0])));

  ws:=TChakraWebsocket.Create(FServer, FSite, string(JsStringToUnicodeString(JsValueAsJsString(Arguments^[1]))), url);
  result:=TChakraWebsocketScript.Create(ws).Instance;
  FSite.AddCustomHandler(url, ws);
end;

function TChakraWebserverSite.addWhitelistExecutable(
  Arguments: PJsValueRefArray; CountArguments: word): JsValueRef;
var
  s: string;
begin
  result:=JsUndefinedValue;
  if (CountArguments<1) or not Assigned(FSite) then
    Exit;

  s:=string(JsStringToUnicodeString(JsValueAsJsString(Arguments^[0])));
  if Pos('/', s)<>1 then
    s:=FSite.Path+'bin/'+s;

  FSite.AddWhiteListProcess(s);
end;

function TChakraWebserverSite.fileExists(Arguments: PJsValueRefArray;
  CountArguments: word): JsValueRef;
begin
  Result:=JsFalseValue;

  if not Assigned(FSite) then
    Exit;

  if CountArguments<1 then
    Exit;

  if SysUtils.FileExists(FSite.Path + string(JsStringToUnicodeString(JsValueAsJsString(Arguments^[0])))) then
    Result:=JsTrueValue;
end;

function TChakraWebserverSite.readFile(Arguments: PJsValueRefArray;
  CountArguments: word): JsValueRef;
begin
  Result:=JsUndefinedValue;

  if not Assigned(FSite) then
    Exit;

  if CountArguments<1 then
    Exit;

  Result:=StringToJsString(LoadFile(FSite.Path + string(JsStringToUnicodeString(JsValueAsJsString(Arguments^[0])))));
  //Result:=BESENStringValue(BESENUTF8ToUTF16(BESENGetFileContent(FSite.Path + string(JsStringToUnicodeString(JsValueAsJsString(Arguments^[0]^)))));
end;

function TChakraWebserverSite.unload(Arguments: PJsValueRefArray;
  CountArguments: word): JsValueRef;
begin
  Result:=JsUndefinedValue;

  if not Assigned(FSite) then
    Exit;

  if FServer.SiteManager.UnloadSite(FSite.Name) then
    FSite:=nil;
end;

{ TChakraWebserverObject }

function TChakraWebserverObject.addListener(Arguments: PJsValueRefArray;
  CountArguments: word): JsValueRef;
var
  Listener: TWebserverListener;
  ListenerObj: TChakraWebserverListener;
begin
  Result:=JsUndefinedValue;

  if CountArguments<2 then
    Exit;

  Listener:=FServer.AddListener(string(JsStringToUnicodeString(JsValueAsJsString(Arguments^[0]))), string(JsStringToUnicodeString(JsValueAsJsString(Arguments^[1]))));

  ListenerObj:=TChakraWebserverListener.Create(nil, 0, True);
  ListenerObj.FListener:=Listener;
  ListenerObj.FServer:=FServer;

  Result:=ListenerObj.Instance;
end;

function TChakraWebserverObject.removeListener(Arguments: PJsValueRefArray;
  CountArguments: word): JsValueRef;
var
  obj: TObject;
begin
  Result:=JsFalseValue;
  if CountArguments<1 then
    Exit;

  obj:=TObject(JsGetExternalData(Arguments^[0]));

  if Assigned(obj) and(obj is TChakraWebserverListener) then
  begin
    if FServer.RemoveListener(TChakraWebserverListener(obj).FListener) then
    begin
      Result:=JsTrueValue;
      TChakraWebserverListener(obj).FListener:=nil;
    end;
  end;
end;

function TChakraWebserverObject.addSite(Arguments: PJsValueRefArray;
  CountArguments: word): JsValueRef;
var
  Site: TWebserverSite;
  Host: TChakraWebserverSite;
begin
  Result:=JsUndefinedValue;

  if CountArguments<1 then
    Exit;

  Site:=FServer.SiteManager.AddSite(string(JsStringToUnicodeString(JsValueAsJsString(Arguments^[0]))));

  if Assigned(Site) then
  begin
    Host:=TChakraWebserverSite.Create(nil, 0, true);
    Host.FSite:=Site;
    Host.FServer:=FServer;
    Result:=Host.Instance;
  end;
end;

function TChakraWebserverObject.setThreadCount(Arguments: PJsValueRefArray;
  CountArguments: word): JsValueRef;
begin
  Result:=JsUndefinedValue;

  if CountArguments<1 then
    Exit;

  if not Assigned(FServer) then
    Exit;

  FServer.SetThreadCount(Round(JsNumberToDouble(Arguments^[0])));
end;

function TChakraWebserverObject.setMimeType(Arguments: PJsValueRefArray;
  CountArguments: word): JsValueRef;
begin
  Result:=JsUndefinedValue;
  if CountArguments<2 then Exit;

  OverwriteMimeType(string(JsStringToUnicodeString(JsValueAsJsString(Arguments^[0]))), string(JsStringToUnicodeString(JsValueAsJsString(Arguments^[1]))));
end;

function TChakraWebserverObject.setDefaultSite(Arguments: PJsValueRefArray;
  CountArguments: word): JsValueRef;
var
  o: TObject;
begin
  Result:=JsUndefinedValue;
  if CountArguments<1 then
    Exit;

  o:=TObject(JsGetExternalData(Arguments^[0]));

  if not Assigned(o) then
    Exit;

  if not (o is TChakraWebserverSite) then
    Exit;

  if not Assigned(TChakraWebserverSite(o).FSite) then
    Exit;

  FServer.SiteManager.DefaultHost:=TChakraWebserverSite(o).FSite;
end;

{ TWebserverManager }

constructor TWebserverManager.Create(const BasePath: string;
  TestMode: Boolean);
begin
  ServerManager:=Self;
  FServer:=TWebserver.Create(BasePath, TestMode);
  FInstance:=TChakraInstance.Create(FServer.SiteManager, nil, nil);
  FPath:=FServer.SiteManager.Path;
  FServerObject:=TChakraWebserverObject.Create(nil, 0, True);
  FServerObject.FServer:=FServer;
end;

destructor TWebserverManager.Destroy;
begin
  FServer.Destroy;
  FInstance.Destroy;
  inherited Destroy;
end;

function TWebserverManager.Execute(Filename: string): Boolean;
begin
  result:=False;
  JsSetProperty(FInstance.Context.Global, 'server', FServerObject.Instance);
  try
    FInstance.ExecuteFile(Filename);
    result:=True;
  except
    on e: Exception do
      FInstance.OutputException(e, 'startup');
  end;
end;

procedure TWebserverManager.Process;
begin
  FServer.Ticks:=longword(GetTickCount64);
  Finstance.ProcessHandlers;
end;

end.

