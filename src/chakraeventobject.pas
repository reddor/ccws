unit ChakraEventObject;

{$i ccwssettings.inc}

interface

uses
  Classes,
  SysUtils,
  ChakraCommon,
  ChakraCore,
  ChakraCoreClasses,
  ChakraCoreUtils,
  ChakraRTTIObject,
  contnrs;

type
    { TChakraEvent }

    TChakraEvent = class(TNativeRTTIObject)
    private
      FType: string;
    public
      constructor Create(Args: PJsValueRef = nil; ArgCount: Word = 0; AFinalize: Boolean = False); override; overload;
      constructor Create(EventType: string; AFinalize: Boolean=False); overload;
    published
      property _Type: string read FType;
    end;

    { TListenerGroup }

    TListenerGroup = class
    private
      FCallbacks: array of JsValueRef;
    public
      destructor Destroy; override;
      procedure Fire(Event: TChakraEvent; ThisObj: JsValueRef);
      procedure AddListener(Callback: JsValueRef);
      procedure RemoveListener(Callback: JsValueRef);
    end;

    { TNativeRTTIEventObject }

    TNativeRTTIEventObject = class(TNativeRTTIObject)
    private
      FListeners: TFPObjectHashTable;
      function addEventListener(Arguments: PJsValueRefArray; CountArguments: word): JsValueRef;
      function removeEventListener(Arguments: PJsValueRefArray; CountArguments: word): JsValueRef;
      function dispatchEvent(Arguments: PJsValueRefArray; CountArguments: word): JsValueRef;
    protected
      class function InitializePrototype(AConstructor: JsValueRef): JsValueRef; override;
      class procedure RegisterMethods(AInstance: JsValueRef); override;
    public
      constructor Create(Args: PJsValueRef = nil; ArgCount: Word = 0; AFinalize: Boolean = False); override;
      destructor Destroy; override;
    end;

implementation

{ TChakraEvent }

constructor TChakraEvent.Create(Args: PJsValueRef; ArgCount: Word;
  AFinalize: Boolean);
begin
  if ArgCount < 1 then
    raise Exception.Create('1 argument required');
  FType:=JsStringToUTF8String(JsValueAsJsString(Args^));
  inherited Create(Args, ArgCount, AFinalize);
end;

constructor TChakraEvent.Create(EventType: string; AFinalize: Boolean = False);
begin
  FType:=EventType;
  inherited Create(nil, 0, AFinalize);
end;

{ TListenerGroup }

destructor TListenerGroup.Destroy;
var
  i: Integer;
begin
  for i:=0 to Length(FCallbacks)-1 do
    JsRelease(FCallbacks[i]);
  Setlength(FCallbacks, 0);
  inherited Destroy;
end;

procedure TListenerGroup.Fire(Event: TChakraEvent; ThisObj: JsValueRef);
var
  i: Integer;
begin
  for i:=0 to Length(FCallbacks)-1 do
  begin
    JsCallFunction(FCallbacks[i], [Event.Instance], ThisObj);
  end;
end;

procedure TListenerGroup.AddListener(Callback: JsValueRef);
var
  i: Integer;
begin
  for i:=0 to Length(FCallbacks)-1 do
  if FCallbacks[i] = Callback then
    Exit;
  i:=Length(FCallbacks);
  Setlength(FCallbacks, i+1);
  FCallbacks[i]:=Callback;
  jsAddRef(Callback);
end;

procedure TListenerGroup.RemoveListener(Callback: JsValueRef);
var
  i, j: Integer;
begin
  for i:=0 to Length(FCallbacks)-1 do
  if FCallbacks[i] = Callback then
  begin
    for j:=i to Length(FCallbacks)-2 do
      FCallbacks[i]:=FCallbacks[i+1];
    Setlength(FCallbacks, Length(FCallbacks) - 1);
    jsRelease(Callback);
    Exit;
  end;
end;

{ TNativeRTTIEventObject }

class function TNativeRTTIEventObject.InitializePrototype(
  AConstructor: JsValueRef): JsValueRef;
begin
  if Self.ClassParent = TNativeRTTIEventObject then
    Result := JsGetProperty(AConstructor, 'prototype')
  else
    Result := inherited InitializePrototype(AConstructor);
end;

class procedure TNativeRTTIEventObject.RegisterMethods(AInstance: JsValueRef);
begin
  RegisterMethod(AInstance, 'addEventListener', @TNativeRTTIEventObject.addEventListener);
  RegisterMethod(AInstance, 'removeEventListener', @TNativeRTTIEventObject.removeEventListener);
  RegisterMethod(AInstance, 'dispatchEvent', @TNativeRTTIEventObject.dispatchEvent);
  inherited RegisterMethods(AInstance);
end;

constructor TNativeRTTIEventObject.Create(Args: PJsValueRef; ArgCount: Word;
  AFinalize: Boolean);
begin
  FListeners:=TFPObjectHashTable.Create(True);
  inherited Create(Args, ArgCount, AFinalize);
end;

destructor TNativeRTTIEventObject.Destroy;
begin
  FListeners.Free;
  inherited Destroy;
end;

function TNativeRTTIEventObject.addEventListener(Arguments: PJsValueRefArray;
  CountArguments: word): JsValueRef;
var
  group: TListenerGroup;
  s: string;
begin
  result:=JsUndefinedValue;
  if CountArguments < 2 then
    raise Exception.Create('2 arguments required');
  s:=JsStringToUTF8String(JsValueAsJsString(Arguments^[0]));
  if JsGetValueType(Arguments^[1]) <> JsFunction then
    raise Exception.Create('Second argument must be a function');
  group:=TListenerGroup(FListeners.Items[s]);
  if not Assigned(group) then
  begin
    group:=TListenerGroup.Create;
    FListeners.Items[s]:=group;
  end;
  group.AddListener(Arguments^[1]);
end;

function TNativeRTTIEventObject.removeEventListener(
  Arguments: PJsValueRefArray; CountArguments: word): JsValueRef;
var
  group: TListenerGroup;
  s: string;
begin
  result:=JsUndefinedValue;
  if CountArguments < 2 then
    raise Exception.Create('2 arguments required');
  s:=JsStringToUTF8String(JsValueAsJsString(Arguments^[0]));
  if JsGetValueType(Arguments^[1]) <> JsFunction then
    raise Exception.Create('Second argument must be a function');
  group:=TListenerGroup(FListeners.Items[s]);
  if Assigned(group) then
  begin
    group.RemoveListener(Arguments^[1]);
  end;
end;

function TNativeRTTIEventObject.dispatchEvent(Arguments: PJsValueRefArray;
  CountArguments: word): JsValueRef;
var
  group: TListenerGroup;
  o: TNativeObject;
begin
  result:=JsUndefinedValue;
  if CountArguments < 1 then
    raise Exception.Create('2 arguments required');
  o:=TNativeObject(JsGetExternalData(Arguments^[0]));
  if not Assigned(o) or not (o is TChakraEvent) then
    raise Exception.Create('Parameter 1 must be of type Event');
  group:=TListenerGroup(FListeners.Items[TChakraEvent(o)._Type]);
  if Assigned(group) then
  begin
    group.Fire(TChakraEvent(o), Instance);
  end;
end;

end.

