unit chakraserverconfig;
{
 chakra classes for server configuration & global server manager class

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
    SysUtils,
    Classes,
    SyncObjs,
    //{$i besenunits.inc},
    webserverhosts,
    chakraevents,
    chakrainstance,
    ChakraCore,
    ChakraCommon,
    ChakraCoreUtils,
    ChakraRTTIObject,
    webserver;

type
  { TChakraWebserverSite }

  TChakraWebserverSite = class(TNativeRTTIObject)
  private
    FServer: TWebserver;
    FSite: TWebserverSite;
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
    function unload(Arguments: PJsValueRefArray; CountArguments: word): JsValueRef;
  end;

  { TChakraWebserverListener }

  TChakraWebserverListener= class(TNativeRTTIObject)
  private
    FServer: TWebserver;
    FListener: TWebserverListener;
    function GetIP: UnicodeString;
    function GetPort: UnicodeString;
  published
    { remove() - removes this listener }
    function remove(Arguments: PJsValueRefArray; CountArguments: word): JsValueRef;

    function enableSSL(Arguments: PJsValueRefArray; CountArguments: word): JsValueRef;

    function setCiphers(Arguments: PJsValueRefArray; CountArguments: word): JsValueRef;

    property ip: UnicodeString read GetIP;
    property port: UnicodeString read GetPort;
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
    FPath: ansistring;
  public
    constructor Create(const BasePath: ansistring; TestMode: Boolean = false);
    destructor Destroy; override;
    function Execute(Filename: string): Boolean;
    procedure Process;
    property Server: TWebserver read FServer;
    property Path: ansistring read FPath;
  end;

var
  ServerManager: TWebserverManager;

function StripBasePath(filename: ansistring): ansistring;

implementation

uses
  mimehelper,
  chakrawebsocket,
  chakraprocess,
  logging;

function StripBasePath(filename: ansistring): ansistring;
begin
  if not Assigned(ServerManager) then
    result:=filename
  else if Pos(lowercase(Servermanager.Path), lowercase(filename))=1 then
    result:=Copy(filename, Length(ServerManager.Path), Length(filename))
  else
    result:=filename;
end;

{ TChakraWebserverListener }

function TChakraWebserverListener.GetIP: UnicodeString;
begin
  if Assigned(FListener) then
    result:=FListener.IP
  else
    result:='';
end;

function TChakraWebserverListener.GetPort: UnicodeString;
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

function TChakraWebserverListener.enableSSL(Arguments: PJsValueRefArray;
  CountArguments: word): JsValueRef;
begin
  Result:=JsUndefinedValue;
  if CountArguments<3 then
   Exit;
  if Assigned(FListener) then
    if not FListener.SSL then

    FListener.EnableSSL(JsStringToUnicodeString(JsValueAsJsString(Arguments^[0])), JsStringToUnicodeString(JsValueAsJsString(Arguments^[1])), JsStringToUnicodeString(JsValueAsJsString(Arguments^[2])));
end;

function TChakraWebserverListener.setCiphers(Arguments: PJsValueRefArray;
  CountArguments: word): JsValueRef;
begin
  Result:=JsUndefinedValue;
  if CountArguments<1 then
   Exit;
  if Assigned(FListener) and(FListener.SSL) then
    FListener.SetSSLCiphers(JsStringToUnicodeString(JsValueAsJsString(Arguments^[0])));
end;

{ TChakraWebserverSite }

function TChakraWebserverSite.addIndexPage(Arguments: PJsValueRefArray;
  CountArguments: word): JsValueRef;
begin
  result:=JsUndefinedValue;
  if (CountArguments <1) or (not Assigned(FSite)) then
    Exit;
  FSite.AddIndexPage(ansistring(JsStringToUnicodeString(JsValueAsJsString(Arguments^[0]))));
end;

function TChakraWebserverSite.addHostname(Arguments: PJsValueRefArray;
  CountArguments: word): JsValueRef;
begin
  result:=JsUndefinedValue;
  if CountArguments<1 then
    Exit;

  if not Assigned(FSite) then
    Exit;

  FSite.AddHostAlias(ansistring(JsStringToUnicodeString(JsValueAsJsString(Arguments^[0]))));
end;

function TChakraWebserverSite.addForward(Arguments: PJsValueRefArray;
  CountArguments: word): JsValueRef;
begin
  result:=JsUndefinedValue;
  if CountArguments<2 then
    Exit;

  if not Assigned(FSite) then
    Exit;

  FSite.AddForward(ansistring(JsStringToUnicodeString(JsValueAsJsString(Arguments^[0]))), ansistring(JsStringToUnicodeString(JsValueAsJsString(Arguments^[1]))));
end;

function TChakraWebserverSite.addScriptAlias(Arguments: PJsValueRefArray;
  CountArguments: word): JsValueRef;
begin
  result:=JsUndefinedValue;

  if CountArguments<2 then
    Exit;

  if not Assigned(FSite) then
    Exit;

  FSite.AddScriptDirectory(ansistring(JsStringToUnicodeString(JsValueAsJsString(Arguments^[0]))), ansistring(JsStringToUnicodeString(JsValueAsJsString(Arguments^[1]))));
end;

function TChakraWebserverSite.addStatusPage(Arguments: PJsValueRefArray;
  CountArguments: word): JsValueRef;
begin
  if not Assigned(FSite) then
    Exit;

  if CountArguments<2 then Exit;

  FSite.AddCustomStatusPage(Round(JsNumberToDouble(Arguments^[0])), ansistring(JsStringToUnicodeString(JsValueAsJsString(Arguments^[1]))));
end;

function TChakraWebserverSite.addResponseHeader(Arguments: PJsValueRefArray;
  CountArguments: word): JsValueRef;
begin
  result:=JsUndefinedValue;
  if CountArguments<2 then
    Exit;

  FSite.AddResponseHeader(ansistring(JsStringToUnicodeString(JsValueAsJsString(Arguments^[0]))), ansistring(JsStringToUnicodeString(JsValueAsJsString(Arguments^[1]))));
end;

function TChakraWebserverSite.addWebsocket(Arguments: PJsValueRefArray;
  CountArguments: word): JsValueRef;
var
  url: UnicodeString;
begin
  result:=JsUndefinedValue;
  if not Assigned(FSite) then
    Exit;

  if CountArguments<2 then
    Exit;

  url:=JsStringToUnicodeString(JsValueAsJsString(Arguments^[0]));
  FSite.AddCustomHandler(ansistring(url), TChakraWebsocket.Create(FServer, FSite, ansistring(JsStringToUnicodeString(JsValueAsJsString(Arguments^[1]))), url));
end;

function TChakraWebserverSite.addWhitelistExecutable(
  Arguments: PJsValueRefArray; CountArguments: word): JsValueRef;
var
  s: ansistring;
begin
  result:=JsUndefinedValue;
  if (CountArguments<1) or not Assigned(FSite) then
    Exit;

  s:=ansistring(JsStringToUnicodeString(JsValueAsJsString(Arguments^[0])));
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

  if SysUtils.FileExists(FSite.Path + ansistring(JsStringToUnicodeString(JsValueAsJsString(Arguments^[0])))) then
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

  Result:=StringToJsString(LoadFile(FSite.Path + ansistring(JsStringToUnicodeString(JsValueAsJsString(Arguments^[0])))));
  //Result:=BESENStringValue(BESENUTF8ToUTF16(BESENGetFileContent(FSite.Path + ansistring(JsStringToUnicodeString(JsValueAsJsString(Arguments^[0]^)))));
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

  Listener:=FServer.AddListener(ansistring(JsStringToUnicodeString(JsValueAsJsString(Arguments^[0]))), ansistring(JsStringToUnicodeString(JsValueAsJsString(Arguments^[1]))));

  ListenerObj:=TChakraWebserverListener.Create();
  ListenerObj.FListener:=Listener;
  ListenerObj.FServer:=FServer;

  Result:=ListenerObj.Instance;

  if CountArguments<5 then
    Exit;
  if Assigned(Listener) then
    Listener.EnableSSL(ansistring(JsStringToUnicodeString(JsValueAsJsString(Arguments^[2]))), ansistring(JsStringToUnicodeString(JsValueAsJsString(Arguments^[3]))), ansistring(JsStringToUnicodeString(JsValueAsJsString(Arguments^[4]))));
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

  Site:=FServer.SiteManager.AddSite(ansistring(JsStringToUnicodeString(JsValueAsJsString(Arguments^[0]))));

  if Assigned(Site) then
  begin
    Host:=TChakraWebserverSite.Create();
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

  OverwriteMimeType(ansistring(JsStringToUnicodeString(JsValueAsJsString(Arguments^[0]))), ansistring(JsStringToUnicodeString(JsValueAsJsString(Arguments^[1]))));
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

constructor TWebserverManager.Create(const BasePath: ansistring;
  TestMode: Boolean);
begin
  ServerManager:=Self;
  FServer:=TWebserver.Create(BasePath, TestMode);
  FInstance:=TChakraInstance.Create(FServer.SiteManager, nil);
  FPath:=FServer.SiteManager.Path;
  FServerObject:=TChakraWebserverObject.Create();
  FServerObject.FServer:=FServer;
  //FServerObject.InitializeObject;
  //FInstance.AddEventHandler(FServer.SiteManager.ProcessTick);
  //FInstance.GarbageCollector.Add(TBESENObject(FServerObject));
  //FInstance.GarbageCollector.Protect(TBESENObject(FServerObject));
end;

destructor TWebserverManager.Destroy;
begin
  FInstance.Destroy;
  FServer.Destroy;
  inherited Destroy;
end;

function TWebserverManager.Execute(Filename: string): Boolean;
var
  lastfile: Integer;
begin
  result:=False;
  //lastfile:=FInstance.CurrentFile;
  //FInstance.SetFilename(ExtractFileName(Filename));
  //FInstance.ObjectGlobal.put('server', BESENObjectValue(FServerObject), false);
  JsSetProperty(FInstance.Context.Global, 'server', FServerObject.Instance);
  try
    FInstance.ExecuteFile(Filename);
    result:=True;
  except
    on e: Exception do
      FInstance.OutputException(e, 'startup');
  end;
  //FInstance.CurrentFile:=lastfile;
end;

procedure TWebserverManager.Process;
begin
  FServer.Ticks:=longword(GetTickCount64);
  Finstance.ProcessHandlers;
end;

end.

