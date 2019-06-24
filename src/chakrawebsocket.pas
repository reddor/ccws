unit chakrawebsocket;
{
 asynchronous besen classes for websockets (and regular http requests)

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
  contnrs,
  ChakraCommon,
  ChakraCore,
  ChakraCoreUtils,
  ChakraRTTIObject,
  chakrainstance,
  chakraevents,
  epollsockets,
  webserverhosts,
  webserver;

type
  //TOpenSSLBesenWorkAroundThread = class(TThread)
  { TChakraWebsocketClient }

  { client object - this is created automatically for each new connection and
    passed to the script via global handler object callbacks.

    for regular http clients, .disconnect() must be called after the request
    has been processed. Otherwise the client will never receive a response
  }
  TChakraWebsocketClient = class(TNativeRTTIObject)
  private
    FIsRequest: Boolean;
    FMimeType: UnicodeString;
    FReply: UnicodeString;
    FConnection: THTTPConnection;
    FReturnType: UnicodeString;
    FRefCounter: Integer;
    function GetHostname: UnicodeString;
    function GetLag: Integer;
    function GetParameter: UnicodeString;
    function GetPingTime: Integer;
    function GetPongTime: Integer;
    function GetPostData: UnicodeString;
    procedure SetPingTime(AValue: Integer);
    procedure SetPongTime(AValue: Integer);
  public
    constructor Create(Args: PJsValueRef = nil; ArgCount: Word = 0; AFinalize: Boolean = False); override;
    procedure AddRefCount;
    procedure DecRefCount;
  published
    { send(data) - sends data to client }
    function send(Arguments: PJsValueRefArray; CountArguments: word): JsValueRef;
    { disconnect() - disconnects the client }
    function disconnect(Arguments: PJsValueRefArray; CountArguments: word): JsValueRef;
    { getHeader(item) - returns an entry from the http request header }
    function getHeader(Arguments: PJsValueRefArray; CountArguments: word): JsValueRef;
    { redirect(url) - perform a redirect (if not websocket) }
    function redirect(Arguments: PJsValueRefArray; CountArguments: word): JsValueRef;
    { the remote client ip }
    property host: UnicodeString read GetHostname;
    { client lag - only measured/updated during idle pings }
    property lag: Integer read GetLag;
    { raw http post data (for regular http requests) }
    property postData: UnicodeString read GetPostData;
    { ping interval for client connection (only sent when idle), in seconds }
    property pingTime: Integer read GetPingTime write SetPingTime;
    { maximum timeframe for a ping-reply before the connection is dropped }
    property maxPongTime: Integer read GetPongTime write SetPongTime;
    { the mime type for the response. usually "text/html" }
    property mimeType: UnicodeString read FMimeType write FMimeType;
    { the http response message. usually "200 OK" }
    property returnType: UnicodeString read FReturnType write FReturnType;
    { the http request uri parameter }
    property parameter: UnicodeString read GetParameter;
  end;

  TChakraWebsocket = class;
  { TChakraWebsocketHandler }

  { global handler object for websocket scripts }
  TChakraWebsocketHandler = class(TNativeRTTIObject)
  private
    //FOnConnect: TBESENObjectFunction;
    //FOnData: TBESENObjectFunction;
    //FOnDisconnect: TBESENObjectFunction;
    //FOnRequest: TBESENObjectFunction;
    FUrl: UnicodeString;
    FParentThread: TChakraWebsocket;
    function GetUnloadTimeout: Integer;
    procedure SetUnloadTimeout(AValue: Integer);
  published
    (*
    { onRequest = function(client) - callback function for an incoming regular http request }
    property onRequest: TBESENObjectFunction read FOnRequest write FOnRequest;
    { onConnect = function(client) - callback function for new incoming websocket connection }
    property onConnect: TBESENObjectFunction read FOnConnect write FOnConnect;
    { onData = function(client, data) - callback function for incoming websocket client data }
    property onData: TBESENObjectFunction read FOnData write FOnData;
    { onDisconnect = function(client) - callback function when a client disconnects }
    property onDisconnect: TBESENObjectFunction read FOnDisconnect write FOnDisconnect; *)
    property url: UnicodeString read FUrl;
    property unloadTimeout: Integer read GetUnloadTimeout write SetUnloadTimeout;
  end;

  { TChakraWebsocketBulkSender }
  { bulk message sending object - sends the same message to multiple websocket clients,
    performs slightly better than implementing the same thing in ECMAScript }
  TChakraWebsocketBulkSender = class(TNativeRTTIObject)
  private
    FClients: array of TChakraWebsocketClient;
    function GetLength: Integer;
  protected
    //procedure InitializeObject; override;
    //procedure FinalizeObject; override;
    function RemoveClient(Client: TChakraWebsocketClient): Boolean;
  published
    { add(client) - add a websocket client into bulk send list }
    function add(Arguments: PJsValueRefArray; CountArguments: word): JsValueRef;
    { remove(client) - remove client from bulk send list }
    function remove(Arguments: PJsValueRefArray; CountArguments: word): JsValueRef;
    { send(data - send data to all clients in bulk send list}
    function send(Arguments: PJsValueRefArray; CountArguments: word): JsValueRef;
    { amount of clients in list }
    property count: Integer read GetLength;
  end;

  { TChakraWebsocket }

  TChakraWebsocket = class(TEPollWorkerThread)
  private
    FAutoUnload: Integer;
    FFilename: UnicodeString;
    FSite: TWebserverSite;
    FInstance: TChakraInstance;
    FHandler: TChakraWebsocketHandler;
    FClients: array of TChakraWebsocketClient;
    FIdleTicks,FGCTicks: Integer;
    FUrl: UnicodeString;
    FFlushList: TObjectList;
  protected
    procedure LoadBESEN;
    procedure UnloadBESEN;
    function GetClient(AClient: THTTPConnection): TChakraWebsocketClient;
    procedure ThreadTick; override;
    procedure AddConnection(Client: TEPollSocket);
    procedure ClientData(Sender: THTTPConnection; const data: AnsiString);
    procedure ClientDisconnect(Sender: TEPollSocket);
    procedure Initialize; override;
  public
    constructor Create(aParent: TWebserver; ASite: TWebserverSite; AFile: UnicodeString; Url: UnicodeString);
    destructor Destroy; override;
    procedure AddConnectionToFlush(AConnection: THTTPConnection);
    property Site: TWebserverSite read FSite;
    property AutoUnload: Integer read FAutoUnload write FAutoUnload;
  end;

implementation

uses
  chakraserverconfig,
  logging;

{ TChakraWebsocketBulkSender }

function TChakraWebsocketBulkSender.GetLength: Integer;
begin
  result:=Length(FClients);
end;

(*
procedure TChakraWebsocketBulkSender.FinalizeObject;
var
  i: Integer;
begin
  for i:=0 to Length(FClients)-1 do
    FClients[i].DecRefCount;
  Setlength(FClients, 0);
  inherited FinalizeObject;
end; *)

function TChakraWebsocketBulkSender.RemoveClient(Client: TChakraWebsocketClient
  ): Boolean;
var
  i: Integer;
begin
  result:=False;
  for i:=0 to Length(FClients)-1 do
  begin
    if FClients[i] = Client then
    begin
      FClients[i]:=FClients[Length(FClients)-1];
      Setlength(FClients, Length(FClients)-1);
      result:=True;
      Exit;
    end;
  end;
end;

function TChakraWebsocketBulkSender.add(Arguments: PJsValueRefArray;
  CountArguments: word): JsValueRef;
var
  o: TNativeRTTIObject;
  i: Integer;
begin
  Result:=JsFalseValue;
  if CountArguments<1 then
    Exit;

  o:=TNativeRTTIObject(JsGetExternalData(Arguments^[0]));
  if Assigned(o) and (o is TChakraWebsocketClient) then
  begin
    if not TChakraWebsocketClient(o).FIsRequest then
    begin
      i:=Length(FClients);
      Setlength(FClients, i+1);
      FClients[i]:=TChakraWebsocketClient(o);
      Result:=JsTrueValue;
    end;
  end else
    raise Exception.Create('Websocket client object expected');
end;

function TChakraWebsocketBulkSender.remove(Arguments: PJsValueRefArray;
  CountArguments: word): JsValueRef;
var
  o: TNativeRTTIObject;
begin
  Result:=JsFalseValue;
  if CountArguments<1 then
    Exit;
  o:=TNativeRTTIObject(JsGetExternalData(Arguments^[0]));
  if Assigned(o) and (o is TChakraWebsocketClient) then
  begin
    Result:=BooleanToJsBoolean(RemoveClient(TChakraWebsocketClient(o)));
  end else
    raise Exception.Create('Websocket client object expected');
end;

function TChakraWebsocketBulkSender.send(Arguments: PJsValueRefArray;
  CountArguments: word): JsValueRef;
var
  i: Integer;
  data: UnicodeString;
begin
  result:=JsUndefinedValue;
  if CountArguments<1 then
    Exit;

  data:=JsStringToUnicodeString(JsValueAsJsString(Arguments^[0]));

  for i:=0 to Length(FClients)-1 do
  with FClients[i] do
  if (Assigned(FConnection)) then
  begin
    if FConnection.Closed then
    begin
      RemoveClient(FClients[i]);
    end else
    begin
      FConnection.SendWS(Data, False);
      TChakraWebsocket(FConnection.Parent).AddConnectionToFlush(FConnection);
    end;
  end else
    RemoveClient(FClients[i]);
end;

{ TChakraWebsocketHandler }

function TChakraWebsocketHandler.GetUnloadTimeout: Integer;
begin
  result:=FParentThread.AutoUnload;
end;

procedure TChakraWebsocketHandler.SetUnloadTimeout(AValue: Integer);
begin
  FParentThread.AutoUnload:=AValue;
end;

{ TChakraWebsocketHandler }

constructor TChakraWebsocket.Create(aParent: TWebserver; ASite: TWebserverSite;
  AFile: UnicodeString; Url: UnicodeString);
begin
  FSite:=ASite;
  OnConnection:=@AddConnection;
  FFilename:=ASite.Path+'scripts/'+AFile;
  FInstance:=nil;
  FURL:=Url;
  FAutoUnload:=20000;
  FFlushList:=TObjectList.Create(False);
  inherited Create(aParent);
end;

destructor TChakraWebsocket.Destroy; 
begin
  inherited; 
  UnloadBESEN;
  FFlushList.Free;
end;

procedure TChakraWebsocket.AddConnectionToFlush(AConnection: THTTPConnection);
begin
  if FFlushList.IndexOf(AConnection) = -1 then
    FFLushList.Add(AConnection);
end;

procedure TChakraWebsocket.LoadBESEN;
begin
  dolog(llDebug, 'Loading Websocket Script at '+StripBasePath(FFilename));
  if Assigned(FInstance) then
    Exit;

  FInstance:=TChakraInstance.Create(FSite.Parent, FSite, self);
  FHandler:=TChakraWebsocketHandler.Create();
  //FHandler.InitializeObject;
  FHandler.FUrl:=FUrl;
  FHandler.FParentThread:=Self;

  //FInstance.GarbageCollector.Add(TChakraObject(FHandler));
  //FInstance.GarbageCollector.Protect(TChakraObject(FHandler));

  JsSetProperty(FInstance.Context.Global, 'handler', FHandler.Instance);
  //FInstance.ObjectGlobal.put('handler', BESENObjectValue(FHandler), false);

  TChakraWebsocketBulkSender.Project('BulkSender');
  //FInstance.RegisterNativeObject('BulkSender', TChakraWebsocketBulkSender);
  //FInstance.SetFilename(FFilename);
  try
    FInstance.ExecuteFile(FFilename);
  except
    on e: Exception do
      FInstance.OutputException(e, 'websocket-init');
  end;
end;

procedure TChakraWebsocket.UnloadBESEN;
var
  conn: THTTPConnection;
begin
  if FInstance = nil then
    Exit;

  dolog(llDebug, 'Unloading Websocket Script at '+StripBasePath(FFilename));

  while Length(FClients)>0 do
  begin
    conn:=FClients[0].FConnection;
    if Assigned(conn) then
    begin
      ClientDisconnect(conn);
      TWebserver(Parent).FreeConnection(conn);
    end;
  end;

  //FInstance.GarbageCollector.UnProtect(TChakraObject(FHandler));

  FInstance.Free;
  FInstance:=nil;
  FHandler:=nil;
end;

procedure TChakraWebsocket.ClientData(Sender: THTTPConnection;
  const data: AnsiString);
var
  client: TChakraWebsocketClient;
  //a: array[0..1] of PBESENValue;
  //v,v2, AResult: TChakraValue;
begin
  client:=GetClient(Sender);

  if not Assigned(client) then
  begin
    dolog(llDebug, 'Got websocket client-data with no associated client');
    Sender.Close;
    Exit;
  end;

  try
     ExecuteCallback(FHandler, 'onData', [client.Instance, StringToJsString(data)]);
  except
    on e: Exception do
      FInstance.OutputException(e, 'handler.onData');
  end;
end;

procedure TChakraWebsocket.ClientDisconnect(Sender: TEPollSocket);
var
  client: TChakraWebsocketClient;
  i: Integer;
begin
  if not (Sender is THTTPConnection) then
    Exit;

  client:=GetClient(THTTPConnection(Sender));

  if not Assigned(client) then
    Exit;

  if not client.FIsRequest then
  begin
    try
       ExecuteCallback(FHandler, 'onDisconnect', [FHandler.Instance, client.Instance]);
    except
      on e: Exception do
        FInstance.OutputException(e, 'handler.onDisconnect');
    end;
  end;
  client.DecRefCount;

  i:=FFlushList.IndexOf(Sender);
  if i>=0 then
    FFlushList.Delete(i);

  for i:=0 to Length(FClients)-1 do
    if FClients[i] = client then
    begin
      FClients[i]:=FClients[Length(FClients)-1];
      Setlength(FClients, Length(FClients)-1);
      Break;
    end;

  client.FConnection:=nil;
end;

procedure TChakraWebsocket.Initialize;
begin
  inherited Initialize;
  LoadBESEN;
end;

function TChakraWebsocket.GetClient(AClient: THTTPConnection): TChakraWebsocketClient;
var
  i: Integer;
begin
  result:=nil;
  if not Assigned(AClient) then
    Exit;

  for i:=0 to Length(FClients)-1 do
    if FClients[i].FConnection = AClient then
    begin
      result:=FClients[i];
      Exit;
    end;
end;

procedure TChakraWebsocket.AddConnection(Client: TEPollSocket);
var
  i: Integer;
  //a: PBESENValue;
  //v: TChakraValue;
  //AResult: TChakraValue;
  aclient: TChakraWebsocketClient;
begin
  if not Assigned(Client) then
    Exit;

  if not (Client is THTTPConnection) then
    Exit;

  if not Assigned(FInstance) then
    LoadBESEN;

  aclient:=TChakraWebsocketClient.Create();
  //FInstance.GarbageCollector.Add(TChakraObject(aclient));

  //aclient.InitializeObject;
  aclient.AddRefCount;
  aclient.FConnection:=THTTPConnection(Client);
  aclient.FConnection.OnWebsocketData:=@ClientData;
  aclient.FConnection.OnDisconnect:=@ClientDisconnect;

  //a:=@v;
  i:=Length(FClients);
  Setlength(FClients, i+1);
  FClients[i]:=aClient;
  //v:=BESENObjectValue(aClient);

  aclient.FIsRequest:=not aclient.FConnection.CanWebsocket;
  if aclient.FIsRequest then
  begin
    try
       ExecuteCallback(FHandler, 'onRequest', [FHandler.Instance, aClient.Instance]);
    except
      on e: Exception do
        FInstance.OutputException(e, 'handler.onRequest');
    end;
  end else
  begin
    aclient.FConnection.UpgradeToWebsocket;
    try
       ExecuteCallback(FHandler, 'onConnect', [FHandler.Instance, aClient.Instance]);
      //if Assigned(FHandler.onConnect) then
      //  FHandler.onConnect.Call(BESENObjectValue(FHandler), @a, 1, AResult);
    except
      on e: Exception do
        FInstance.OutputException(e, 'handler.onConnect');
    end;
  end;
end;

procedure TChakraWebsocket.ThreadTick;
var
  i: Integer;
begin
  if Assigned(FInstance) then
  begin
    if FFlushList.Count>0 then
    begin
      for i:=0 to FFLushlist.Count-1 do
        THTTPConnection(FFLushList[i]).FlushSendbuffer;
      FFlushList.Clear;
    end;

    FInstance.ProcessHandlers;
    if longword(TWebserver(Parent).Ticks - FGCTicks)>=1000 then
    begin
      FInstance.CollectGarbage;
      FGCTicks:=TWebserver(Parent).Ticks;
    end;

    if (Length(FClients)>0) then
      FIdleTicks:=0
    else begin
      if FAutoUnload>0 then
      if FIdleTicks * EpollWaitTime > FAutoUnload then
        UnloadBESEN
      else
        inc(FIdleTicks);
    end;
  end;
  inherited;
end;

{ TChakraWebsocketClient }

procedure TChakraWebsocketClient.AddRefCount;
begin
  if FRefCounter = 0 then
  begin
    //TChakra(Instance).GarbageCollector.Protect(Self);
  end;
  Inc(FRefCounter);
end;

procedure TChakraWebsocketClient.DecRefCount;
begin
  Dec(FRefCounter);
  if FRefCounter = 0 then
  begin
    //nTChakra(Instance).GarbageCollector.Unprotect(Self);
  end else
  if FRefCounter < 0 then
    dolog(llWarning, 'Internal Error: Reference Counter in TChakraWebsocketClient is broken');
end;

function TChakraWebsocketClient.send(Arguments: PJsValueRefArray;
  CountArguments: word): JsValueRef;
begin
  Result := JsUndefinedValue;

  if CountArguments<=0 then
    Exit;

  if not Assigned(FConnection) then
    Exit;

  if FIsRequest then
  begin
    // for a normal http request, we cache the reply and send it out at once
    FReply:=FReply + JsStringToUnicodeString(JsValueAsJsString(Arguments^[0]))
  end else
  begin
    { BUG: Calling OpenSSL functions from a native script callback function
      can cause weird exceptions (from within OpenSSL)... in besen. but does it
      also happen with chakra?
      }
    FConnection.SendWS(JsStringToUnicodeString(JsValueAsJsString(Arguments^[0])), not FConnection.IsSSL);
    if FConnection.IsSSL then
     TChakraWebsocket(FConnection.Parent).AddConnectionToFlush(FConnection);
  end;
end;

function TChakraWebsocketClient.getHeader(Arguments: PJsValueRefArray;
  CountArguments: word): JsValueRef;
begin
  Result := JsUndefinedValue;

  if CountArguments>0 then
    if(Assigned(FConnection)) then
      Result:=StringToJsString(FConnection.Header.header[JsStringToUnicodeString(JsValueAsJsString(Arguments^[0]))]);
end;

function TChakraWebsocketClient.redirect(Arguments: PJsValueRefArray;
  CountArguments: word): JsValueRef;
var
  url: UnicodeString;
begin
  Result := JsUndefinedValue;

  if Assigned(FConnection) then
  begin
    if (CountArguments>0) and FIsRequest then
    begin
      url:=JsStringToUnicodeString(JsValueAsJsString(Arguments^[0]));
      FConnection.Reply.header.Add('Location', url);
      FConnection.SendContent('text/html', '<html><body>Content has been moved to <a href="'+url+'">'+url+'</a></body></html>', '302 Found');
      FConnection.Close;
    end;
  end;
end;


function TChakraWebsocketClient.disconnect(Arguments: PJsValueRefArray;
  CountArguments: word): JsValueRef;
begin
  Result := JsUndefinedValue;
  if Assigned(FConnection) then
  begin
    if FIsRequest then
    begin
      FConnection.SendContent(FMimeType, FReply, FReturnType, not FConnection.IsSSL);
      if FConnection.IsSSL then
       TChakraWebsocket(FConnection.Parent).AddConnectionToFlush(FConnection);
    end;
    FConnection.Close;
  end;
end;

function TChakraWebsocketClient.GetLag: Integer;
begin
  if Assigned(FConnection) then
    result:=FConnection.Lag
  else
    result:=-1;
end;

function TChakraWebsocketClient.GetParameter: UnicodeString;
begin
  result:=UnicodeString(FConnection.Header.parameters);
end;

function TChakraWebsocketClient.GetPingTime: Integer;
begin
  if Assigned(FConnection) then
    result:=FConnection.WebsocketPingIdleTime
  else
    result:=-1;
end;

function TChakraWebsocketClient.GetPongTime: Integer;
begin
  if Assigned(FConnection) then
    result:=FConnection.WebsocketMaxPongTime
  else
    result:=-1;
end;

function TChakraWebsocketClient.GetPostData: UnicodeString;
begin
  result:='';
end;

procedure TChakraWebsocketClient.SetPingTime(AValue: Integer);
begin
  if not Assigned(FConnection) then
    Exit;

  if AValue>1 then
    FConnection.WebsocketPingIdleTime:=AValue
  else
    FConnection.WebsocketPingIdleTime:=1
end;

procedure TChakraWebsocketClient.SetPongTime(AValue: Integer);
begin
  if not Assigned(FConnection) then
    Exit;

  if AValue>1 then
    FConnection.WebsocketMaxPongTime:=AValue
  else
    FConnection.WebsocketMaxPongTime:=1
end;

constructor TChakraWebsocketClient.Create(Args: PJsValueRef; ArgCount: Word;
  AFinalize: Boolean);
begin
  inherited Create(Args, ArgCount, AFinalize);
  FReply:='';
  FIsRequest:=False;
  FMimeType:='text/html';
  FReturnType:='200 OK';
  FRefCounter:=0;
end;

function TChakraWebsocketClient.GetHostname: UnicodeString;
begin
  if Assigned(FConnection) then
    result:=FConnection.GetRemoteIP
  else
    result:='';
end;

end.

