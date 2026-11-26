module TW22MOD2;

const
  MaxFiles = 150;

type
  Str2       = string[2];
  Str8       = string[8];
  Str12      = string[12];
  Str16      = string[16];
  Str80      = string[80];

var
  Files      : external array[1..2, 1..MaxFiles] of Str12;
  FileSizes  : external array[1..2, 1..MaxFiles] of integer;
  FileCount  : external array[1..2] of integer;
  DriveNo    : external array[1..2] of integer;
  Selected   : external array[1..2] of integer;
  FirstLine  : external array[1..2] of integer;
  Truncated  : external array[1..2] of boolean;
  ScreenRows : external integer;
  ScreenCols : external integer;
  Rows       : external integer;
  PanelWidth : external integer;
  InnerWidth : external integer;
  ColSep1    : external integer;
  ColSize    : external integer;
  Active     : external integer;
  StatusText : external Str80;
  AskSize    : external boolean;
  ESC        : external char;

external procedure AnsiGotoXY(X, Y: integer);
external procedure ClrScr;
external procedure ClrEol;
external procedure NormVideo;
external procedure DelayShort;
external procedure IntToStr(val, width: integer; var s: Str16);
external function ReadIntDefault(Prompt: Str80; DefaultVal, MinVal, MaxVal: integer): integer;
external function DriveLetter(D: integer): char;
external procedure EnsureVisible(P: integer);

procedure ShowBanner;
begin
  write(ESC, '[0m');
  NormVideo;
  ClrScr;
  writeln;
  writeln('----- *** TWIN - File Manager *** -----');
  writeln('|                                     |');
  writeln('|        (c) 2026, Ralf Kammel        |');
  writeln('|                                     |');
  writeln('|  Ported to CP/M 2.2 for the V20-MBC |');
  writeln('|          Running 8080 mode          |');
  writeln('|                                     |');
  writeln('|        by X-Lent Electronics        |');
  writeln('|            Version v2.0             |');
  writeln('|                                     |');
  writeln('---------------------------------------');
  writeln
end;

procedure SetupScreen;
begin
  if AskSize then
  begin
    writeln('---------------------------------------');
    writeln(ESC, '[1;32m', '  TWIN File Manager - Terminal Setup', ESC, '[0m');
    writeln('---------------------------------------');
    ScreenCols := ReadIntDefault(' How many Columns (80..132)', 90, 80, 132);
    ScreenRows := ReadIntDefault(' How many Rows (15..60)', 40, 15, 60)
  end
  else
  begin
    ScreenRows := 40;
    ScreenCols := 90;
    DelayShort
  end;
  Rows := ScreenRows - 6;
  PanelWidth := ScreenCols div 2;
  InnerWidth := PanelWidth - 2;
  if InnerWidth > 64 then
    InnerWidth := 64;
  ColSize := InnerWidth - 9;
  ColSep1 := ColSize - 2
end;

procedure DrawBorderLine(X, Y: integer; Title: Str80);
var
  K, SideLeft, SideRight: integer;
begin
  AnsiGotoXY(X, Y);
  if length(Title) = 0 then
  begin
    write('+');
    for K := 1 to InnerWidth do
      write('=');
    write('+')
  end
  else
  begin
    SideLeft := (InnerWidth - length(Title)) div 2;
    SideRight := InnerWidth - length(Title) - SideLeft;
    write('+');
    for K := 1 to SideLeft do
      write('=');
    write(ESC, '[1;37;44m', Title);
    write(ESC, '[0m', ESC, '[37;44m');
    for K := 1 to SideRight do
      write('=');
    write('+')
  end
end;

procedure BuildRowText(P, N: integer; var RowText: Str80);
var
  K: integer;
  NameText: Str12;
  SizeText: Str8;
  FreeText: Str16;
begin
  RowText := '';
  for K := 1 to InnerWidth do
    RowText := concat(RowText, ' ');
  RowText[ColSep1] := '|';
  NameText := Files[P, N];
  for K := 1 to length(NameText) do
    RowText[K] := NameText[K];
  if FileSizes[P, N] < 0 then
    SizeText := '>32767KB'
  else
  begin
    IntToStr(FileSizes[P, N], 5, FreeText);
    SizeText := concat(copy(FreeText, 1, 5), ' KB')
  end;
  for K := 1 to 8 do
    RowText[ColSize + K - 1] := SizeText[K]
end;

procedure DrawHdr(P: integer);
var
  X, K, TitleLen: integer;
begin
  if P = 1 then
    X := 1
  else
    X := PanelWidth + 1;
  AnsiGotoXY(X + 1, 2);
  write(ESC, '[0m');
  if P = Active then
    write(ESC, '[1;37;42m')
  else
    write(ESC, '[1;37;43m');
  if P = Active then
    write('>')
  else
    write(' ');
  write(DriveLetter(DriveNo[P]), ': ');
  write(FileCount[P]:3);
  write(' Files');
  TitleLen := 13;
  if Truncated[P] then
  begin
    write('+');
    TitleLen := TitleLen + 1
  end;
  for K := TitleLen + 1 to InnerWidth do
    write(' ');
  write(ESC, '[0m', ESC, '[37;44m')
end;

procedure DrawList(P: integer);
var
  X, Y, N, K: integer;
  RowText: Str80;
