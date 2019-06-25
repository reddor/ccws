unit chakraevents;

{$i ccwssettings.inc}

interface

uses
  Classes,
  SysUtils,
  SyncObjs,
  contnrs,
  chakrainstance,
  ChakraCommon,
  ChakraCore,
  ChakraRTTIObject;


const
  EventBufferSize = 2048; // must be 2^n, otherwise bugs in wrap-around

type
  TEventListManager = class;

  TEventItem = record
    Name, Data: widestring;
  end;

  { TEventList }

  TEventList = class
  private
    FName: widestring;
    FRefCount: Integer;
    FEventReadPos, FEventWritePos: Longword;
    FEvents: array[0..EventBufferSize-1] of TEventItem;
  public
    constructor Create(Name: widestring);
    procedure AddEvent(const Name, Data: widestring);
    function GetEvent(var Position: Longword; var Name, Data: widestring): Boolean;
    function GetListenerPosition: Longword;
    property Name: widestring read FName;
  end;

  { TEventListManager }

  TEventListManager = class
  private
    FCS: TCriticalSection;
    FLists: TFPDataHashTable;
  public
    constructor Create;
    destructor Destroy; override;
    function GetEventList(Name: widestring): TEventList;
    procedure ReleaseEventList(List: TEventList);
  end;

  TChakraEventListener = class;

  { TChakraEventEntries }

  TChakraEventEntries = class
  private
    FParent: TChakraEventListener;
    FInstance: TChakraInstance;
    //FEntries: array of TBESENObjectFunction;
  public
    constructor Create(Parent: TChakraEventListener; Instance: TChakraInstance);
    destructor Destroy; override;
    //procedure Add(Func: TBESENObjectFunction);
    procedure Fire(const Data: UnicodeString);
  end;

  { TChakraEventListener }

  { an eventlistener ecmascript-object that works across instances.

    Example:
    var foo = new EventList("bar"); }
  TChakraEventListener = class(TNativeRTTIObject)
  private
    FEvents: TEventList;
    FListeners: TFPDataHashTable;
    FPosition: Longword;
  protected
    procedure ProcessEvents;
    //procedure ConstructObject(const ThisArgument:TBESENValue;Arguments:PPBESENValues;CountArguments:integer); override;
    //procedure InitializeObject; override;
    //procedure FinalizeObject; override;
    Procedure ClearItems(Item: Pointer; const Key: ansistring; var Continue: Boolean);
  public
    destructor Destroy; override;
  published
    { addEventListener(eventName, callback) - adds a listener entry. callback = function(data) }
    //procedure addEventListener(const ThisArgument:TBESENValue;Arguments:PPBESENValues;CountArguments:integer;var ResultValue:TBESENValue);
    { fireEvent(eventName, data) - fires an event. "data" must be of type string, as the
      event will be fired accross multiple script instances }
    //procedure fireEvent(const ThisArgument:TBESENValue;Arguments:PPBESENValues;CountArguments:integer;var ResultValue:TBESENValue);
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
  FLists:=TFPDataHashTable.Create;
end;

destructor TEventListManager.Destroy;
begin
  FLists.Free;
  FCS.Free;
  inherited Destroy;
end;

function TEventListManager.GetEventList(Name: widestring): TEventList;
begin
  result:=nil;
  (*
  FCS.Enter;
  try
    n:=BESENUTF16ToUTF8(Name);
    result:=FLists[n];
    if not Assigned(result) then
    begin
      result:=TEventList.Create(Name);
      FLists[n]:=result;
    end;
    Inc(result.FRefCount);
  finally
    FCS.Leave;
  end; *)
end;

procedure TEventListManager.ReleaseEventList(List: TEventList);
begin
  (*
  FCS.Enter;
  try
    Dec(List.FRefCount);
    if List.FRefCount<=0 then
    begin
      FLists.Delete(BESENUTF16ToUTF8(List.Name));
      List.Free;
    end;
  finally
    FCS.Leave;
  end; *)
end;

{ TChakraEventListener }

(*
procedure TChakraEventListener.ConstructObject(const ThisArgument: TBESENValue;
  Arguments: PPBESENValues; CountArguments: integer);
begin
  if CountArguments<1 then
    raise EBESENError.Create('Identifier expected');

  TBESENInstance(Instance).AddEventHandler(ProcessEvents);

  if not Assigned(FEvents) then
  begin
    FEvents:=EventListManager.GetEventList(TBESEN(Instance).ToStr(Arguments^[0]^));
    FPosition:=FEvents.GetListenerPosition;
  end;
end;

procedure TChakraEventListener.InitializeObject;
begin
  if not Assigned(FListeners) then
    FListeners:=TFPDataHashTable.Create;
  inherited InitializeObject;
end;

procedure TChakraEventListener.FinalizeObject;
begin
  if Assigned(FEvents) then
  begin
    //if Assigned(TBESEN(Instance).Tag) then
    TBESENInstance(Instance).RemoveEventHandler(ProcessEvents);

    EventListManager.ReleaseEventList(FEvents);
    FEvents:=nil;
  end;
  if Assigned(FListeners) then
  begin
    FListeners.Iterate(ClearItems);
    FListeners.Free;
    FListeners:=nil;
  end;
  inherited FinalizeObject;
end;     *)

