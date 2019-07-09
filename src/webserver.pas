unit webserver;

{$i ccwssettings.inc}

interface

uses
  Classes,
  SysUtils,
  SyncObjs,
  synsock,
  blcksock,
  epollsockets,
  baseunix,
  unix,
  sockets,
  httphelper,
  DateUtils,
  MD5,
  webserverhosts,
  logging;

const
  { maximum number of cached THTTPConnection classes }
  ConnectionCacheSize = 2048;

type
  TWebsocketVersion = (wvNone, wvUnknown, wvHixie76, wvHybi07, wvHybi10, wvRFC, wvDelayedRequest);
  TWebsocketMessageType = (wsConnect, wsData, wsDisconnect, wsError);

  TWebsocketFrame = record
    fin, RSV1, RSV2, RSV3: Boolean;
    opcode: Byte;
    masked: Boolean;
    Length: Int64;
    Mask: array[0..3] of Byte;
  end;

  TWebserver = class;
  THTTPConnection = class;
  THTTPConnectionDataReceived = procedure(Sender: THTTPConnection; const Data: string) of object;
  THTTPConnectionPostDataReceived = procedure(Sender: THTTPConnection; const Data: string; finished: Boolean) of object;
  TCGIEnvCallback = procedure(const Name, Value: string) of object;

  { THTTPConnection }
  THTTPConnection = class(TEPollSocket)
  private
    FInBuffer: string;
    FIdent: string;
    FPathUrl: string;
    FMaxPongTime: Integer;
    FOnPostData: THTTPConnectionPostDataReceived;
    FOnWebsocketData: THTTPConnectionDataReceived;
    FPingIdleTime: Integer;
    FHeader: THTTPRequest;
    FReply: THTTPReply;
    fkeepalive: Boolean;
    FTag: Pointer;
    FVersion: TWebsocketVersion;
    FIdletime: Integer;
    hassegmented: Boolean;
    target: string;
    FWSData: string;
    FLag: Integer;
    FServer: TWebserver;
    FHost: TWebserverSite;
    FContentLength: Integer;
    FGotHeader: Boolean;
    FLastPing: longint;
    FPostData: string;
    procedure CheckMessageBody;
    function GotCompleteRequest: Boolean;
    function IsExternalScript: Boolean;
    procedure ProcessHixie76;
    function ReadRFCWebsocketFrame(out header: TWebsocketFrame; out HeaderSize: Integer): Boolean;
    procedure ProcessRFC;
  protected
    procedure AddCallback; override;
    procedure ProcessData(const Buffer: Pointer; BufferLength: Integer); override;
    procedure ProcessRequest;
    procedure ProcessWebsocket;
    procedure SendReply;
  public
    constructor Create(Server: TWebserver; ASocket: TSocket);
    destructor Destroy; override;
    procedure Cleanup; override;
    procedure Dispose; override;
    function CanWebsocket: Boolean;
    procedure UpgradeToWebsocket;
    function CheckTimeout: Boolean; override;
    procedure SendStatusCode(const Code: Word);
    procedure SendWS(data: string; Flush: Boolean = True);
    procedure SendContent(mimetype, data: string; result: string = '200 OK'; Flush: Boolean = True);
    procedure SendFile(mimetype: string; FileName: string; result: string = '200 OK');
    (* called after a regular request is processed by the websocket handler,
       to return the connection back to the normal worker-pool *)
    procedure RelocateBack;
    property wsVersion: TWebsocketVersion read FVersion write FVersion;
    property OnWebsocketData: THTTPConnectionDataReceived read FOnWebsocketData write FOnWebsocketData;
    property OnPostData: THTTPConnectionPostDataReceived read FOnPostData write FOnPostData;
    property Header: THTTPRequest read FHeader;
    property Lag: Integer read FLag write FLag;
    property WebsocketPingIdleTime: Integer read FPingIdleTime write FPingIdleTime;
    property WebsocketMaxPongTime: Integer read FMaxPongTime write FMaxPongTime;
    property Reply: THTTPReply read FReply;
    property KeepAlive: Boolean read fkeepalive;
  end;

  { TWebserverListener }

  TWebserverListener = class(TThread)
  private
    FParent: TWebserver;
    FIP: string;
    FPort: string;
  protected
    procedure Execute; override;
  public
    constructor Create(Parent: TWebserver; IP, Port: string);
    destructor Destroy; override;
    property IP: string read FIP;
    property Port: string read FPort;
    property Parent: TWebserver read FParent;
  end;

  { TWebserverWorkerThread }
  TWebserverWorkerThread = class(TEpollWorkerThread)
  protected
    procedure Initialize; override;
  end;

  { TWebserver }
  TWebserver = class
  private
    FCS: TCriticalSection;
    FTestMode: Boolean;
    FTicks: longword;
    FWorkerCount: Integer;
    FWorker: array of TWebserverWorkerThread;
    FSiteManager: TWebserverSiteManager;
    FCachedConnectionCount: Integer;
    FCachedConnections: array[0..ConnectionCacheSize] of THTTPConnection;
    FListener: array of TWebserverListener;
    fcurrthread: Integer;
    FTotalConnections: Int64;
    FTotalRequests: Int64;
  protected
    procedure AddWorkerThread(AThread: TWebserverWorkerThread);
    procedure RelocateBack(Connection: THTTPConnection);
  public
    constructor Create(const BasePath: string; IsTestMode: Boolean = False);
    destructor Destroy; override;
    function SetThreadCount(Count: Integer): Boolean;
    function AddListener(IP, Port: string): TWebserverListener;
    function RemoveListener(Listener: TWebserverListener): Boolean;
    procedure Accept(Sock: TSocket);
    procedure FreeConnection(Connection: THTTPConnection);
    property SiteManager: TWebserverSiteManager read FSiteManager;
    property TestMode: Boolean read FTestMode;
    property Ticks: longword read FTicks write FTicks;
  end;

