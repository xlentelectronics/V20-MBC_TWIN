module TW22MOD1;

const
  MaxFiles = 150;

type
  Str2       = string[2];
  Str8       = string[8];
  Str12      = string[12];
  Str16      = string[16];
  Str80      = string[80];
  ByteArr36  = array[0..35] of byte;
  ByteArr128 = array[0..127] of byte;

var
  Files      : external array[1..2, 1..MaxFiles] of Str12;
  FileSizes  : external array[1..2, 1..MaxFiles] of integer;
  FileCount  : external array[1..2] of integer;
  DriveNo    : external array[1..2] of integer;
  Selected   : external array[1..2] of integer;
  FirstLine  : external array[1..2] of integer;
  Truncated  : external array[1..2] of boolean;
  SearchFCB  : external ByteArr36;
  DirDMA     : external ByteArr128;
  Rows       : external integer;
  ESC        : external char;
  Dummy      : external integer;

external function BDOS(func: integer; parm: integer): integer;

procedure AnsiGotoXY(X, Y: integer);
begin
  write(ESC, '[', Y:1, ';', X:1, 'H')
end;

procedure ClrScr;
begin
  write(ESC, '[2J', ESC, '[H')
end;

procedure ClrEol;
begin
  write(ESC, '[K')
end;

procedure NormVideo;
begin
  write(ESC, '[0m')
end;

procedure ReadKbd(var ch: char);
var
  res: integer;
begin
  repeat
    res := BDOS(6, 255)
  until res <> 0;
  ch := chr(res & 127)
end;

procedure DelayShort;
var
  I, J: integer;
begin
  for I := 1 to 200 do
    for J := 1 to 1500 do
    begin
    end
end;

procedure IntToStr(val, width: integer; var s: Str16);
var
  i, temp, idx: integer;
  buf: array[1..8] of char;
begin
  s := '';
  if val = 0 then
  begin
    buf[1] := '0';
    idx := 1
  end
  else
  begin
    temp := val;
    idx := 0;
    while temp > 0 do
    begin
      idx := idx + 1;
      buf[idx] := chr((temp mod 10) + ord('0'));
      temp := temp div 10
    end
  end;
  for i := idx + 1 to width do
    s := concat(s, ' ');
  for i := idx downto 1 do
    s := concat(s, buf[i])
end;

function ReadIntDefault(Prompt: Str80; DefaultVal, MinVal, MaxVal: integer): integer;
var
  InputStr: string[10];
  I, L, ValNum, Digit: integer;
  Valid: boolean;
  Ch: char;
begin
  write(Prompt, ' [', DefaultVal:1, ']: ');
  readln(InputStr);
  L := length(InputStr);
  if L = 0 then
    ReadIntDefault := DefaultVal
  else
  begin
    ValNum := 0;
    Valid := true;
    I := 1;
    while I <= L do
    begin
      Ch := InputStr[I];
      if (Ch >= '0') and (Ch <= '9') then
      begin
        Digit := ord(Ch) - ord('0');
        ValNum := ValNum * 10 + Digit
      end
      else
        Valid := false;
      I := I + 1
    end;
    if (not Valid) or (ValNum < MinVal) or (ValNum > MaxVal) then
      ReadIntDefault := DefaultVal
    else
      ReadIntDefault := ValNum
  end
end;

function DriveLetter(D: integer): char;
begin
  DriveLetter := chr(ord('A') + D - 1)
end;

procedure MakeName(Slot: integer; var ResultName: Str12);
var
  BaseName, ExtName: Str8;
  PosDMA, I, C: integer;
begin
  BaseName := '';
  ExtName := '';
  PosDMA := Slot * 32;
  for I := 1 to 8 do
  begin
    C := DirDMA[PosDMA + I];
    C := C & 127;
    if C <> ord(' ') then
      BaseName := concat(BaseName, chr(C))
  end;
  for I := 9 to 11 do
  begin
    C := DirDMA[PosDMA + I];
    C := C & 127;
    if C <> ord(' ') then
      ExtName := concat(ExtName, chr(C))
  end;
  ResultName := BaseName;
  if length(ExtName) > 0 then
    ResultName := concat(ResultName, '.', ExtName)
end;