procedure TChakraEventListener.ClearItems(Item: Pointer; const Key: ansistring;
  var Continue: Boolean);
begin
  Continue:=True;
  if Assigned(Item) then
  begin
    if TObject(Item) is TChakraEventEntries then
    begin
      TChakraEventEntries(Item).Free;
    end;
  end;
end;

destructor TChakraEventListener.Destroy;
begin
  inherited Destroy;
end;

procedure TChakraEventListener.ProcessEvents;
var
  Name, Data: widestring;
  p: TChakraEventEntries;
begin
  if Assigned(FEvents) then
  while FEvents.GetEvent(FPosition, Name, Data) do
  begin
    p:=TChakraEventEntries(FListeners[ansistring(Name)]);
    if Assigned(p) then
      p.Fire(Data);
  end;
end;

(*
procedure TChakraEventListener.addEventListener(const ThisArgument: TBESENValue;
  Arguments: PPBESENValues; CountArguments: integer;
  var ResultValue: TBESENValue);
var
  Name: ansistring;
  o: TBESENObject;
  p: TChakraEventEntries;
begin
  ResultValue:=BESENUndefinedValue;

  if CountArguments<2 then
    Exit;

  Name:=ansistring(TBESEN(Instance).ToStr(Arguments^[0]^));
  o:=TBESEN(Instance).ToObj(Arguments^[1]^);

  if not (o is TBESENObjectFunction) then
    raise EBESENError.Create('Function expected');

  p:=TChakraEventEntries(FListeners[Name]);
  if not Assigned(p) then
  begin
    p:=TChakraEventEntries.Create(Self, TBESEN(Instance));
    FListeners[Name]:=p;
  end;
  p.Add(TBESENObjectFunction(o));
  ResultValue:=BESENBooleanValue(True);
end;

procedure TChakraEventListener.fireEvent(const ThisArgument: TBESENValue;
  Arguments: PPBESENValues; CountArguments: integer;
  var ResultValue: TBESENValue);
var
  Name, Data: TBESENString;
begin
  ResultValue:=BESENUndefinedValue;

  if CountArguments<2 then
    Exit;

  Name:=TBESEN(Instance).ToStr(Arguments^[0]^);

  if Arguments^[1]^.ValueType = bvtOBJECT then
  begin
    Data:=TBESEN(Instance).ToStr(TBESEN(Instance).JSONStringify(Arguments^[1]^));
  end else
    Data:=TBESEN(Instance).ToStr(Arguments^[1]^);

  if Assigned(FEvents) then
    FEvents.AddEvent(Name, Data);

  ResultValue:=BESENBooleanValue(True);
end;          *)

{ TChakraEventEntries }

constructor TChakraEventEntries.Create(Parent: TChakraEventListener;
  Instance: TChakraInstance);
begin
  FParent:=Parent;
  FInstance:=Instance;
  // Setlength(FEntries, 0);
end;

destructor TChakraEventEntries.Destroy;
begin
  (*
  if not TBESENInstance(FInstance).ShuttingDown then
  for i:=0 to Length(FEntries)-1 do
  begin
    FInstance.GarbageCollector.Unprotect(FEntries[i]);
  end;
  Setlength(FEntries, 0); *)
  inherited Destroy;
end;

(*
procedure TChakraEventEntries.Add(Func: TBESENObjectFunction);
var
  i: Integer;
begin
  FInstance.GarbageCollector.Protect(Func);
  i:=Length(FEntries);
  Setlength(FEntries, i+1);
  FEntries[i]:=Func;
end;   *)

procedure TChakraEventEntries.Fire(const Data: UnicodeString);
begin (*
var
  i: Integer;
  val: TBESENValue;
  pval: PBESENValue;
  Result: TBESENValue;
begin
  pval:=@val;
  val:=BESENStringValue(Data);

  for i:=0 to Length(FEntries)-1 do
  try
    FEntries[i].Call(BESENObjectValue(FParent), @pval, 1, Result);
  except
    on e: Exception do
      TBESENInstance(FInstance).OutputException(e, 'Event');
  end;  *)
end;

{ TEventList }

constructor TEventList.Create(Name: widestring);
begin
  FName:=name;
  FRefCount:=0;
  FEventReadPos:=0;
  FEventWritePos:=0;
end;

procedure TEventList.AddEvent(const Name, Data: widestring);
var
  pos: Longword;
begin
  pos:=InterLockedIncrement(FEventWritePos) mod EventBufferSize;
  FEvents[pos-1].Name:=Name;
  FEvents[pos-1].Data:=Data;
  InterlockedIncrement(FEventReadPos);
end;

function TEventList.GetEvent(var Position: Longword; var Name, Data: widestring
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

