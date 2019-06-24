unit xmlhttprequest;

{$mode delphi}

interface

uses
  Classes,
  SysUtils,
  ChakraCommon,
  ChakraCoreClasses,
  ChakraCoreUtils,
  ChakraRTTIObject,
  chakrainstance,
  blcksock,
  httprequest;

type
  { TXMLHttpRequest }
  TXMLHttpRequest = class(TNativeRTTIObject)
  private
    FOnError: JsValueRef;
    FRequest: THTTPRequestThread;
    FOnReadyStateChange: JsValueRef;
    FReadyState: longword;
    FResponse: UnicodeString;
    FStatus: longword;
    FStatusText: UnicodeString;
    FSynchronous: boolean;
    FTimeout: longword;
    procedure RequestError(Sender: TObject; {%H-}ErrorType: THTTPRequestError;
      const Message: ansistring);
    procedure RequestResponse(Sender: TObject; const ResponseCode, Data: ansistring);
    function RequestForward(Sender: TObject; var {%H-}newUrl: ansistring): boolean;
    function RequestSent(Sender: TObject; {%H-}Socket: TTCPBlockSocket): boolean;
    function RequestHeadersReceived(Sender: TObject): boolean;
    function RequestLoading(Sender: TObject): boolean;
    function RequestConnect(Sender: TObject; {%H-}Host, {%H-}Port: ansistring): boolean;
  protected
    procedure DoFire(Func: TCallbackProc);
    procedure FireError;
    procedure FireReadyChange;
    procedure FireReadyChangeOpened;
    procedure FireReadyChangeHeadersReceived;
    procedure FireReadyChangeLoading;
    procedure FireReadyChangeDone;

    //procedure InitializeObject; override;
    function DoConnect(Method, Url: ansistring): boolean;
  public
    constructor Create(Args: PJsValueRef = nil; ArgCount: Word = 0; AFinalize: Boolean = False); override;
    destructor Destroy; override;
  published
    function abort({%H-}Args: PJsValueRef; {%H-}ArgCount: word): JsValueRef;
    function getAllResponseHeaders({%H-}Args: PJsValueRef;
    {%H-}ArgCount: word): JsValueRef;
    function open(Args: PJsValueRefArray; ArgCount: word): JsValueRef;
    function overrideMimeType({%H-}Args: PJsValueRef; {%H-}ArgCount: word): JsValueRef;
    function send(Args: PJsValueRef; ArgCount: word): JsValueRef;
    function setRequestHeader(Args: PJsValueRefArray; ArgCount: word): JsValueRef;
    function getResponseHeader(Args: PJsValueRef; ArgCount: word): JsValueRef;

    property readyState: longword read FReadyState;
    property response: UnicodeString read FResponse;
    property responseText: UnicodeString read FResponse;
    property status: longword read FStatus;
    property statusText: UnicodeString read FStatusText;
    property timeout: longword read FTimeout write FTimeout;
    property synchronous: boolean read FSynchronous write FSynchronous;
  end;

implementation

uses
  sockets;

{ TXMLHttpRequest }


function TXMLHttpRequest.DoConnect(Method, Url: ansistring): boolean;
begin
  Result := False;
  if Assigned(FRequest) then
    Exit;

  FRequest := THTTPRequestThread.Create(Method, url, True);
  FRequest.OnError := RequestError;
  FRequest.OnForward := RequestForward;
  FRequest.OnResponse := RequestResponse;
  FRequest.OnRequestSent := RequestSent;
  FRequest.OnHeadersReceived := RequestHeadersReceived;
  FRequest.OnLoading := RequestLoading;
  FRequest.OnConnect := RequestConnect;

  FTimeout := Round(JsNumberToDouble(JsGetProperty(Instance, 'timeout')));

  if FTimeout = 0 then
    FRequest.TimeOut := 60000
  else
    FRequest.TimeOut := FTimeout;

  FRequest.Start;
end;

constructor TXMLHttpRequest.Create(Args: PJsValueRef; ArgCount: Word;
  AFinalize: Boolean);
begin
  inherited Create(Args, ArgCount, AFinalize);
  FSynchronous := False;
end;

destructor TXMLHttpRequest.Destroy;
begin
  if Assigned(FRequest) then
  begin
    FRequest.OnError := nil;
    FRequest.OnForward := nil;
    FRequest.OnResponse := nil;
    if not FRequest.Finished then
    begin
      FRequest.FreeOnTerminate := True;
    end
    else
      FRequest.Free;
    FRequest := nil;
  end;
  inherited Destroy;
end;

procedure TXMLHttpRequest.RequestError(Sender: TObject;
  ErrorType: THTTPRequestError; const Message: ansistring);
begin
  FStatusText := UnicodeString(Message);
  DoFire(FireError);
end;

procedure TXMLHttpRequest.RequestResponse(Sender: TObject;
  const ResponseCode, Data: ansistring);
begin
  FStatus := StrToIntDef(Copy(ResponseCode, 1, Pos(' ', ResponseCode) - 1), 0);
  FStatusText := UnicodeString(ResponseCode);
  FResponse := UnicodeString(Data);
  DoFire(FireReadyChangeDone);
