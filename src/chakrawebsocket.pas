unit chakrawebsocket;

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
  ChakraEventObject,
  chakrainstance,
  chakraevents,
  epollsockets,
  webserverhosts,
  webserver;

type
  { TChakraWebsocketClient }

  { client object - this is created automatically for each new connection and
    passed to the script via global handler object callbacks.

    for regular http clients, .disconnect() must be called after the request
    has been processed. Otherwise the client will never receive a response
  }
  TChakraWebsocketClient = class(TNativeRTTIEventObject)
  private
    FIsRequest: Boolean;
    FMimeType: string;
    FReply: string;
    FConnection: THTTPConnection;
    FReturnType: string;
    function GetHostname: string;
    function GetLag: Integer;
    function GetParameter: string;
    function GetPingTime: Integer;
    function GetPongTime: Integer;
    function GetPostData: string;
    procedure SetPingTime(AValue: Integer);
    procedure SetPongTime(AValue: Integer);
  public
    constructor Create(Args: PJsValueRef = nil; ArgCount: Word = 0; AFinalize: Boolean = False); override;
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
    property host: string read GetHostname;
    { client lag - only measured/updated during idle pings }
    property lag: Integer read GetLag;
    { raw http post data (for regular http requests) }
    property postData: string read GetPostData;
    { ping interval for client connection (only sent when idle), in seconds }
    property pingTime: Integer read GetPingTime write SetPingTime;
    { maximum timeframe for a ping-reply before the connection is dropped }
    property maxPongTime: Integer read GetPongTime write SetPongTime;
    { the mime type for the response. usually "text/html" }
    property mimeType: string read FMimeType write FMimeType;
    { the http response message. usually "200 OK" }
    property returnType: string read FReturnType write FReturnType;
    { the http request uri parameter }
    property parameter: string read GetParameter;
  end;

  TChakraWebsocket = class;
  { TChakraWebsocketHandler }

  { global handler object for websocket scripts }
  TChakraWebsocketHandler = class(TNativeRTTIEventObject)
  private
    FUrl: string;
    FParentThread: TChakraWebsocket;
    function GetUnloadTimeout: Integer;
    procedure SetUnloadTimeout(AValue: Integer);
  published
    property url: string read FUrl;
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

  { TChakraDataEvent }

  TChakraDataEvent = class(TChakraEvent)
  private
    FClient: TChakraWebsocketClient;
    FData: string;
  published
    property client: TChakraWebsocketClient read FClient write FClient;
    property data: string read FData write FData;
  end;

  { TChakraWebsocket }

  TChakraWebsocket = class(TEPollWorkerThread)
  private
    FCS: TCriticalSection;
    FAutoUnload: Integer;
    FFilename: string;
    FSite: TWebserverSite;
    FInstance: TChakraInstance;
    FHandler: TChakraWebsocketHandler;
    FClients: array of TChakraWebsocketClient;
    FIdleTicks,FGCTicks: Integer;
    FUrl: string;
    FFlushList: TObjectList;
    FEnvVars: TFPStringHashTable;
  protected
    procedure LoadInstance;
    procedure UnloadInstance;
    function GetClient(AClient: THTTPConnection): TChakraWebsocketClient;
    procedure ThreadTick; override;
    procedure AddConnection(Client: TEPollSocket);
    procedure ClientData(Sender: THTTPConnection; const data: string);
    procedure ClientDisconnect(Sender: TEPollSocket);
    procedure Initialize; override;
    procedure Finalize; override;
  public
    constructor Create(aParent: TWebserver; ASite: TWebserverSite; AFile: string; Url: string);
    destructor Destroy; override;
    procedure AddConnectionToFlush(AConnection: THTTPConnection);
    procedure RemoveWebsocketClient(Client: TChakraWebsocketClient);
    procedure SetEnvVar(Name, Value: string);
    function GetEnvVar(Name: string): string;
    property Site: TWebserverSite read FSite;
    property AutoUnload: Integer read FAutoUnload write FAutoUnload;
    property Url: string read FUrl;
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
  data: string;
