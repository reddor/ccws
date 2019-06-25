unit sslclass;

{$i ccwssettings.inc}

interface

uses
  Classes,
  SysUtils,
  Sockets;

type
  TAbstractSSLContext = class;

  { TAbstractSSLConnection }

  { TAbstractSSLSession }

  TAbstractSSLSession = class
  private
    FParent: TAbstractSSLContext;
  public
    constructor Create(AParent: TAbstractSSLContext);
    function Read(Buffer: Pointer; BufferSize: Integer): Integer; virtual; abstract;
    function Write(Buffer: Pointer; BufferSize: Integer): Integer; virtual; abstract;
    function WantWrite: Boolean; virtual; abstract;
    function WantClose: Boolean; virtual; abstract;

    property Parent: TAbstractSSLContext read FParent;
  end;

  { TAbstractSSLContext }

  TAbstractSSLContext = class
  public
    function Enable(const PrivateKeyFile, CertificateFile, CertPassword: string): Boolean; virtual; abstract;
    function StartSession(Socket: TSocket; LogPrefix: string): TAbstractSSLSession; virtual; abstract;
  end;

implementation

{ TAbstractSSLConnection }

constructor TAbstractSSLSession.Create(AParent: TAbstractSSLContext);
begin
  FParent:=AParent;
end;

end.