implementation

uses
  buildinfo,
  mimehelper,
  sha1,
  base64;

function ProcessHandshakeString(const Input: string): string;
var
  SHA1: TSHA1Context;
  hash: string;

  procedure ShaUpdate(s: string);
  begin
    SHA1Update(SHA1, s[1], length(s));
  end;

type
  PSHA1Digest = ^TSHA1Digest;

begin
  SHA1Init(SHA1);
  Setlength(hash, 20);

  ShaUpdate(Input+'258EAFA5-E914-47DA-95CA-C5AB0DC85B11');

  SHA1Final(SHA1, PSHA1Digest(@hash[1])^);
  result:=string(EncodeStringBase64(AnsiString(hash)));
end;

function ProcessHandshakeStringV0(const Input: string): string;
// concatenates numbers found in input and divides the resulting number by the number of spaces
// returns a 4 byte string
var
  i,j,k: cardinal;
  s: string;
begin
  result := '';
  j := 0;
  s := '';

  for i:=1 to Length(Input) do
  if (Input[i]>#47)and(Input[i]<#58) then
    s := s + (Input[i])
  else
  if Input[i]=#32 then
    inc(j);

  // IntToStr() doesnt work with numbers > 2^31
  // todo: check length(s)

  k := 0;
  for i:=1 to length(s) do
  k := k*10 + cardinal(ord(s[i])-48);

  // todo: check if (k mod j) = 0
  if j>0 then
    j := k div j
  else
    j := k; // wtf

  for i:=0 to 3 do
  result := result + Char(PByteArray(@j)^[3-i]);
end;

function MD5ofStr(str: string): string;
var
  i: Integer;
  tempstr: TMDDigest;
begin
  tempstr:=MDString(AnsiString(str), MD_VERSION_5);
  SetLength(result, Length(tempstr));
  for i:=0 to Length(tempstr)-1 do
  result[i + 1]:=Char(tempstr[i]);
end;

function CreateHeader(opcode: Byte; Length:Int64): string;
begin
  if Length>125 then
    SetLength(Result, 4)
  else
    setlength(Result, 2);

  result[1] := AnsiChar(128 + (opcode and 15));
  if Length<126 then
  begin
    result[2] := AnsiChar(Length);
  end else
  if Length < 65536 then
  begin
    result[2] := #126;
    result[3] := AnsiChar(Length shr 8);
    result[4] := AnsiChar(Length);
  end else
  begin
    Setlength(result, 10);
    result[2] := #127;
    result[3]:=AnsiChar(Length shr 56);
    result[4]:=AnsiChar(Length shr 48);
    result[5]:=AnsiChar(Length shr 40);
    result[6]:=AnsiChar(Length shr 32);
    result[7]:=AnsiChar(Length shr 24);
    result[8]:=AnsiChar(Length shr 16);
    result[9]:=AnsiChar(Length shr 8);
    result[10]:=AnsiChar(Length);
  end;
end;

{ TWebserverWorkerThread }

procedure TWebserverWorkerThread.Initialize;
begin
  inherited Initialize;
end;

{ TWebserverListener }

procedure TWebserverListener.Execute;
var
  ClientSock: TSocket;
  FSock: TTCPBlockSocket;
  x: Integer;
  AcceptError: Boolean;
begin
  FSock:=TTCPBlockSocket.Create;
  with FSock do
  begin
    FSock.EnableReuse(True);
    CreateSocket;
    FSock.EnableReuse(True);
    SetLinger(true, 1000);
    bind(AnsiString(FIP), AnsiString(FPort));
    listen;
    x:=0;
    AcceptError:=False;
    repeat
      try
      if canread(500) then
      begin
        ClientSock:=accept;
        if (LastError = 0)and(ClientSock>=0) then
        begin
          AcceptError:=False;
          x := fpfcntl(ClientSock, F_GETFL, 0);
          if x<0 then
          begin
            dolog(llError, FIP+':'+FPort+': Could not F_GETFL for '+string(IntToStr(ClientSock)));
            continue;
          end else begin
            x := fpfcntl(ClientSock, F_SetFl, x or O_NONBLOCK);
            if x<0 then 
            begin
              dolog(llError, FIP+':'+FPort+': Could not set NONBLOCK!');
              continue;
            end;
          end;
          FParent.Accept(ClientSock);
        end else
        begin
          if not AcceptError then
          begin
            dolog(llWarning, FIP+':'+FPort+': Could not accept incoming connection!');
            AcceptError:=True;
          end;
          { there is nothing we can do - sleep to avoid busyloop as canread()
            will return instantly as long as there are unaccepted connections }
          Sleep(50);
        end;
      end;
      except
        on e: Exception do dolog(llError, string(e.Message));
      end;
    until Terminated;
    FSock.CloseSocket;
    dolog(llNotice, 'Stopped listening to '+FIP+':'+FPort);
  end;
  FSock.Free;
end;

constructor TWebserverListener.Create(Parent: TWebserver; IP, Port: string);
begin
  FIP:=IP;
  FParent:=Parent;
  FPort:=Port;
  inherited Create(False);
end;

destructor TWebserverListener.Destroy; 
begin
  inherited Destroy;
end;

{ THTTPConnection }

procedure THTTPConnection.ProcessRequest;
var
  p: TEpollWorkerThread;
  newtarget: string;
begin
  try
    if FGotHeader then
    begin
      InterLockedIncrement64(FServer.FTotalRequests);
      FGotHeader:=False;
      // FContentLength:=-1;

      FReply.Clear(FHeader.version);

      Freply.header.Add('Server', FullServerName);

      Freply.header.Add('Date', DateTimeToHTTPTime(Now));
      fkeepalive := Pos('KEEP-ALIVE', Uppercase(Fheader.header['Connection']))>0;
      if fkeepalive then
        Freply.header.Add('Connection', 'keep-alive');

      if (FHeader.version <> 'HTTP/1.0')and(FHeader.version <> 'HTTP/1.1') then
      begin
        // unknown version
        fkeepalive:=False;
        SendStatusCode(505);
        Exit;
      end;

      if (FHeader.version = 'HTTP/1.1') and (FHeader.header['Host']='') then
      begin
        // http/1.1 without Host is not allowed
        fkeepalive:=False;
        SendStatusCode(400);
        Exit;
      end;

      FHost:=FServer.SiteManager.GetSite(string(FHeader.header['Host']));

      if not Assigned(FHost) then
      begin
        SendStatusCode(500);
        Exit;
      end;

      FHost.ApplyResponseHeader(FReply);

      {
      if (FHeader.action <> 'GET')and(FHeader.action <> 'HEAD')and(FHeader.action <> 'POST') then
      begin
        // method not allowed, this server has no POST implementation
        fkeepalive:=False;
        SendStatusCode(405);
        Exit;
      end; }

      target := stringReplace(FHeader.url, '/./', '/', [rfReplaceAll]);
      target := stringReplace(target, '//', '/', [rfReplaceAll]);

      (*
      if not URLPathToAbsolutePath(target, '/', target) then
      begin
        fkeepalive:=False;
        SendStatusCode(400);
        Exit;
      end; *)

      if (length(Target)>0)and ( (Target[1] <> '/')or(pos('/../', target)>0)) then
      begin
        fkeepalive:=False;
        SendStatusCode(400);
        Exit;
      end;

      if FHost.IsForward(target, newtarget) then
      begin
        FReply.header.Add('Location', newtarget);
        SendStatusCode(301);
        Exit;
      end;

      p:=TEpollWorkerThread(FHost.GetCustomHandler(FHeader.url));
      if Assigned(p) then
      begin
        if not CanWebsocket then
          FVersion:=wvDelayedRequest;
        Relocate(p);
      end else
      if CanWebsocket then
      begin
        // ProcessWebsocket
        SendStatusCode(405);
      end
      else
        SendReply;
    end else
    begin
      fkeepalive:=false;
      SendStatusCode(400);
      Exit;
    end;
  except
    on E: Exception do
    begin
      dolog(llError, GetPeerName+': Exception in ProcessRequest: '+ string(E.Message));
      Close;
    end;
  end;
end;

procedure THTTPConnection.ProcessWebsocket;
var
  p: TEpollWorkerThread;
begin
  p:=TEpollWorkerThread(FHost.GetCustomHandler(FHeader.url));

  if Assigned(p) then
  begin
    UpgradeToWebsocket;
    Relocate(p);
  end else
  begin
    dolog(llDebug, 'Trying websocket but none is avail '+FHeader.url);
    SendStatusCode(404);
  end;
end;

procedure THTTPConnection.UpgradeToWebsocket;
var
  s,s2: string;

begin
  fkeepalive:=False;
  FIdletime:=FServer.Ticks;
  s := FHeader.header['Sec-WebSocket-Version'];

  Freply.header.add('Upgrade', 'WebSocket');
  Freply.header.add('Connection', 'Upgrade');

  s2 := FHeader.header['Sec-WebSocket-Protocol'];
  if pos(',', s2)>0 then
    Freply.header.Add('Sec-WebSocket-Protocol', Copy(s2, 1, pos(',', s2)-1))
  else if length(s2)>0 then
    Freply.header.Add('Sec-WebSocket-Protocol', s2);

  wsVersion := wvUnknown;
  if s = '' then
  begin
    // draft-ietf-hybi-thewebsocketprotocol-00 / hixie76 ?
    dolog(llNotice, GetPeerName+': Legacy Websocket Connect (Hixie76)');

    if (FHeader.header.Exists('Sec-WebSocket-Key1')<>-1) and
       (FHeader.header.Exists('Sec-WebSocket-Key2')<>-1) then
    begin
      wsVersion := wvHixie76; // yes.

      if FHeader.header.Exists('Origin')<>-1 then
        FReply.Header.Add('Sec-WebSocket-Origin', FHeader.header['Origin']);

      if FHeader.header.Exists('Host')<>-1 then
        if FHeader.parameters<>'' then
          FReply.Header.Add('Sec-WebSocket-Location', 'ws://' +FHeader.header['Host']+FHeader.url+'?'+FHeader.parameters)
        else
          FReply.Header.Add('Sec-WebSocket-Location', 'ws://' +FHeader.header['Host']+FHeader.url);

      if FHeader.Header.Exists('Sec-WebSocket-Protocol')<>-1 then
        FReply.Header.Add('Sec-WebSocket-Protocol', FHeader.header['Sec-WebSocket-Protocol']);

      s := MD5ofStr(ProcessHandshakeStringV0(FHeader.header['Sec-WebSocket-Key1']) +
                      ProcessHandshakeStringV0(FHeader.header['Sec-WebSocket-Key2']) + Copy(FInBuffer, 1, 8));

      s := FReply.Build('101 Switching protocols') + s;
      SendRaw(s);
      Delete(FInBuffer, 1, 8);
    end else
    begin
      dolog(llNotice, GetPeerName+': Unknown websocket handshake');
      Close;
    end;
  end else
  if s = '7' then
  begin
    // draft-ietf-hybi-thewebsocketprotocol-07
    dolog(llNotice, GetPeerName+': Legacy Websocket Connect (Hybi07)');
    wsVersion := wvHybi07;
  end else
  if s = '8' then
  begin
    // draft-ietf-hybi-thewebsocketprotocol-10
    dolog(llNotice, GetPeerName+': Legacy Websocket Connect (Hybi10)');
    wsVersion := wvHybi10;
  end else
  if s = '13' then
  begin
    // rfc6455
    wsVersion := wvRFC;
  end else
  begin
    dolog(llNotice, GetPeerName+': Unknown Websocket Version '+s+', dropping.');
    Close;
  end;

  { there are only minor differences between version 7, 8 & 13, it's basically
    the same handshake }
  if not (wsVersion in [wvUnknown, wvHixie76]) then
  begin
    Freply.header.Add('Sec-WebSocket-Accept', ProcessHandshakeString(FHeader.header['Sec-WebSocket-Key']));
    if FHeader.header.Exists('Sec-WebSocket-Protocol')<>-1 then
       Freply.header.Add('Sec-WebSocket-Protocol', FHeader.header['Sec-WebSocket-Protocol']);

    SendRaw(FReply.Build('101 Switching protocols'));
  end;
end;

procedure THTTPConnection.SendReply;
var
  ATarget, params: string;
  LastModified: TDateTime;
  FFile: string;
begin
  FPathUrl:='';

  if FHost.IsScriptDir(target, ATarget, params) then
  begin
    target:=ATarget;
    if FHeader.parameters<>'' then
      FHeader.parameters:=params + '?' + FHeader.parameters
    else
      FHeader.parameters:=params;
  end;

  if not URLPathToAbsolutePath(target, FHost.Path + 'web', FFile) then
  begin
    SendStatusCode(403);
    Exit;
  end;

  if (Length(target)>0) and (target[Length(Target)]='/') then
  begin
    FFile:=FHost.GetIndexPage(target);
    if FFile = '' then
    begin
      SendStatusCode(403);
      Exit;
    end;
  end else
  if DirectoryExists(FFile) then
  begin
    FReply.header.Add('Location', target+'/');
    SendStatusCode(301);
    Exit;
  end;

  if not FileExists(FFile) then
  begin
    SendStatusCode(404);
    Exit;
  end;

  LastModified := RecodeMilliSecond(FileLastModified(FFile), 0);
  Freply.header.Add('Last-Modified', DateTimeToHTTPTime(LastModified));

  if FHeader.header.Exists('If-Modified-Since')<>-1 then
  begin
    if HTTPTimeToDateTime(FHeader.header['If-Modified-Since']) = LastModified then
    begin
      Freply.header.Add('Expires', DateTimeToHTTPTime(IncSecond(Now, 1337)));
      SendRaw(Freply.Build('304 Not Modified'));
      Exit;
    end;
  end;

  if (FHeader.action <> 'GET') and (FHeader.action <> 'HEAD') then
  begin
    SendStatusCode(500);
    Exit;
  end;

  SendFile(GetFileMIMEType(FFile), FFile);

  (*
  if Assigned(FFile) then
  begin
    if (pos('gzip', FHeader.header['Accept-Encoding'])>0)and(Assigned(FFile.Gzipdata)) and
       (FHeader.RangeCount=0) then
    begin
      len:=FFIle.GZiplength;
      Data:=FFile.Gzipdata;
      FReply.Header.Add('Accept-Ranges', 'bytes');
      FReply.Header.Add('Vary', 'Accept-Encoding');
      FReply.Header.Add('Content-Encoding', 'gzip');
    end else
    begin
      len:=FFile.Filelength;
      Data:=FFile.Filedata;
    end;

    ARangeStart := 0;
    ARangeLen := len;

    if FHeader.RangeCount=1 then
    begin
      ARangeStart := FHeader.Range[0].min;
      ARangeLen := FHeader.Range[0].max;
      Freply.Header.Add('Content-range', 'bytes '+IntToStr(ARangeStart)+'-'+IntToStr(ARangeLen)+'/'+IntToStr(FFile.Filelength-1));

      if (ARangeStart>=FFile.Filelength) then
        ARangeStart:=FFile.FileLEngth-1;

      if ARangeStart+ARangeLen>FFile.FileLength then
        ARangeLen:=FFile.FileLength - ARangeStart;
    end;

    Setlength(s, ARangeLen - (ARangeStart));

    Move(PByteArray(Data)[ARangeStart], s[1], Length(s));

    Freply.header.Add('Expires', DateTimeToHTTPTime(IncSecond(Now, FFile.CacheLength)));
    if FHeader.RangeCount=1 then
      SendContent(FFile^.mimetype, s, '206 Partial Content')
    else
      SendContent(FFile^.mimetype, s);

    FHost.Files.Release(FFile);
  end else
  begin
    SendStatusCode(403);
    Exit;
  end;  *)
end;

procedure THTTPConnection.RelocateBack;
begin
  if Closed then
  begin
    dolog(llDebug, 'Relocating back when connection is terminated');
    Free;
    exit;
  end;
  if (FVersion in [wvDelayedRequest, wvNone]) then
  begin
    FVersion:=wvNone;
    OnDisconnect:=nil;
    OnWebsocketData:=nil;
    FServer.RelocateBack(self);
  end else
  begin
    dolog(llError, 'Internal error - should not be called in this state');
    Close;
  end;
end;

procedure THTTPConnection.SendStatusCode(const Code: Word);
var
  s, Title, Description, Host: string;
begin
  GetHTTPStatusCode(Code, Title, Description);
  Title:=string(IntToStr(Code))+' '+Title;
  if Assigned(FHost) then
    s:=FHost.GetCustomStatusPage(Code)
  else
    s:='';

  if s<>'' then
  begin
    SendFile(GetFileMIMEType(s), s, Title);
    Exit;
  end;

  Host:=FHeader.header['Host'];
  if Host = '' then
    Host:='chakraws';

  if Description = '' then
    Description:='No information available';

  SendContent('text/html', '<!DOCTYPE html>'#13#10+'<html>'#13#10+' <head>'#13#10+'  <title>'+Title+'</title>'#13#10+' </head>'#13#10+' <body>'#13#10+
              '  <h1>'+Title+'</h1>'#13#10+'  <p>'+Description+'</p>'+#13#10+
              '  <hr>'#13#10+'  <i>'+Host +' Server</i>'+
              ' </body>'#13#10+'</html>', Title);

end;


constructor THTTPConnection.Create(Server: TWebserver; ASocket: TSocket);
begin
  inherited Create(ASocket);
  FHeader:=THTTPRequest.Create;
  FReply:=THTTPReply.Create;
  FContentLength:=-1;
  FGotHeader:=False;

  FPingIdleTime:=15000; // milliseconds until ping is sent
  FMaxPongTime:=15000; // milliseconds until connection is closed with no pong reply
  FInBuffer:='';
  FServer:=Server;
  FIdletime:=FServer.Ticks;
end;

destructor THTTPConnection.Destroy;
begin
  Cleanup;
  FHeader.Free;
  FReply.Free;
  inherited Destroy;
end;

procedure THTTPConnection.Cleanup;
begin
  inherited;
  fkeepalive:=False;
  FIdletime:=FServer.Ticks;
  target:='';
  FWSData:='';
  FIdent:='';
  FContentLength:=-1;
  FPostData:='';
  FPathUrl:='';
  FGotHeader:=False;
  FOnWebsocketData:=nil;
  FOnPostData:=nil;
  FVersion:=wvNone;
  FTag:=nil;
  FWSData:='';
  FInBuffer:='';
  FLastPing:=0;
end;

procedure THTTPConnection.Dispose;
begin
  if Assigned(FServer) then
    FServer.FreeConnection(Self)
end;

function THTTPConnection.CanWebsocket: Boolean;
begin
  result:=(FHeader.Action = 'GET')and(FHeader.version = 'HTTP/1.1') and
          (((Pos('UPGRADE', UpperCase(FHeader.header['Connection']))>0) and
          (Uppercase(FHeader.header['Upgrade'])='WEBSOCKET')));
end;

function THTTPConnection.CheckTimeout: Boolean;
var s: string;
begin
  case FVersion of
    wvNone, wvUnknown:
    begin
      if longword(FServer.Ticks - FIdletime) > 30000 then
        Close;
    end;
    wvHixie76:
    begin
      begin
{$IFDEF HIXIE76_PING}
        if FIdletime = FPingIdleTime then
          SendWS('PING '+IntToStr(DateTimeToTimeStamp (Now).time));
        if longword(FServer.Ticks - FIdletime) > FMaxPongTime then
          FWantclose:=True;
{$ELSE}
       if longword(FServer.Ticks - FIdletime) > 60000 then
         Close;
{$ENDIF}
      end;
    end;
    else
    begin
      if (longword(FServer.Ticks - FIdleTime) > FPingIdleTime) and (FLastPing = 0) then
      begin
        FLastPing:=DateTimeToTimeStamp(Now).Time;
        s:=string(IntToStr(FLastPing));
        SendRaw(CreateHeader(9, length(s))+s);
        FIdleTime:=FServer.Ticks;
      end;
    end;
    if longword(FServer.Ticks - FIdletime) > FMaxPongTime then
      Close;
  end;
  result:=Wantclose;
end;

function THTTPConnection.GotCompleteRequest: Boolean;
var
  i: Integer;
begin
  result:=False;
  if (not FGotHeader) and (FContentLength <= 0) then
  begin
    for i:=Length(FInBuffer) downto 4 do
    if(FInBuffer[i]=#10)and(FInBuffer[i-1]=#13)and(FInBuffer[i-2]=#10)and(FInBuffer[i-3]=#13) then
    begin
      result:=True;
      FGotHeader:=FHeader.readstr(FInBuffer);
      if FGotHeader then
        FContentLength:=StrToIntDef(ansistring(FHeader.header['Content-Length']), 0);
      Exit;
    end;
  end else
  begin
    if FContentLength = -1 then
      FContentLength:=StrToIntDef(ansistring(FHeader.header['Content-Length']), 0);
    if FContentLength>0 then
    begin
      CheckMessageBody;
      if FContentLength = 0 then
        result:=GotCompleteRequest;
    end else
      result:=True;
  end;
end;

function THTTPConnection.IsExternalScript: Boolean;
begin
  result:=False;
end;

procedure THTTPConnection.ProcessHixie76;
var
  i: Integer;
  s: string;
begin
  while Length(FInBuffer)>0 do
  begin
    if FInbuffer[1]=#0 then
    begin
      i:=Pos(#255, FInBuffer);
      if i=0 then
        Exit;

      s:=Copy(FInBuffer, 2, i-2);
      Delete(FInBuffer, 1, i);
{$IFDEF HIXIE76_PING}
      if Pos('PONG ', s)=1 then
      begin
        Delete(s, 1, pos(' ', s));
        try
          FLag:=longword(DateTimeToTimeStamp(Now).time - (StrToInt(s)));
        except
        end;
      end else
{$ENDIF}
      if Assigned(FOnWebsocketData) then
        FOnWebsocketData(Self, s);
    end else
    begin
      dolog(llDebug, GetPeerName+': closing, Invalid packet');
      Close;
      Exit;
    end;
  end;
end;

function THTTPConnection.ReadRFCWebsocketFrame(out header: TWebsocketFrame; out
  HeaderSize: Integer): Boolean;
begin
  result:=False;
  HeaderSize:=2;
  header.fin := Ord(FInbuffer[1]) and 128 <> 0;
  header.RSV1 := Ord(FInbuffer[1]) and 64 <> 0;
  header.RSV2 := Ord(FInbuffer[1]) and 32 <> 0;
  header.RSV3 := Ord(FInbuffer[1]) and 16 <> 0;
  header.opcode := Ord(FInbuffer[1]) and 15;
  header.masked := Ord(FInbuffer[2]) and 128 <> 0;
  header.length := Ord(FInbuffer[2]) and 127;

  if header.length = 126 then
  begin
    if Length(FInbuffer)<2+HeaderSize then
      Exit;
    header.length:=Ord(FInbuffer[4])+Ord(FInbuffer[3])*256;
    HeaderSize:=4;
  end else if header.length = 127 then
  begin
    if Length(FInbuffer)<8+HeaderSize then
      Exit;
     header.length:=PInt64(@FInbuffer[3])^;
     HeaderSize:=10;
  end;
  if header.Masked then
  begin
    if Length(FInBuffer)<4+HeaderSize then
      Exit;
    header.Mask[0]:=Ord(FInbuffer[HeaderSize+1]);
    header.Mask[1]:=Ord(FInbuffer[HeaderSize+2]);
    header.Mask[2]:=Ord(FInbuffer[HeaderSize+3]);
    header.Mask[3]:=Ord(FInbuffer[HeaderSize+4]);
    inc(HeaderSize, 4);
  end;

  if header.opcode = 255 then
  begin
    Delete(FInbuffer, 1, HeaderSize);
    Exit;
  end;

  if Length(FInbuffer)<HeaderSize+header.Length then
    Exit;
  result:=True;
end;

procedure THTTPConnection.ProcessRFC;
var
  i, j: Integer;
  s: string;
  FrameHeader: TWebsocketFrame;
begin
  while Length(FInBuffer)>1 do
  begin
    if not ReadRFCWebsocketFrame(FrameHeader, j) then
      Exit;

    s:=Copy(FInBuffer, j+1, FrameHeader.length);
    Delete(FInBuffer, 1, j+FrameHeader.length);

    if FrameHeader.Masked then
    begin
      for i:=1 to FrameHeader.Length do
        s[i]:=AnsiChar(Byte(s[i]) xor FrameHeader.mask[(i-1) mod 4]);
    end else
    begin
      // only accept masked frames
      Close;
      Exit;
    end;

    case FrameHeader.opcode of
      254:
      begin
        // 254 error, 8 connection close
        Close;
        Exit;
      end;
      0:
      begin
        // continuation frame
        if not hassegmented then
        begin
          Close;
          Exit;
        end;

        FWSData:=FWSData  + Copy(FInBuffer, j+1, FrameHeader.Length);

        if FrameHeader.fin then
        begin
          hassegmented:=false;
          if Assigned(FOnWebsocketData) then
            FOnWebsocketData(Self, FWSDAta);
          fwsdata:='';
          // data received!
        end;
      end;
      1, 2:
      begin
        // 1 = text, 2 = binary
        if not FrameHeader.fin then
        begin
          if hasSegmented then
            Close;
          FWSData:=s;
          hasSegmented := true;
        end else
        begin
          // data received
          if Assigned(FOnWebsocketData) then
            FOnWebsocketData(Self, s);
        end;
      end;
      8:
      begin
        SendRaw(CreateHeader(FrameHeader.opcode, Length(s)) + s);
        Close;
      end;
      9: SendRaw(CreateHeader(10, Length(s)) + s);
      10:
      begin
        // pong
        try
          // edge doesn't include ping string?
          if s<>'' then
            FLag:=longword(DateTimeToTimeStamp (Now).time - StrToInt(ansistring(s)))
          else if FLastPing <> 0 then
            FLag:=DateTimeToTimeStamp(Now).Time - FLastPing;
          FLastPing:=0;
          //dolog(lldebug, 'got pong, lag '+IntToStr(FLag)+'ms');
        except
          on e: Exception do
          begin
            dolog(llError, GetPeerName+': send invalid pong reply ' + s + ' '+string(e.Message));
            Close;
          end;
        end;
      end;
    end;
  end;
end;

procedure THTTPConnection.AddCallback;
begin
  inherited AddCallback;
  if FInBuffer <> '' then
    ProcessData(nil, 0);
end;

procedure THTTPConnection.CheckMessageBody;
var
  finished: Boolean;
  s: string;
begin
  if FContentLength = -1 then
    FContentLength:=StrToIntDef(ansistring(FHeader.header['Content-Length']), 0);
  if FContentLength<=0 then
    Exit;

  if Assigned(FOnPostData) then
  begin
    finished:=Length(FInBuffer)>=FContentLength;
    if Length(FInBuffer)<=FContentLength then
    begin
      s:=FInBuffer;
      Dec(FContentLength, Length(FInBuffer));
      FInBuffer:='';
      FOnPostData(Self, s, finished);
    end else
    begin
      s:=Copy(FInBuffer, 1, FContentLength);
      Delete(FInBuffer, 1, FContentLength);
      FContentLength:=0;
      FOnPostData(Self, s, finished);
    end;
    if finished then
      FOnPostData:=nil;
  end else
  begin
    if Length(FInBuffer)<=FContentLength then
    begin
      Dec(FContentLength, Length(FInBuffer));
      FInBuffer:='';
    end else
    begin
      Delete(FInBuffer, 1, FContentLength);
      FContentLength:=0;
    end;
    if FContentLength = 0 then
      dolog(llWarning, GetPeerName+': Got unexpected message body for '+FHeader.action+' '+FHeader.url);
  end;
end;

procedure THTTPConnection.ProcessData(const Buffer: Pointer;
  BufferLength: Integer);
var
  i: Integer;
begin
  FIdletime:=FServer.Ticks;
  i:=Length(FInBuffer);
  Setlength(FInBuffer, i + BufferLength);
  Move(Buffer^, FInBuffer[i+1], BufferLength);

  case FVersion of
    wvNone:
    begin
      if GotCompleteRequest then
      begin
        ProcessRequest;
      end else
      if (not FGotHeader) and (Length(FInBuffer)>128*1024) then
      begin
        // 128kb of data and still no complete request (not counting postdata)
        SendStatusCode(400);
        Close;
      end;
    end;
    wvHixie76: ProcessHixie76();
    wvRFC, wvHybi07, wvHybi10: ProcessRFC();
    wvDelayedRequest: ;
    else begin
      dolog(llError, 'Unknown state in THTTPConnection.ProcessData');
      Close;
    end;
  end;
 end;

procedure THTTPConnection.SendWS(data: string; Flush: Boolean);
begin
  case FVersion of
    wvNone,
    wvUnknown: Exit;
    wvHixie76: SendRaw(#0+data+#255, Flush);
    else
      SendRaw(CreateHeader(1, length(data))+data, Flush);
  end;
end;

procedure THTTPConnection.SendContent(mimetype, data: string;
  result: string; Flush: Boolean);
begin
  if mimetype<>'' then
    freply.header.add('Content-Type', mimetype);
  freply.header.add('Content-Length', string(IntToStr(length(data))));

  if FHeader.action = 'HEAD' then
    SendRaw(freply.build(result), Flush)
  else
    SendRaw(freply.Build(result) + data, Flush);

  if Assigned(FOnPostData) then
  begin
    dolog(llError, GetPeerName+': Internal error - postdata callback still in place when it should not be');
    FOnPostData:=nil;
  end;

  if Flush then
    CheckMessageBody; // this is just a courtesy call to remove bogus post-data from our inbuffer

  if not FKeepAlive then
    Close;
end;

procedure THTTPConnection.SendFile(mimetype: string;
  FileName: string; result: string);
var
  F: File;
  Buffer: array[0..4096 - 1] of Byte;
  BytesRead: Integer;
begin
  Assignfile(F, FileName);
  {$i-}Reset(F, 1);{$i+}
  if ioresult <> 0 then
  begin
    SendStatusCode(403);
    Exit;
  end;
  try
    if mimetype<>'' then
      freply.header.add('Content-Type', mimetype);
    freply.header.add('Content-Length', string(IntToStr(FileSize(F))));

    if FHeader.action = 'HEAD' then
    begin
      SendRaw(freply.build(result), True);
      Exit;
    end;

    SendRaw(freply.Build(result), True);

    repeat
      BlockRead(F, Buffer, SizeOf(Buffer), BytesRead);
      if BytesRead > 0 then
      begin
        SendRaw(@Buffer[0], BytesRead, True);
      end;
    until BytesRead = 0;
  finally
    CloseFile(f);
    CheckMessageBody; // this is just a courtesy call to remove bogus post-data from our inbuffer
    if not FKeepAlive then
      Close;
  end;
end;

{ TWebserver }

procedure TWebserver.AddWorkerThread(AThread: TWebserverWorkerThread);
var
  i: Integer;
begin
  i:=Length(FWorker);
  Setlength(FWorker, i+1);
  FWorker[i]:=AThread;
end;

procedure TWebserver.RelocateBack(Connection: THTTPConnection);
begin
  try
    FCS.Enter;
    Connection.Relocate(FWorker[Random(Length(FWorker))]);
  finally
    FCS.Leave;
  end;
end;

constructor TWebserver.Create(const BasePath: string; IsTestMode: Boolean);
begin

  FTestMode:=IsTestMode;
  FCS:=TCriticalSection.Create;

  FSiteManager:=TWebserverSiteManager.Create(BasePath);
  fcurrthread:=0;
  FWorkerCount:=0;
  FTicks:=0;

  SetThreadCount(1);
end;

destructor TWebserver.Destroy;
var i: Integer;
begin
  for i:=0 to Length(FListener)-1 do
    FListener[i].Free;

  Setlength(FListener, 0);

  SetThreadCount(0);

  dolog(llNotice, 'Total connections accepted: '+string(IntToStr(FTotalConnections))
                 +', total requests processed: '+string(IntToStr(FTotalRequests)));
  FSiteManager.Destroy;

  for i:=0 to FCachedConnectionCount-1 do
    FCachedConnections[i].Free;

  FCS.Free;
  inherited Destroy;
end;

function TWebserver.SetThreadCount(Count: Integer): Boolean;
var
  i: Integer;
begin
  result:=False;

  if Count<0 then
    Exit;

  if FTestMode then
  begin
    result:=True;
    Exit;
  end;


  if Count < FWorkerCount then
  begin
    dolog(llDebug, 'Decimating threads from '+string(IntToStr(FWorkerCount))+' to '+string(IntToStr(Count)));
    for i:=Count to FWorkerCount-1 do
      FWorker[i].Terminate;

    for i:=Count to FWorkerCount-1 do
    begin
      FWorker[i].WaitFor;
      Inc(FTotalConnections, FWorker[i].TotalCount);
      FWorker[i].Free;
    end;
    Setlength(FWorker, Count);
    FWorkerCount:=Count;
  end else
  if Count > FWorkerCount then
  begin
    if FWorkerCount <> 0 then // surpress initial message
    dolog(llDebug, 'Increasing threads from '+string(IntToStr(FWorkerCount))+' to '+string(IntToStr(Count)));
    Setlength(FWorker, Count);
    for i:=FWorkerCount to Count-1 do
      FWorker[i]:=TWebserverWorkerThread.Create(Self);
    FWorkerCount:=Count;
  end;
end;

function TWebserver.AddListener(IP, Port: string): TWebserverListener;
var
  i: Integer;
begin
  if FTestMode then
  begin
    result:=nil;
    Exit;
  end;

  dolog(llNotice, 'Creating listener for '''+IP+':'+Port+'''');
  result:=TWebserverListener.Create(Self, IP, Port);
  FCS.Enter;
  try
    i:=Length(FListener);
    Setlength(FListener, i+1);
    FListener[i]:=result;
  finally
    FCS.Leave;
  end;
end;

function TWebserver.RemoveListener(Listener: TWebserverListener): Boolean;
var
  i: Integer;
begin
  result:=False;
  if not Assigned(FListener) then
    Exit;

  FCS.Enter;
  try
    for i:=0 to Length(FListener)-1 do
      if FListener[i] = Listener then
      begin
        FListener[i]:=FListener[Length(FListener)-1];
        Setlength(FListener, Length(FListener)-1);
        result:=True;
      end;
  finally
    FCS.Leave;
  end;
  if result then
  begin
    dolog(llNotice, 'Removing listener for '''+Listener.IP+':'+Listener.Port+'''');
    Listener.Free;
  end else
    dolog(llNotice, 'Could not remove listener for '''+Listener.IP+':'+Listener.Port+'''');
end;

const
  SendHelp: string = 'internal server error';

procedure TWebserver.Accept(Sock: TSocket);
var c: THTTPConnection;
begin
  if FWorkerCount = 0 then
  begin
    Send(Sock, @SendHelp[1], Length(SendHelp), 0);
    CloseSocket(Sock);
    Exit;
  end;

  FCS.Enter;
  try
    fcurrthread:=(fcurrthread+1) mod FWorkerCount;
    if FCachedConnectionCount>0 then
    begin
      dec(FCachedConnectionCount);
      c:=FCachedConnections[FCachedConnectionCount];
      FCachedConnections[FCachedConnectionCount]:=nil;
      c.FIdletime:=FTicks;
      c.ReAssign(Sock);
    end else
      c:=nil;
  finally
    FCS.Leave;
  end;
  if not Assigned(c) then
    c:=THTTPConnection.Create(Self, Sock);

  c.Relocate(FWorker[fcurrthread]);
end;

procedure TWebserver.FreeConnection(Connection: THTTPConnection);
begin
  if FCachedConnectionCount>=ConnectionCacheSize-1 then
  begin
    Connection.Free;
    Exit;
  end;
  Connection.Cleanup;

  FCS.Enter;
  try
    if FCachedConnectionCount<ConnectionCacheSize then
    begin
      FCachedConnections[FCachedConnectionCount]:=Connection;
      Inc(FCachedConnectionCount);
    end else
      Connection.Free;
  finally
    FCS.Leave;
  end;
end;

end.