begin
  result:=JsUndefinedValue;
  if CountArguments<1 then
    Exit;

  data:=string(JsStringToUnicodeString(JsValueAsJsString(Arguments^[0])));

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
  AFile: string; Url: string);
begin
  FCS:=TCriticalSection.Create;
  FSite:=ASite;
  OnConnection:=@AddConnection;
  FFilename:=ASite.Path+'scripts/'+AFile;
  FInstance:=nil;
  FURL:=Url;
  FAutoUnload:=20000;
  FFlushList:=TObjectList.Create(False);
  FEnvVars:=TFPStringHashTable.Create;
  inherited Create(aParent);
end;

destructor TChakraWebsocket.Destroy;
begin
  inherited;
  FCS.Free;
  FFlushList.Free;
  FEnvVars.Free;
end;

procedure TChakraWebsocket.AddConnectionToFlush(AConnection: THTTPConnection);
begin
  if FFlushList.IndexOf(AConnection) = -1 then
    FFLushList.Add(AConnection);
end;

procedure TChakraWebsocket.RemoveWebsocketClient(Client: TChakraWebsocketClient);
var
  i: Integer;
begin
  for i:=0 to Length(FClients)-1 do
  if FClients[i] = Client then
  begin
    FClients[i]:=FClients[Length(FClients)-1];
    Setlength(FClients, Length(FClients) - 1);
    Client.FConnection:=nil;
    if Client.Release = 0 then
      Client.Free;
    Exit;
  end;
  raise Exception.Create('Websocket client not found');
end;

procedure TChakraWebsocket.SetEnvVar(Name, Value: string);
begin
  FCS.Enter;
  try
    FEnvVars[Name]:=Value;
  finally
    FCS.Leave;
  end;
end;

function TChakraWebsocket.GetEnvVar(Name: string): string;
begin
  FCS.Enter;
  try
    Result:=FEnvVars[Name];
  finally
    FCS.Leave;
  end;
end;

procedure TChakraWebsocket.LoadInstance;
begin
  dolog(llDebug, 'Loading Websocket Script at '+StripBasePath(FFilename));
  if Assigned(FInstance) then
    Exit;

  FInstance:=TChakraInstance.Create(FSite.Parent, FSite, self);
  FHandler:=TChakraWebsocketHandler.Create(nil, 0, True);
  FHandler.FUrl:=FUrl;
  FHandler.FParentThread:=Self;

  JsSetProperty(FInstance.Context.Global, 'handler', FHandler.Instance);
  TChakraWebsocketBulkSender.Project('BulkSender');

  try
    FInstance.ExecuteFile(FFilename);
  except
    on e: Exception do
      FInstance.SystemObject.HandleException(e, 'websocket-init');
  end;
end;

procedure TChakraWebsocket.UnloadInstance;
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

  FInstance.CollectGarbage;
  FInstance.Free;
  FInstance:=nil;
  FHandler:=nil;
end;

procedure TChakraWebsocket.ClientData(Sender: THTTPConnection;
  const data: string);
var
  client: TChakraWebsocketClient;
  ev: TChakraDataEvent;
  //a: array[0..1] of PBESENValue;
  //v,v2, AResult: TChakraValue;
begin
  if (Sender.wsVersion = wvNone) or (Sender.wsVersion = wvDelayedRequest) then
    raise Exception.Create('Bad state for client data');

  client:=GetClient(Sender);

  if not Assigned(client) then
  begin
    dolog(llDebug, 'Got websocket client-data with no associated client');
    Sender.Close;
    Exit;
  end;

  ev:=TChakraDataEvent.Create('data', False);
  ev.data:=data;
  ev.client:=client;
  client.dispatchEvent(ev);
  FHandler.dispatchEvent(ev);

  try
    ExecuteCallback(FHandler, 'onData', [client.Instance, StringToJsString(data)]);
  except
    on e: Exception do
      FInstance.SystemObject.HandleException(e, 'handler.onData');
  end;

  try
    ExecuteCallback(FHandler, 'ondata', [ev.Instance]);
  except
    on e: Exception do
    FInstance.SystemObject.HandleException(e, 'handler.ondata');
  end;
  ev.Free;
