unit ChakraRTTIObject;

{$ifdef FPC}
{$mode Delphi}
{$endif}
{$M+}

{$define LowercaseFirstLetter}
{.$define DebugUsage}

interface

uses
  Classes,
  SysUtils,
  typinfo,
  ChakraCommon,
  ChakraCore,
  ChakraCoreClasses,
  ChakraCoreUtils;

type
  TRTTIMethodCallback = procedure(AInstance: JsValueRef; name: string; Addr: Pointer) of object;

  { TNativeRTTIObject }
  TNativeRTTIObject = class(TNativeObject)
  private
    FThrowOnEnum: Boolean;
    FThrowOnRead: Boolean;
    FThrowOnWrite: Boolean;
    class procedure RegisterRTTIMethod(AInstance: JsValueRef; name: string; Addr: Pointer);
    class procedure UnregisterRTTIMethod(AInstance: JsValueRef; name: string; Addr: Pointer);
    class procedure EnumerateRTTIMethods(AInstance: JsValueRef; Callback: TRTTIMethodCallback);
  protected
    class function InitializePrototype(AConstructor: JsValueRef): JsValueRef; override;
    class procedure RegisterRttiProperty(AInstance: JsValueRef; PropInfo: PPropInfo);
    class procedure UnregisterRttiProperty(AInstance: JsValueRef; PropInfo: PPropInfo);
    class procedure RegisterProperties(AInstance: JsValueRef); override;
    class procedure RegisterMethods(AInstance: JsValueRef); override;
    procedure UnregisterProperties;
  public
    constructor Create(Args: PJsValueRef = nil; ArgCount: Word = 0; AFinalize: Boolean = False); override;
    destructor Destroy; override;
    property ThrowOnInvalidEnum: Boolean read FThrowOnEnum write FThrowOnEnum;
    property ThrowOnInvalidRead: Boolean read FThrowOnRead write FThrowOnRead;
    property ThrowOnInvalidWrite: Boolean read FThrowOnWrite write FThrowOnWrite;
  end;


{$ifdef DebugUsage}
procedure ChakraRTTIObjectDebugDump;
{$endif DebugUsage}

implementation

uses
  {$ifdef DebugUsage}
  syncobjs,
  contnrs,
  logging,
  {$endif DebugUsage}
  rttiutils;

type
  TRTTIGetSingleProc = function: single of object;
  TRTTIGetDoubleProc = function: double of object;
  TRTTIGetCompProc = function: comp of object;
  TRTTIGetCurrProc = function: currency of object;
  TRTTIGetExtendedProc = function: extended of object;
  TRTTIGetUInt8Proc = function: byte of object;
  TRTTIGetInt8Proc = function: shortint of object;
  TRTTIGetUInt16Proc = function: word of object;
  TRTTIGetInt16Proc = function: smallint of object;
  TRTTIGetUInt32Proc = function: longword of object;
  TRTTIGetInt32Proc = function: longint of object;
  TRTTIGetInt64Proc = function: int64 of object;
  TRTTIGetAnsiStringProc = function: ansistring of object;
  TRTTIGetWideStringProc = function: WideString of object;
  TRTTIGetUnicodeStringProc = function: UnicodeString of object;
  TRTTIGetClassProc = function: TObject of object;
  TRTTISetSingleProc = procedure(const Value: single) of object;
  TRTTISetDoubleProc = procedure(const Value: double) of object;
  TRTTISetCompProc = procedure(const Value: comp) of object;
  TRTTISetCurrProc = procedure(const Value: currency) of object;
  TRTTISetExtendedProc = procedure(const Value: extended) of object;
  TRTTISetUInt8Proc = procedure(const Value: byte) of object;
  TRTTISetInt8Proc = procedure(const Value: shortint) of object;
  TRTTISetUInt16Proc = procedure(const Value: word) of object;
  TRTTISetInt16Proc = procedure(const Value: smallint) of object;
  TRTTISetUInt32Proc = procedure(const Value: longword) of object;
  TRTTISetInt32Proc = procedure(const Value: longint) of object;
  TRTTISetInt64Proc = procedure(const Value: int64) of object;
  TRTTISetAnsistringProc = procedure(const Value: ansistring) of object;
  TRTTISetWidestringProc = procedure(const Value: WideString) of object;
  TRTTISetUnicodestringProc = procedure(const Value: UnicodeString) of object;
  TRTTISetClassProc = procedure(const Value: TObject) of object;

  (* type declarations taken from BESEN for class method enumeration *)
  {$ifdef fpc}
  PShortString = ^ShortString;
  {$endif}
  TMethodNameRec = packed record
  {$ifdef fpc}
    Name: PShortString;
    Address: pointer;
  {$else}
    Size: word;
    Address: pointer;
  {$ifdef NextGen}
    Name: TSymbolName;
  {$else}
    Name: ShortString;
  {$endif}
  {$endif}
  end;
  TMethodNameRecs = packed array[word] of TMethodNameRec;
  PMethodNameTable = ^TMethodNameTable;

  TMethodNameTable = packed record
    {$ifdef fpc}Count: longword;{$else}
    Count: word;
    {$endif}
    Methods: TMethodNameRecs;
  end;

