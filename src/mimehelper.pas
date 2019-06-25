unit mimehelper;

{$i ccwssettings.inc}

interface

function GetFileMIMEType(const FileName: string): string;
procedure OverwriteMimeType(FileExt: string; const NewType: string);

implementation

uses
  SysUtils,
  contnrs;

var
  MimeTypes: TFPStringHashTable;

procedure OverwriteMimeType(FileExt: string; const NewType: string);
begin
  if Pos('.', FileExt)=1 then
    delete(FileExt, 1, 1);
  MimeTypes.Items[ansistring(FileExt)]:=ansistring(NewType);
end;

function GetFileMIMEType(const FileName: string): string;
var
  ext: String;
begin
  ext:=ExtractFileExt(FileName);
  if Pos('.', ext)=1 then
    delete(ext, 1, 1);

  ext:=lowercase(ext);
  Result := string(MimeTypes.Items[ansistring(ext)]);
end;

procedure ReadMimeTypes;
var
  t: Textfile;
  s, a, b: string;
  i: Integer;
begin
  Assignfile(t, '/etc/mime.types');
  {$I-}Reset(t);{$I+}
  if ioresult=0 then
  begin
    while not eof(t) do
    begin
      readln(t, s);
      if Length(s)>0 then
       if s[1]<>'#' then
       begin
         i:=1;
         while (i<=Length(s))and(s[i]<>#9)and(s[i]<>' ') do
           inc(i);
         a:=trim(Copy(s, 1, i));
         b:=trim(Copy(s, i+1, length(s)));
         if (a<>'')and(b<>'') then
         begin
           while pos(' ', b)>0 do
           begin
             s:=Trim(copy(b, 1, pos(' ', b)));
             Delete(b, 1, Length(s)+1);
             MimeTypes[ansistring(s)]:=ansistring(a);
           end;
           MimeTypes[lowercase(ansistring(b))]:=ansistring(a);
         end;
       end;
    end;

    Closefile(t);
  end;
end;

initialization
  MimeTypes:=TFPStringHashTable.Create;
  try
    ReadMimeTypes;
  except

  end;
finalization
  MimeTypes.Free;
end.
 