begin
  if P = 1 then
    X := 1
  else
    X := PanelWidth + 1;
  for Y := 1 to Rows do
  begin
    N := FirstLine[P] + Y - 1;
    AnsiGotoXY(X + 1, Y + 3);
    if (N <= FileCount[P]) and (N >= 1) then
    begin
      write(ESC, '[1;37;44m');
      if (P = Active) and (N = Selected[P]) then
        write(ESC, '[7m');
      BuildRowText(P, N, RowText);
      write(RowText);
      write(ESC, '[0m', ESC, '[37;44m')
    end
    else
    begin
      write(ESC, '[0m', ESC, '[37;44m');
      for K := 1 to InnerWidth do
        write(' ')
    end
  end
end;

procedure DrawPanel(P: integer);
var
  X, Y, K: integer;
  RowText: Str80;
begin
  if P = 1 then
    X := 1
  else
    X := PanelWidth + 1;
  write(ESC, '[0m', ESC, '[37;44m');
  if P = 1 then
    DrawBorderLine(X, 1, ' TWIN v2.0 ')
  else
    DrawBorderLine(X, 1, ' V20-MBC CP/M 2.2 ');
  for Y := 2 to ScreenRows - 3 do
  begin
    AnsiGotoXY(X, Y);
    write('|');
    for K := 1 to InnerWidth do
      write(' ');
    write('|')
  end;
  DrawBorderLine(X, ScreenRows - 2, '');
  DrawHdr(P);
  AnsiGotoXY(X + 1, 3);
  RowText := '';
  for K := 1 to InnerWidth do
    RowText := concat(RowText, ' ');
  RowText[1] := 'N';
  RowText[2] := 'a';
  RowText[3] := 'm';
  RowText[4] := 'e';
  RowText[ColSep1] := '|';
  RowText[ColSize] := 'S';
  RowText[ColSize + 1] := 'i';
  RowText[ColSize + 2] := 'z';
  RowText[ColSize + 3] := 'e';
  write(ESC, '[1;33;44m');
  write(RowText);
  write(ESC, '[0m', ESC, '[37;44m');
  DrawList(P)
end;

procedure DrawCommandLine;
begin
  AnsiGotoXY(1, ScreenRows);
  write(ESC, '[0;30;47m');
  write('Arrows Move | ');
  write(ESC, '[1;4m', 'TAB', ESC, '[0;30;47m', ' Panel | ');
  write(ESC, '[1;4m', 'C', ESC, '[0;30;47m', 'opy | ');
  write(ESC, '[1;4m', 'D', ESC, '[0;30;47m', 'el | ');
  write(ESC, '[1;4m', 'R', ESC, '[0;30;47m', 'ename | ');
  write(ESC, '[1;4m', 'S', ESC, '[0;30;47m', 'how | ');
  write(ESC, '[1;4m', 'L', ESC, '[0;30;47m', 'og Drive | ');
  write(ESC, '[1;4m', 'H', ESC, '[0;30;47m', 'elp | ');
  write(ESC, '[1;4m', 'Q', ESC, '[0;30;47m', 'uit');
  ClrEol;
  write(ESC, '[0m', ESC, '[37;40m')
end;

procedure DrawScreen;
begin
  NormVideo;
  write(ESC, '[0m', ESC, '[37;44m');
  ClrScr;
  AnsiGotoXY(1, ScreenRows - 1);
  write(ESC, '[0m', ESC, '[37;40m');
  write(StatusText);
  ClrEol;
  DrawCommandLine;
  DrawPanel(1);
  DrawPanel(2)
end;

procedure DrawFileRow(P, N: integer);
var
  X, Y, K: integer;
  RowText: Str80;
begin
  if (N >= FirstLine[P]) and (N < FirstLine[P] + Rows) then
  begin
    if P = 1 then
      X := 1
    else
      X := PanelWidth + 1;
    Y := N - FirstLine[P] + 4;
    if (N >= 1) and (N <= FileCount[P]) then
      BuildRowText(P, N, RowText)
    else
    begin
      RowText := '';
      for K := 1 to InnerWidth do
        RowText := concat(RowText, ' ')
    end;
    AnsiGotoXY(X + 1, Y);
    write(ESC, '[1;37;44m');
    if (P = Active) and (N = Selected[P]) then
      write(ESC, '[7m');
    write(RowText);
    write(ESC, '[0m', ESC, '[37;44m')
  end
end;

procedure MoveSelection(P, Direction: integer);
var
  OldSelected, OldFirst: integer;
begin
  OldSelected := Selected[P];
  OldFirst := FirstLine[P];
  if FileCount[P] > 0 then
  begin
    if Selected[P] = 0 then
      Selected[P] := 1
    else
      Selected[P] := Selected[P] + Direction;
    if Selected[P] < 1 then
      Selected[P] := 1;
    if Selected[P] > FileCount[P] then
      Selected[P] := FileCount[P];
    EnsureVisible(P);
    if FirstLine[P] <> OldFirst then
      DrawList(P)
    else
    begin
      if OldSelected > 0 then
        DrawFileRow(P, OldSelected);
      DrawFileRow(P, Selected[P])
    end
  end;
  AnsiGotoXY(1, ScreenRows - 1);
  write(ESC, '[37;40m');
  ClrEol
end;

procedure SetStatus(Msg: Str80);
begin
  StatusText := Msg;
  AnsiGotoXY(1, ScreenRows - 1);
  write(ESC, '[0m', ESC, '[37;40m');
  write(StatusText);
  ClrEol
end;

modend.