end;

procedure TChakraWebsocket.ClientDisconnect(Sender: TEPollSocket);
var
  client: TChakraWebsocketClient;
  ev: TChakraDataEvent;
  i: Integer;
begin
  if not (Sender is THTTPConnection) then
    Exit;

  client:=GetClient(THTTPConnection(Sender));

  if not Assigned(client) then
    Exit;

  if not client.FIsRequest then
  begin
    ev:=TChakraDataEvent.Create('disconnect', False);
    ev.data:='';
    ev.client:=client;
    client.dispatchEvent(ev);
    FHandler.dispatchEvent(ev);

    try
       ExecuteCallback(FHandler, 'onDisconnect', [client.Instance]);
    except
      on e: Exception do
        FInstance.SystemObject.HandleException(e, 'handler.onDisconnect');
    end;

    try
       ExecuteCallback(FHandler, 'ondisconnect', [ev.Instance]);
    except
      on e: Exception do
        FInstance.SystemObject.HandleException(e, 'handler.ondisconnect');
    end;

    ev.Free;
  end;

  i:=FFlushList.IndexOf(Sender);
  if i>=0 then
    FFlushList.Delete(i);

  RemoveWebsocketClient(client);
end;

procedure TChakraWebsocket.Initialize;
begin
  inherited Initialize;
  LoadInstance;
end;

procedure TChakraWebsocket.Finalize;
var
  i: Integer;
begin
  inherited Finalize;
  for i:=0 to Length(FClients)-1 do
  begin
    FClients[i].Free;
  end;
  UnloadInstance;
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
  eventsFired: Integer;
  ev: TChakraDataEvent;
  aclient: TChakraWebsocketClient;
begin
  if not Assigned(Client) then
    Exit;

  if not (Client is THTTPConnection) then
    Exit;

  if not Assigned(FInstance) then
    LoadInstance;

  aclient:=TChakraWebsocketClient.Create(nil, 0, True);
  aclient.AddRef;
  aclient.FConnection:=THTTPConnection(Client);
  aclient.FConnection.OnWebsocketData:=@ClientData;
  aclient.FConnection.OnDisconnect:=@ClientDisconnect;
  aclient.FIsRequest:=not aclient.FConnection.CanWebsocket;

  i:=Length(FClients);
  Setlength(FClients, i+1);
  FClients[i]:=aClient;

  if aclient.FIsRequest then
  begin
    ev:=TChakraDataEvent.Create('request', False);
    ev.client:=aClient;
    ev.data:='';
    eventsFired:=JsNumberToInt(JsValueAsJsNumber(FHandler.dispatchEvent(ev)));

    try
       ExecuteCallback(FHandler, 'onRequest', [aClient.Instance]);
       if (JsGetProperty(FHandler.Instance, 'onRequest') <> JsUndefinedValue) then
         inc(eventsFired);
    except
      on e: Exception do
        FInstance.SystemObject.HandleException(e, 'handler.onRequest');
    end;

    try
       ExecuteCallback(FHandler, 'onrequest', [ev.Instance]);
       if (JsGetProperty(FHandler.Instance, 'onrequest') <> JsUndefinedValue) then
         inc(eventsFired);
    except
      on e: Exception do
        FInstance.SystemObject.HandleException(e, 'handler.onrequest');
    end;
    ev.Free;

    if (eventsFired = 0) then
    begin
      if not Client.Closed then
      begin
        THTTPConnection(Client).SendStatusCode(404);
        if THTTPConnection(Client).KeepAlive then
        begin
          THTTPConnection(Client).RelocateBack;
        end else
        begin
          THTTPConnection(Client).Close;
        end;
      end;
    end;
  end else
  begin
    aclient.FConnection.UpgradeToWebsocket;

    ev:=TChakraDataEvent.Create('connect', False);
    ev.data:='';
    ev.client:=aclient;
    eventsFired:=JsNumberToInt(JsValueAsJsNumber(FHandler.dispatchEvent(ev)));

    try
       ExecuteCallback(FHandler, 'onconnect', [ev.Instance]);
       if (JsGetProperty(FHandler.Instance, 'onconnect') <> JsUndefinedValue) then
         inc(eventsFired);
    except
      on e: Exception do
        FInstance.SystemObject.HandleException(e, 'handler.onconnect');
    end;

    try
       ExecuteCallback(FHandler, 'onConnect', [aClient.Instance]);
       if (JsGetProperty(FHandler.Instance, 'onConnect') <> JsUndefinedValue) then
         inc(eventsFired);
    except
      on e: Exception do
        FInstance.SystemObject.HandleException(e, 'handler.onConnect');
    end;
    ev.Free;
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
      begin
        FIdleTicks:=0;
        UnloadInstance;
      end
      else
        inc(FIdleTicks);
    end;
  end;
  inherited;