end;

function TXMLHttpRequest.RequestForward(Sender: TObject;
  var newUrl: ansistring): boolean;
begin
  Result := True;
end;

function TXMLHttpRequest.RequestSent(Sender: TObject; Socket: TTCPBlockSocket): boolean;
begin
  Result := True;
end;

function TXMLHttpRequest.RequestHeadersReceived(Sender: TObject): boolean;
begin
  DoFire(FireReadyChangeHeadersReceived);
  Result := True;
end;

function TXMLHttpRequest.RequestLoading(Sender: TObject): boolean;
begin
  DoFire(FireReadyChangeLoading);
  Result := True;
end;

function TXMLHttpRequest.RequestConnect(Sender: TObject;
  Host, Port: ansistring): boolean;
begin
  DoFire(FireReadyChangeOpened);
  Result := True;
end;

procedure TXMLHttpRequest.DoFire(Func: TCallbackProc);
begin
  TChakraInstance(Context.Runtime).Callback(Func);
end;

procedure TXMLHttpRequest.FireError;
begin
  try
    FOnError := JsGetProperty(Instance, 'onerror');
    if Assigned(FOnError) and (JsGetValueType(FOnError) = JsFunction) then
      JsCallFunction(FOnError, [])
  except
    on e: Exception do
    begin
      TChakraInstance(Context.Runtime).OutputException(e, 'XMLHTTPRequest.onerror');
    end;
  end;
end;

procedure TXMLHttpRequest.FireReadyChange;
begin
  try
    FOnReadyStateChange := JsGetProperty(Instance, 'onreadystatechange');
    if Assigned(FOnReadyStateChange) and (JsGetValueType(FOnReadyStateChange) =
      JsFunction) then
      JsCallFunction(FOnReadyStateChange, [Instance])
  except
    on e: Exception do
    begin
      TChakraInstance(Context.Runtime).OutputException(e,
        'XMLHTTPRequest.onreadystatechange');
    end;
  end;
end;

procedure TXMLHttpRequest.FireReadyChangeOpened;
begin
  FReadyState := 1;
  FireReadyChange;
end;

procedure TXMLHttpRequest.FireReadyChangeHeadersReceived;
begin
  FReadyState := 2;
  FireReadyChange;
end;

procedure TXMLHttpRequest.FireReadyChangeLoading;
begin
  FReadyState := 3;
  FireReadyChange;
end;

procedure TXMLHttpRequest.FireReadyChangeDone;
begin
  FReadyState := 4;
  FireReadyChange;
end;

function TXMLHttpRequest.abort(Args: PJsValueRef; ArgCount: word): JsValueRef;
begin
  Result := JsUndefinedValue;
  if Assigned(FRequest) then
    FRequest.Abort;
end;

function TXMLHttpRequest.getAllResponseHeaders(Args: PJsValueRef;
  ArgCount: word): JsValueRef;
begin
  if (FReadyState >= 2) and Assigned(FRequest) then
    Result := StringToJsString(UnicodeString(FRequest.GetAllResponseHeaders))
  else
    Result := JsUndefinedValue;
end;

function TXMLHttpRequest.getResponseHeader(Args: PJsValueRef;
  ArgCount: word): JsValueRef;
begin
  if (FReadyState >= 2) and Assigned(FRequest) and (ArgCount > 0) then
    Result := StringToJsString(UnicodeString(FRequest.GetResponseHeader(
      ansistring(JsStringToUnicodeString(Args^)))))
  else
    Result := JsUndefinedValue;
end;

function TXMLHttpRequest.open(Args: PJsValueRefArray; ArgCount: word): JsValueRef;

begin
  Result := JsNullValue;
  if ArgCount < 2 then
    Exit;

  DoConnect(ansistring(JsStringToUnicodeString(Args^[0])),
    ansistring(JsStringToUnicodeString(Args^[1])));
  Result := JsTrueValue;
end;

function TXMLHttpRequest.overrideMimeType(Args: PJsValueRef;
  ArgCount: word): JsValueRef;
begin
  Result := JsUndefinedValue;
end;

function TXMLHttpRequest.send(Args: PJsValueRef; ArgCount: word): JsValueRef;
begin
  Result := JsUndefinedValue;
  if (FReadyState <= 1) and Assigned(FRequest) then
  begin
    if ArgCount > 0 then
      FRequest.Send(ansistring(JsStringToUnicodeString(Args^)))
    else
      FRequest.Send('');
    if FSynchronous then
    begin
      FRequest.WaitFor;
    end;
  end;
end;

function TXMLHttpRequest.setRequestHeader(Args: PJsValueRefArray;
  ArgCount: word): JsValueRef;
begin
  Result := JsUndefinedValue;
  if (FReadyState <= 1) and Assigned(FRequest) and (ArgCount > 1) then
    FRequest.SetRequestHeader(
      ansistring(JsStringToUnicodeString(Args^[0])),
      ansistring(JsStringToUnicodeString(Args^[1])));
end;

end.
