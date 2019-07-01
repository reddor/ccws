unit chakraevents;

{$i ccwssettings.inc}

interface

uses
  Classes,
  SysUtils,
  SyncObjs,
  contnrs,
  ChakraCommon,
  ChakraCore,
  ChakraCoreClasses,
  ChakraCoreUtils,
  chakrainstance,
  ChakraEventObject;


const
  EventBufferSize = 2048; // must be 2^n, otherwise bugs in wrap-around

type
  TEventListManager = class;

  TEventItem = record
    Name, Data: string;
  end;

  { TEventList }

  TEventList = class
  private
    FName: string;
    FRefCount: Integer;
    FEventReadPos, FEventWritePos: Longword;
    FEvents: array[0..EventBufferSize-1] of TEventItem;
  public
    constructor Create(Name: string);
    destructor Destroy; override;
    procedure AddEvent(const Name, Data: string);
    function GetEvent(var Position: Longword; var Name, Data: string): Boolean;
    function GetListenerPosition: Longword;
    property Name: string read FName;
    property RefCount: Integer read FRefCount write FRefCount;
  end;

  { TEventListManager }

  TEventListManager = class
  private
    FCS: TCriticalSection;
    FLists: TFPObjectHashTable;
  public
    constructor Create;
    destructor Destroy; override;
    function GetEventList(Name: string): TEventList;
    procedure ReleaseEventList(List: TEventList);
  end;

  { TChakraEventListener }

  { an eventlistener ecmascript-object that works across instances.

    Example:
    var foo = new EventList("bar"); }
  TChakraEventListener = class(TNativeRTTIEventObject)
  private
    FEvents: TEventList;
    FPosition: Longword;
    FDebug: string;
    FChakraInstance: TChakraInstance;
  protected
    procedure ProcessEvents;
  public
    constructor Create(Args: PJsValueRef = nil; ArgCount: Word = 0; AFinalize: Boolean = False); override;
    destructor Destroy; override;
  published
    function globalDispatch(Arguments: PJsValueRefArray; CountArguments: word): JsValueRef;
  end;

var
  EventListManager: TEventListManager;

implementation

uses
  logging;


{ TEventListManager }

constructor TEventListManager.Create;
begin
  FCS:=TCriticalSection.Create;
  FLists:=TFPObjectHashTable.Create(True);
end;

destructor TEventListManager.Destroy;
begin
  FLists.Free;
  FCS.Free;
  inherited Destroy;
end;

function TEventListManager.GetEventList(Name: string): TEventList;
begin
  result:=nil;
  FCS.Enter;
  try
    result:=TEventList(FLists[Name]);
    if not Assigned(result) then
    begin
      result:=TEventList.Create(Name);
      FLists[Name]:=result;
    end;
    Inc(result.FRefCount);
  finally
    FCS.Leave;
  end;
end;

procedure TEventListManager.ReleaseEventList(List: TEventList);
begin
  FCS.Enter;
  try
    Dec(List.FRefCount);
    if List.FRefCount<=0 then
    begin
      FLists.Delete(List.Name);
    end;
  finally
    FCS.Leave;
  end;
end;

{ TChakraEventListener }

destructor TChakraEventListener.Destroy;
begin
  if Assigned(FChakraInstance) then
  begin
    FChakraInstance.RemoveEventHandler(@ProcessEvents);
  end;
  if Assigned(FEvents) then
    EventListManager.ReleaseEventList(FEvents);
  inherited Destroy;
end;

function TChakraEventListener.globalDispatch(Arguments: PJsValueRefArray;
  CountArguments: word): JsValueRef;
begin
  result:=JsUndefinedValue;
  if CountArguments < 2 then
    raise Exception.Create('Argument expected');
  if Assigned(FEvents) then
    FEvents.AddEvent(
      JsStringToUTF8String(JsValueAsJsString(Arguments^[0])),
      JsStringToUTF8String(JsValueAsJsString(Arguments^[1]))
    );
end;

procedure TChakraEventListener.ProcessEvents;
var
  Name: string;
  Data: string;
  ev: TChakraEvent;
begin
  Name:='';
  Data:='';
  if Assigned(FEvents) then
  while FEvents.GetEvent(FPosition, Name, Data) do
  begin
    ev:=TChakraEvent.Create(Name, False);
    try
      JsSetProperty(ev.Instance, 'data', StringToJsString(Data));
      dispatchEvent(ev);
    except
      dolog(llError, 'Exception in ChakraEventListener dispatch');
    end;
    ev.Free;
  end;
end;

constructor TChakraEventListener.Create(Args: PJsValueRef; ArgCount: Word;
  AFinalize: Boolean);
begin
  if ArgCount<1 then
    raise Exception.Create('Argument expected');
  if ArgCount>1 then
    FDebug:=JsStringToUTF8String(JsValueAsJsString(Args[1]));

  inherited Create(Args, ArgCount, AFinalize);
  FChakraInstance:=(Context.Runtime as TChakraInstance);
  FChakraInstance.AddEventHandler(@ProcessEvents);
  FEvents:=EventListManager.GetEventList(JsStringToUTF8String(JsValueAsJsString(@Args^[0])));
  FPosition:=FEvents.GetListenerPosition;
end;

{ TEventList }

constructor TEventList.Create(Name: string);
begin
  FName:=name;
  FRefCount:=0;
  FEventReadPos:=0;
  FEventWritePos:=0;
end;

destructor TEventList.Destroy;
var
  i: Integer;
begin
  for i:=0 to Length(FEvents)-1 do
  begin
    FEvents[i].Name:='';
    FEvents[i].Data:='';
  end;
  inherited Destroy;
end;

procedure TEventList.AddEvent(const Name, Data: string);
var
  pos: Longword;
begin
  pos:=InterLockedIncrement(FEventWritePos);
  FEvents[(pos-1) mod EventBufferSize].Name:=Name;
  FEvents[(pos-1) mod EventBufferSize].Data:=Data;
  InterlockedIncrement(FEventReadPos);
end;

function TEventList.GetEvent(var Position: Longword; var Name, Data: string
  ): Boolean;
var
  l: Longword;
begin
  if Position < FEventReadPos then
  begin
    l:=Position mod EventBufferSize;
    Name:=FEvents[l].Name;
    Data:=FEvents[l].Data;
    Inc(Position);
    result:=True;
  end else
    result:=False;
end;

function TEventList.GetListenerPosition: Longword;
begin
  result:=FEventReadPos;
end;

initialization
  EventListManager:=TEventListManager.Create;
finalization
  EventListManager.Free;
end.