end;

{ TChakraWebsocketClient }

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
    FReply:=FReply + string(JsStringToUnicodeString(JsValueAsJsString(Arguments^[0])))
  end else
  begin
    { BUG: Calling OpenSSL functions from a native script callback function
      can cause weird exceptions (from within OpenSSL)... in besen. but does it
      also happen with chakra?
      }
    FConnection.SendWS(string(JsStringToUnicodeString(JsValueAsJsString(Arguments^[0]))), not FConnection.IsSSL);
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
      Result:=StringToJsString(FConnection.Header.header[string(JsStringToUnicodeString(JsValueAsJsString(Arguments^[0])))]);
end;

function TChakraWebsocketClient.redirect(Arguments: PJsValueRefArray;
  CountArguments: word): JsValueRef;
var
  url: string;
begin
  Result := JsUndefinedValue;

  if Assigned(FConnection) then
  begin
    if (CountArguments>0) and FIsRequest then
    begin
      url:=string(JsStringToUnicodeString(JsValueAsJsString(Arguments^[0])));
      FConnection.Reply.header.Add('Location', url);
      FConnection.SendContent('text/html', '<html><body>Content has been moved to <a href="'+url+'">'+url+'</a></body></html>', '302 Found');
      FConnection.Close;
    end;
  end;
end;


function TChakraWebsocketClient.disconnect(Arguments: PJsValueRefArray;
  CountArguments: word): JsValueRef;
var
  ws: TChakraWebsocket;
begin
  Result := JsUndefinedValue;
  if Assigned(FConnection) then
  begin
    if FIsRequest then
    begin
      ws:=TChakraWebsocket(FConnection.Parent);
      FConnection.SendContent(FMimeType, FReply, FReturnType, not FConnection.IsSSL);
      if FConnection.IsSSL then
       ws.AddConnectionToFlush(FConnection);
      if (not FConnection.Closed) and FConnection.KeepAlive then
      begin

        FConnection.RelocateBack;
      end else
      begin
        FConnection.Close;
      end;
      ws.RemoveWebsocketClient(Self);
    end else
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

function TChakraWebsocketClient.GetParameter: string;
begin
  result:=string(FConnection.Header.parameters);
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

function TChakraWebsocketClient.GetPostData: string;
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
end;

function TChakraWebsocketClient.GetHostname: string;
begin
  if Assigned(FConnection) then
    result:=FConnection.GetRemoteIP
  else
    result:='';
end;

end.