{$ifdef DebugUsage}
var
  DebugCS: TCriticalSection;
  DebugInfo: TFPDataHashTable;

procedure IterateDebugInfoProc(Item: Pointer; const Key: string; var Continue: Boolean);
begin
  doLog(llDebug, Key + ': ' + IntToStr({%H-}PtrUint(Item)));
end;

procedure ChakraRTTIObjectDebugDump;
begin
  DebugCS.Enter;
  try
    doLog(llDebug, 'RTTI Object Dump:');
    DebugInfo.Iterate(@IterateDebugInfoProc);
    doLog(llDebug, '---');
  finally
    DebugCS.Leave;
  end;
end;

{$endif}

function GetIntValue(Target: Pointer; OrdType: TOrdType): Int64;
begin
  case OrdType of
    otSByte: Result := PShortInt(Target)^;
    otUByte: Result := PByte(Target)^;
    otSWord: Result := PSmallInt(Target)^;
    otUWord: Result := PWord(Target)^;
    otSLong: Result := PLongInt(Target)^;
    otULong: Result := PLongWord(Target)^;
    else
      Result := 0;
  end;
end;

function GetIntValueProc(Method: TMethod; OrdType: TOrdType): Int64;
begin
  case OrdType of
    otSByte: Result := TRTTIGetInt8Proc(Method)();
    otUByte: Result := TRTTIGetUInt8Proc(Method)();
    otSWord: Result := TRTTIGetInt16Proc(Method)();
    otUWord: Result := TRTTIGetUInt16Proc(Method)();
    otSLong: Result := TRTTIGetInt32Proc(Method)();
    otULong: Result := TRTTIGetUInt32Proc(Method)();
    else
      Result := 0;
  end;
end;

procedure SetIntValue(Target: Pointer; OrdType: TOrdType; Value: int64);
begin
  case OrdType of
    otSByte: PShortInt(Target)^ := Value;
    otUByte: PByte(Target)^ := Value;
    otSWord: PSmallInt(Target)^ := Value;
    otUWord: PWord(Target)^ := Value;
    otSLong: PLongInt(Target)^ := Value;
    otULong: PLongWord(Target)^ := Value;
  end;
end;

procedure SetIntValueProc(Method: TMethod; OrdType: TOrdType; Value: int64);
begin
  case OrdType of
    otSByte: TRTTISetInt8Proc(Method)(Value);
    otUByte: TRTTISetUInt8Proc(Method)(Value);
    otSWord: TRTTISetInt16Proc(Method)(Value);
    otUWord: TRTTISetUInt16Proc(Method)(Value);
    otSLong: TRTTISetInt32Proc(Method)(Value);
    otULong: TRTTISetUInt32Proc(Method)(Value);
  end;
end;

function BoolToInt(BoolValue: Boolean; IfTrue, IfFalse: Integer): Integer; inline;
begin
  if BoolValue then
    result:=IfTrue
  else
    result:=IfFalse
end;

