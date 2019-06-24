unit chakracoreinstance;

{$mode objfpc}{$H+}

interface

uses
  SysUtils,
  ChakraCoreVersion,
  ChakraCommon,
  ChakraCoreUtils,
  ChakraCoreClasses,
  filecache,
  webserverhosts,
  webserver;

type

  { TChakraCoreInstance }

  TChakraCoreInstance = class
  private
    FRuntime: TChakraCoreRuntime;
    FContext: TChakraCoreContext;
  public
    constructor Create(Manager: TWebserverSiteManager; Site: TWebserverSite; Thread: TThread = nil);
    destructor Destroy; override;
  end;

implementation

{ TChakraCoreInstance }

constructor TChakraCoreInstance.Create(Manager: TWebserverSiteManager;
  Site: TWebserverSite; Thread: TThread);
begin
  FRuntime:=TChakraCoreRuntime.Create;
  FContext:=TChakraCoreContext.Create(Runtime);
  Context.Activate();

end;

destructor TChakraCoreInstance.Destroy;
begin
  inherited Destroy;
end;

end.