function EntrySizeKB(Slot: integer): integer;
var
  PosDMA, Ex1, Ex2, RecByte: integer;
  ExtentNo, Records, SizeKB: real;
begin
  PosDMA := Slot * 32;
  Ex1 := DirDMA[PosDMA + 14];
  Ex1 := Ex1 & 63;
  Ex2 := DirDMA[PosDMA + 12];
  RecByte := DirDMA[PosDMA + 15];
  ExtentNo := Ex1 * 32 + Ex2;
  Records := ExtentNo * 128.0 + RecByte;
  SizeKB := Records / 8.0;
  if SizeKB > 32767.0 then
    EntrySizeKB := -1
  else
    EntrySizeKB := round(SizeKB)
end;

procedure FillFCB(var FCB: ByteArr36; Drive: integer; Name: Str12);
var
  I, BasePos, ExtPos, L: integer;
  InExt: boolean;
  Ch: char;
begin
  for I := 0 to 35 do
    FCB[I] := 0;
  FCB[0] := Drive;
  for I := 1 to 11 do
    FCB[I] := ord(' ');
  BasePos := 1;
  ExtPos := 9;
  InExt := false;
  L := length(Name);
  I := 1;
  while I <= L do
  begin
    Ch := Name[I];
    if Ch = '.' then
      InExt := true
    else if InExt then
    begin
      if ExtPos <= 11 then
      begin
        FCB[ExtPos] := ord(Ch);
        ExtPos := ExtPos + 1
      end
    end
    else
    begin
      if BasePos <= 8 then
      begin
        FCB[BasePos] := ord(Ch);
        BasePos := BasePos + 1
      end
    end;
    I := I + 1
  end
end;

procedure LoadDirectory(P: integer);
var
  N, Slot, K, I, Index: integer;
  ThisName: Str12;
  ThisSize: integer;
begin
  FileCount[P] := 0;
  Truncated[P] := false;
  for K := 0 to 35 do
    SearchFCB[K] := 0;
  SearchFCB[0] := DriveNo[P];
  for K := 1 to 11 do
    SearchFCB[K] := ord('?');
  Dummy := BDOS(26, addr(DirDMA));
  N := BDOS(17, addr(SearchFCB));
  if N < 0 then
    N := N + 256;
  while (N <> 255) and (FileCount[P] < MaxFiles) do
  begin
    Slot := N;
    MakeName(Slot, ThisName);
    ThisSize := EntrySizeKB(Slot);
    Index := 0;
    for I := 1 to FileCount[P] do
      if Files[P, I] = ThisName then
        Index := I;
    if Index = 0 then
    begin
      FileCount[P] := FileCount[P] + 1;
      Index := FileCount[P];
      Files[P, Index] := ThisName;
      FileSizes[P, Index] := ThisSize
    end
    else if (FileSizes[P, Index] >= 0) and
            ((ThisSize < 0) or (ThisSize > FileSizes[P, Index])) then
      FileSizes[P, Index] := ThisSize;
    N := BDOS(18, 0);
    if N < 0 then
      N := N + 256
  end;
  if (FileCount[P] = MaxFiles) and (N <> 255) then
    Truncated[P] := true;
  if FileCount[P] = 0 then
  begin
    Selected[P] := 0;
    FirstLine[P] := 1
  end
  else
  begin
    if Selected[P] < 1 then
      Selected[P] := 1;
    if Selected[P] > FileCount[P] then
      Selected[P] := FileCount[P];
    FirstLine[P] := 1
  end
end;

procedure EnsureVisible(P: integer);
var
  MaxFirst: integer;
begin
  if FileCount[P] = 0 then
  begin
    FirstLine[P] := 1;
    Selected[P] := 0
  end
  else
  begin
    if Selected[P] < 1 then
      Selected[P] := 1;
    if Selected[P] > FileCount[P] then
      Selected[P] := FileCount[P];
    if Selected[P] < FirstLine[P] then
      FirstLine[P] := Selected[P];
    if Selected[P] >= FirstLine[P] + Rows then
      FirstLine[P] := Selected[P] - Rows + 1;
    MaxFirst := FileCount[P] - Rows + 1;
    if MaxFirst < 1 then
      MaxFirst := 1;
    if FirstLine[P] > MaxFirst then
      FirstLine[P] := MaxFirst
  end
end;

modend.