function Native_PropGetCallback({%H-}Callee: JsValueRef; IsConstructCall: bool;
  Args: PJsValueRef; ArgCount: word; CallbackState: Pointer): JsValueRef;
 {$ifdef WINDOWS} stdcall;{$else} cdecl;
{$endif}
var
  PropInfo: PPropInfo;
  base: PByteArray;
  TypeData: PTypeData;
  Value: double;
  Offset: longword;
  Method: TMethod;
  obj: TObject;
  i: integer;
begin
  Result := JsUndefinedValue;
  try
    if IsConstructCall then
      raise Exception.Create('Property get accessor called as a constructor');

    if not Assigned(Args) or (ArgCount <> 1) then // thisarg
      raise Exception.Create('Invalid arguments');

    PropInfo := PPropInfo(CallbackState);
    base := JsGetExternalData(Args^);

    if not Assigned(PropInfo^.GetProc) then
    begin
      if TNativeRTTIObject(base).ThrowOnInvalidRead then
        raise Exception.Create('Property is not readable')
      else
      begin
        Result:=JsUndefinedValue;
        Exit;
      end;
    end;

    TypeData := GetTypeData(PropInfo^.PropType);

    Offset := {%H-}PtrUInt(PropInfo^.GetProc);
    if Offset <= $FFFF then
    begin
      case PropInfo^.PropType^.Kind of
        tkFloat:
        begin
          case TypeData^.FloatType of
            ftSingle: Value := PSingle(@base^[Offset])^;
            ftDouble: Value := PDouble(@base^[Offset])^;
            ftComp: Value := PComp(@base^[Offset])^;
            ftCurr: Value := PCurrency(@base^[Offset])^;
            ftExtended: Value := PExtended(@base^[Offset])^;
            else
              Value := 0;
          end;
          Result := DoubleToJsNumber(Value);
        end;
        tkInteger:
        begin
          Result := DoubleToJsNumber(GetIntValue(@Base^[Offset], TypeData^.OrdType));
        end;
        tkBool:
        begin
          if GetIntValue(@Base^[Offset], TypeData^.OrdType) <> 0 then
            Result := JsTrueValue
          else
            Result := JsFalseValue;
        end;
        tkInt64:
        begin
          Value := PInt64(@base^[offset])^;
          Result := DoubleToJsNumber(Value);
        end;
        tkAString,
        tkString:
        begin
          Result := StringToJsString(PAnsistring(@base^[Offset])^);
        end;
        tkWString:
        begin
          Result := StringToJsString(PWideString(@base^[offset])^);
        end;
        tkUString:
        begin
          Result := StringToJsString(PUnicodeString(@base^[offset])^);
        end;
        tkEnumeration:
        begin
          i := GetIntValue(@Base^[Offset], TypeData^.OrdType);
          Result := StringToJsString(GetEnumName(PropInfo^.PropType, i));
        end;
        tkClass:
        begin
          obj := TObject(PPointer(@base^[offset])^);
          if Assigned(obj) and (obj is TNativeObject) then
          begin
            Result := TNativeObject(obj).Instance;
          end
          else
            Result := JsNullValue;
        end
        else
          raise Exception.Create('Unsupported property type');
      end;
    end
    else
    begin
      Method.Data := base;
      Method.Code := PropInfo^.GetProc;
      case PropInfo^.PropType^.Kind of
        tkFloat:
        begin
          case TypeData^.FloatType of
            ftSingle: Value := TRTTIGetSingleProc(Method)();
            ftDouble: Value := TRTTIGetDoubleProc(Method)();
            ftComp: Value := TRTTIGetCompProc(Method)();
            ftCurr: Value := TRTTIGetCurrProc(Method)();
            ftExtended: Value := TRTTIGetExtendedProc(Method)();
            else
              Value := 0;
          end;
          Result := DoubleToJsNumber(Value);
        end;
        tkInteger:
        begin
          case TypeData^.OrdType of
            otSByte: Value := TRTTIGetInt8Proc(Method)();
            otUByte: Value := TRTTIGetUInt8Proc(Method)();
            otSWord: Value := TRTTIGetInt16Proc(Method)();
            otUWord: Value := TRTTIGetUInt16Proc(Method)();
            otSLong: Value := TRTTIGetInt32Proc(Method)();
            otULong: Value := TRTTIGetUInt32Proc(Method)();
            else
              Value := 0;
          end;
          Result := DoubleToJsNumber(Value);
        end;
        tkBool:
        begin
          case TypeData^.OrdType of
            otSByte: i := TRTTIGetInt8Proc(Method)();
            otUByte: i := TRTTIGetUInt8Proc(Method)();
            otSWord: i := TRTTIGetInt16Proc(Method)();
            otUWord: i := TRTTIGetUInt16Proc(Method)();
            otSLong: i := TRTTIGetInt32Proc(Method)();
            otULong: i := TRTTIGetUInt32Proc(Method)();
            else
              i := 0;
          end;
          if i <> 0 then
            Result := JsTrueValue
          else
            Result := JsFalseValue;
        end;
        tkInt64:
        begin
          Value := TRTTIGetInt64Proc(Method)();
          Result := DoubleToJsNumber(Value);
        end;
        TkAString,
        tkString:
        begin
          Result := StringToJSString(TRTTIGetAnsiStringProc(Method)());
        end;
        tkWString:
        begin
          Result := StringToJSString(TRTTIGetWideStringProc(Method)());
        end;
        tkUString:
        begin
          Result := StringToJSString(TRTTIGetUnicodeStringProc(Method)());
        end;
        tkEnumeration:
        begin
          case TypeData^.OrdType of
            otSByte: i := TRTTIGetInt8Proc(Method)();
            otUByte: i := TRTTIGetUInt8Proc(Method)();
            otSWord: i := TRTTIGetInt16Proc(Method)();
            otUWord: i := TRTTIGetUInt16Proc(Method)();
            otSLong: i := TRTTIGetInt32Proc(Method)();
            otULong: i := TRTTIGetUInt32Proc(Method)();
            else
              Value := 0;
          end;
          Result := StringToJsString(GetEnumName(TypeData^.ParentInfo, i));
        end;
        tkClass:
        begin
          obj := TRTTIGetClassProc(Method)();
          if Assigned(obj) and (obj is TNativeObject) then
          begin
            Result := TNativeObject(obj).Instance;
          end
          else
            Result := JsNullValue;
        end
        else
          raise Exception.Create('Unsupported property type');
      end;
    end;
  except
    on E: Exception do
      JsThrowError(WideFormat('[%s] %s', [E.ClassName, E.Message]));
  end;
end;

function Native_PropSetCallback({%H-}Callee: JsValueRef; IsConstructCall: bool;
  Args: PJsValueRefArray; ArgCount: word; CallbackState: Pointer): JsValueRef;
 {$ifdef WINDOWS} stdcall;{$else} cdecl;
{$endif}
var
  PropInfo: PPropInfo;
  base: PByteArray;
  TypeData: PTypeData;
  val: double;
  Offset: longword;
  Method: TMethod;
  i: integer;
begin
  Result := JsUndefinedValue;
  try
    if IsConstructCall then
      raise Exception.Create('Property set accessor called as a constructor');

    if not Assigned(Args) or (ArgCount <> 2) then // thisarg, value
      raise Exception.Create('Invalid arguments');

    PropInfo := PPropInfo(CallbackState);
    base := JsGetExternalData(Args^[0]);

    if not Assigned(PropInfo^.SetProc) then
    begin
      if TNativeRTTIObject(base).ThrowOnInvalidWrite then
        raise Exception.Create('Property is not writable')
      else
        Exit;
    end;

    TypeData := GetTypeData(PropInfo^.PropType);
    Offset := {%H-}PtrUInt(PropInfo^.GetProc);
    if Offset <= $FFFF then
    begin
      case PropInfo^.PropType^.Kind of
        tkFloat:
        begin
          val := JsNumberToDouble(Args^[1]);
          case TypeData^.FloatType of
            ftSingle: PSingle(@base^[Offset])^ := val;
            ftDouble: PDouble(@base^[Offset])^ := val;
            ftComp: PComp(@base^[Offset])^ := Round(val);
            ftCurr: PCurrency(@base^[Offset])^ := val;
            ftExtended: PExtended(@base^[Offset])^ := val;
          end;
        end;
        tkInteger:
        begin
          SetIntValue(@base^[offset], TypeData^.OrdType,
            Round(JsNumberToDouble(Args^[1])));
        end;
        tkBool:
        begin
          SetIntValue(@base^[offset], TypeData^.OrdType, BoolToInt(JsBooleanToBoolean(Args^[1]), 1, 0));
        end;
        tkInt64:
        begin
          PInt64(@base^[offset])^ := Round(val);
        end;
        tkAString,
        tkString:
        begin
          PAnsiString(@base^[Offset])^ := ansistring(JsStringToUnicodeString(Args^[1]));
        end;
        tkWString:
        begin
          PWideString(@base^[Offset])^ := WideString(JsStringToUnicodeString(Args^[1]));
        end;
        tkUString:
        begin
          PUnicodeString(@base^[Offset])^ := JsStringToUnicodeString(Args^[1]);
        end;
        tkEnumeration:
        begin
          i := GetEnumValue(PropInfo^.PropType, ansistring(
            JsStringToUnicodeString(JsValueAsJsString(Args^[1]))));
          if i = -1 then
          begin
            if TNativeRTTIObject(base).ThrowOnInvalidEnum then
              raise Exception.Create('Invalid enumerator value')
          end else
            SetIntValue(@base^[offset], TypeData^.OrdType, i);
        end;
        tkClass:
        begin
          PPointer(@base^[Offset])^ := JsGetExternalData(Args^[1]);
        end
        else
          raise Exception.Create('Unsupported property type');
      end;
    end
    else
    begin
      Method.Data := base;
      Method.Code := PropInfo^.SetProc;
      case PropInfo^.PropType^.Kind of
        tkFloat:
        begin
          val := JsNumberToDouble(JsValueAsJsNumber(Args^[1]));
          case TypeData^.FloatType of
            ftSingle: TRTTISetSingleProc(Method)(val);
            ftDouble: TRTTISetDoubleProc(Method)(val);
            ftComp: TRTTISetCompProc(Method)(Round(val));
            ftCurr: TRTTISetCurrProc(Method)(val);
            ftExtended: TRTTISetExtendedProc(Method)(val);
          end;
        end;
        tkInteger:
        begin
          SetIntValueProc(Method, TypeData^.OrdType, Round(JsNumberToDouble(JsValueAsJsNumber(Args^[1]))));
        end;
        tkBool:
        begin
          SetIntValueProc(Method, TypeData^.OrdType, BoolToInt(JsBooleanToBoolean(Args^[1]), 1, 0));
        end;
        tkInt64:
        begin
          TRTTISetInt64Proc(Method)(Round(val));
        end;
        tkAString,
        tkString:
        begin
          TRTTISetAnsistringProc(Method)(
            ansistring(JsStringToUnicodeString(JsValueAsJsString(Args^[1]))));
        end;
        tkWString:
        begin
          TRTTISetWidestringProc(Method)(
            WideString(JsStringToUnicodeString(JsValueAsJsString(Args^[1]))));
        end;
        tkUString:
        begin
          TRTTISetUnicodestringProc(Method)(
            JsStringToUnicodeString(JsValueAsJsString(Args^[1])));
        end;
        tkEnumeration:
        begin
          i := GetEnumValue(PropInfo^.PropType,
            ansistring(JsStringToUnicodeString(JsValueAsJsString(Args^[1]))));
          if i = -1 then
          begin
            if TNativeRTTIObject(base).ThrowOnInvalidEnum then
              raise Exception.Create('Invalid enumerator value')
          end else
            SetIntValueProc(Method, TypeData^.OrdType, i);
        end;
        tkClass:
        begin
          TRTTISetClassProc(Method)(TObject(JsGetExternalData(Args^[1])));
        end;
        else
          raise Exception.Create('Unsupported property type');
      end;
    end;
  except
    on E: Exception do
      JsThrowError(WideFormat('[%s] %s', [E.ClassName, E.Message]));
  end;
end;

{ TNativeRTTIObject }

class procedure TNativeRTTIObject.RegisterRTTIMethod(AInstance: JsValueRef;
  name: string; Addr: Pointer);
begin
  {$IFDEF LowercaseFirstLetter}
  if Length(Name)>0 then
    Name[1]:=LowerCase(Name[1]);
  {$ENDIF}
  RegisterMethod(AInstance, UTF8Decode(Name), Addr);
end;

function NullProc(callee: JsValueRef; isConstructCall: bool; arguments: PJsValueRef; argumentCount: Word;
    callbackState: Pointer): JsValueRef; {$ifdef WINDOWS}stdcall;{$else}cdecl;{$endif}
begin
  result:=JsUndefinedValue;
end;

class procedure TNativeRTTIObject.UnregisterRTTIMethod(AInstance: JsValueRef;
  name: string; Addr: Pointer);
begin
  //JsSetCallback(Instance: JsValueRef; const CallbackName: UnicodeString; Callback: JsNativeFunction;
  //  CallbackState: Pointer; UseStrictRules: Boolean = True): JsValueRef; overload;
  JsSetCallback(AInstance, name, @NullProc, nil);
end;

class procedure TNativeRTTIObject.EnumerateRTTIMethods(AInstance: JsValueRef;
  Callback: TRTTIMethodCallback);
var
  ClassRef: Pointer;
  MethodTable: PMethodNameTable;
  i: integer;
begin
  ClassRef:=Pointer(Self);
  while Assigned(ClassRef) do
  begin
    MethodTable := pointer({%H-}pointer({%H-}ptruint({%H-}ClassRef) + vmtMethodTable)^);
    if assigned(MethodTable) then
    begin
      for i := 0 to MethodTable^.Count - 1 do
      begin
        Callback(AInstance, MethodTable^.Methods[i].Name^, MethodTable^.Methods[i].Address);
      end;
    end;
    ClassRef:=pointer({%H-}pointer({%H-}ptruint({%H-}ClassRef) + vmtParent)^);
  end;
end;

class function TNativeRTTIObject.InitializePrototype(AConstructor: JsValueRef
  ): JsValueRef;
begin
  if Self.ClassParent = TNativeRTTIObject then
    Result := JsGetProperty(AConstructor, 'prototype')
  else
    Result := inherited InitializePrototype(AConstructor);
end;

class procedure TNativeRTTIObject.RegisterRttiProperty(AInstance: JsValueRef;
  PropInfo: PPropInfo);
var
  Descriptor: JsValueRef;
  PropName: UTF8String;
  PropId: JsPropertyIdRef;
  B: bytebool;
begin
  Descriptor := JsCreateObject;
  JsSetProperty(Descriptor, 'configurable', JsFalseValue, True);
  JsSetProperty(Descriptor, 'enumerable', JsTrueValue, True);
  JsSetCallback(Descriptor, 'get', JSNativeFunction(@Native_PropGetCallback),
    PropInfo, True);
  JsSetCallback(Descriptor, 'set', JSNativeFunction(@Native_PropSetCallback),
    PropInfo, True);
  PropName := UTF8Encode(PropInfo^.Name);
  if Pos('_', PropName) = 1 then
    Delete(PropName, 1, 1);
  {$IFDEF LowercaseFirstLetter}
  if Length(PropName)>0 then
    PropName[1]:=LowerCase(PropName[1]);
  {$ENDIF}
  ChakraCoreCheck(JsCreatePropertyId(PAnsiChar(PropName), Length(PropName), PropId));
  ChakraCoreCheck(JsDefineProperty(AInstance, PropId, Descriptor, B));
end;

class procedure TNativeRTTIObject.UnregisterRttiProperty(AInstance: JsValueRef;
  PropInfo: PPropInfo);
var
  Descriptor: JsValueRef;
  PropName: UTF8String;
  PropId: JsPropertyIdRef;
  B: bytebool;
begin
  Descriptor := JsCreateObject;
  JsSetProperty(Descriptor, 'configurable', JsFalseValue, True);
  JsSetProperty(Descriptor, 'enumerable', JsTrueValue, True);
  PropName := UTF8Encode(PropInfo^.Name);
  if Pos('_', PropName) = 1 then
    Delete(PropName, 1, 1);
  {$IFDEF LowercaseFirstLetter}
  if Length(PropName)>0 then
    PropName[1]:=LowerCase(PropName[1]);
  {$ENDIF}
  ChakraCoreCheck(JsCreatePropertyId(PAnsiChar(PropName), Length(PropName), PropId));
  ChakraCoreCheck(JsDefineProperty(AInstance, PropId, Descriptor, B));
end;

class procedure TNativeRTTIObject.RegisterProperties(AInstance: JsValueRef);
var
  i: integer;
  TypeData: PTypeData;
  PropList: PPropList;
begin
  inherited RegisterProperties(AInstance);
  TypeData := GetTypeData(Self.ClassInfo);
  Self.ClassInfo;
  if not Assigned(TypeData) then
    Exit;
  GetMem(PropList, TypeData^.PropCount * SizeOf(Pointer));
  try
    GetPropInfos(Self.ClassInfo, PropList);
    for i := 0 to TypeData^.PropCount - 1 do
    begin
      if PropList^[i]^.PropType^.Kind in [tkFloat, tkInteger, tkInt64,
        tkAString, tkWString, tkUString, tkEnumeration] then
      begin
        RegisterRttiProperty(AInstance, PropList^[i]);
      end
      else
      if PropList^[i]^.PropType^.Kind = tkClass then
      begin
        if GetTypeData(PropList^[i]^.PropType)^.ClassType.InheritsFrom(
          TNativeObject) then
          RegisterRttiProperty(AInstance, PropList^[i]);
      end;
    end;
  finally
    FreeMem(PropList);
  end;
end;

class procedure TNativeRTTIObject.RegisterMethods(AInstance: JsValueRef);
begin
  inherited RegisterMethods(AInstance);
  EnumerateRTTIMethods(AInstance, RegisterRTTIMethod);
end;

procedure TNativeRTTIObject.UnregisterProperties;
var
  i: integer;
  TypeData: PTypeData;
  PropList: PPropList;
begin
  TypeData := GetTypeData(Self.ClassInfo);
  Self.ClassInfo;
  if not Assigned(TypeData) then
    Exit;
  GetMem(PropList, TypeData^.PropCount * SizeOf(Pointer));
  try
    GetPropInfos(Self.ClassInfo, PropList);
    for i := 0 to TypeData^.PropCount - 1 do
    begin
      if PropList^[i]^.PropType^.Kind in [tkFloat, tkInteger, tkInt64,
        tkAString, tkWString, tkUString, tkEnumeration] then
      begin
        UnregisterRttiProperty(Instance, PropList^[i]);
      end
      else
      if PropList^[i]^.PropType^.Kind = tkClass then
      begin
        if GetTypeData(PropList^[i]^.PropType)^.ClassType.InheritsFrom(
          TNativeObject) then
        begin
          UnregisterRttiProperty(Instance, PropList^[i]);
        end;
      end;
    end;
  finally
    FreeMem(PropList);
  end;
end;

constructor TNativeRTTIObject.Create(Args: PJsValueRef; ArgCount: Word;
  AFinalize: Boolean);
begin
  inherited Create(Args, ArgCount, AFinalize);
  {$ifdef DebugUsage}
  DebugCS.Enter;
  try
    DebugInfo[ClassName]:={%H-}Pointer({%H-}PtrUInt(DebugInfo[ClassName]) + 1);
  finally
    DebugCS.Leave;
  end;
  {$endif DebugUsage}
  FThrowOnEnum:=True;
  FThrowOnRead:=True;
  FThrowOnWrite:=True;
end;

destructor TNativeRTTIObject.Destroy;
begin
  {$ifdef DebugUsage}
  DebugCS.Enter;
  try
    DebugInfo[ClassName]:={%H-}Pointer({%H-}PtrUInt(DebugInfo[ClassName]) - 1);
  finally
    DebugCS.Leave;
  end;
  {$endif DebugUsage}
  try
    EnumerateRTTIMethods(Instance, UnregisterRTTIMethod);
    UnregisterProperties;
  except
    // swallow exceptions that happen when the whole instance is destroyed..
  end;
  inherited Destroy;
end;

{$ifdef DebugUsage}
initialization
  DebugCS:=TCriticalSection.Create;
  DebugInfo:=TFPDataHashTable.Create;
finalization
  DebugCS.Free;
  DebugInfo.Free;
{$endif DebugUsage}
end.
