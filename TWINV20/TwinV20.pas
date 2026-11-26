program TWIN;
{
  TWIN - Two-panel file manager for TP 3.01B and CP/M-86
  Copyright (c) 2026 Ralf Kammel
  SPDX-License-Identifier: MIT
  See LICENSE for the full license text.
  
  Version v1.0 : Orignal version by Ralf Kammel
  
  Version v2.0 : by X-Lent Electronics, November 2026
  - v1.0 Ported to CP/M-86 1.1 for the V-20MBC
  - Start up screen showing Copyright
  - Improved drawing of the panels, no complete redraws of the panels
    by executing a Command   
  - Improved file selection wiht Up/down keys
    No redraws of the panels, just scrolls file up or down
  - Display name in Right penal renamed to V20-MBC 
  - Start up switch /S or /s option to enter terminal Columns and Rows
    Default settings is 90x40
  - Solved bug. When file name is 12 characters error cannot open file, which is wrong.
    Now it opens file names of 12 charecters long correctly
  - S Show, you must press a key to return to TWIN when EOF is reached
    Time now to read the content
  - Added status message COM/CMD with tokenized files cannot be displayed
  - Added H Help procedure. Help screen in new window
  - Change Commandline look and feel
  - /O or /o to show date is not supported in CP/m-86 1.1. 
    A statusline messages is displayed when /O or /o is used
	
  Version 2.1 :
  - Removed /O or /o option. cannot be used in CP/M-86 v1.1.
  - Added Running 8086 in Startup and Help screen  
	
 }

const
  MaxFiles = 240;
  BufRecs = 8;
  ESC = #27;

type
  FileName = string[12];
  FreeString = string[16];
  LineString = string[80];
  
  Registers = record
    AX, BX, CX, DX, BP, SI, DI, DS, ES, Flags: Integer;
  end;

var
  Files: array[1..2, 1..MaxFiles] of FileName;
  FileSizes: array[1..2, 1..MaxFiles] of Integer;
  FileCount: array[1..2] of Integer;
  DriveNo: array[1..2] of Integer;
  Selected: array[1..2] of Integer;
  FirstLine: array[1..2] of Integer;
  Truncated: array[1..2] of Boolean;
  SearchFCB: array[0..35] of Byte;
  RenameFCB: array[0..35] of Byte;
  DirDMA: array[0..127] of Byte;
  ScreenRows: Integer;
  ScreenCols: Integer;
  Rows: Integer;
  PanelWidth: Integer;
  InnerWidth: Integer;
  ColSep1: Integer;
  ColSize: Integer;
  Active: Integer;
  Key, Key2, Key3: Char;
  StatusText: string[78];
  Quit: Boolean;
  CPM3: Boolean;
  Redraw: Boolean;
  AskSize: Boolean;
  ParamIndex: Integer;
  Regs: Registers;

procedure AnsiGotoXY(X, Y: Integer);
begin
  Write(ESC, '[', Y, ';', X, 'H');
end;

procedure ClearRegs;
begin
  Regs.AX := 0;
  Regs.BX := 0;
  Regs.CX := 0;
  Regs.DX := 0;
  Regs.BP := 0;
  Regs.SI := 0;
  Regs.DI := 0;
  Regs.DS := Dseg;
  Regs.ES := Dseg;
  Regs.Flags := 0;
end;

function Bdos86(Func, ParamDX, ParamDS: Integer): Integer;
begin
  ClearRegs;
  Regs.CX := Func;
  Regs.DX := ParamDX;
  Regs.DS := ParamDS;
  Bdos(Regs);
  Bdos86 := Lo(Regs.AX);
end;

procedure SetDMA86(OffsetAddr, SegmentAddr: Integer);
begin
  ClearRegs;
  Regs.CX := 51; { Set DMA Base }
  Regs.DX := SegmentAddr;
  Bdos(Regs);
  ClearRegs;
  Regs.CX := 26; { Set DMA Offset }
  Regs.DX := OffsetAddr;
  Bdos(Regs);
end;

function ReadIntDefault(Prompt: LineString; DefaultVal, MinVal, MaxVal: Integer): Integer;
var
  InputStr: string[10];
  ValNum, Code: Integer;
begin
  Write(Prompt, ' [', DefaultVal, ']: ');
  ReadLn(InputStr);
  if Length(InputStr) = 0 then
    ReadIntDefault := DefaultVal
  else
  begin
    Val(InputStr, ValNum, Code);
    if (Code <> 0) or (ValNum < MinVal) or (ValNum > MaxVal) then
      ReadIntDefault := DefaultVal
    else
      ReadIntDefault := ValNum;
  end;
end;

procedure ShowBanner;
begin
  Write(ESC, '[0m');
  NormVideo;
  ClrScr;
  WriteLn;
  WriteLn('----- *** TWIN - File Manager *** -----');
  WriteLn('|                                     |');
  WriteLn('|        (c) 2026, Ralf Kammel        |');
  WriteLn('|                                     |');
  WriteLn('|  Ported to CP/M-86 for the V20-MBC  |');
  WriteLn('|          Running 8086 mode          |');
  WriteLn('|                                     |');
  WriteLn('|        by X-Lent Electronics        |');
  WriteLn('|            Version v2.1             |');
  WriteLn('|                                     |');  	
  WriteLn('---------------------------------------');
  WriteLn;
end;

procedure SetupScreen;
var
  Extra: Integer;
begin
  if AskSize then
  begin
    WriteLn('---------------------------------------');
    WriteLn(ESC, '[1;32m','  TWIN File Manager - Terminal Setup', ESC, '[0m');
    WriteLn('---------------------------------------');
    ScreenCols := ReadIntDefault(' How many Columns (80..132)', 90, 80, 132);
    ScreenRows := ReadIntDefault(' How many Rows (15..60)', 40, 15, 60);
  end
  else
  begin
    ScreenRows := 40;
    ScreenCols := 90;
    Delay(3500);
  end;

  Rows := ScreenRows - 6;
  PanelWidth := ScreenCols div 2;
  InnerWidth := PanelWidth - 2;
  if InnerWidth > 64 then
    InnerWidth := 64;

  Extra := InnerWidth - 38;
  if Extra < 0 then
    Extra := 0;

  ColSize := InnerWidth - 9;
  ColSep1 := ColSize - 2;
end;

function DriveLetter(D: Integer): Char;
begin
  DriveLetter := Chr(Ord('A') + D - 1);
end;

function MakeName(Slot: Integer): FileName;
var
  BaseName, ExtName: string[8];
  ResultName: FileName;
  PosDMA, I, C: Integer;
begin
  BaseName := '';
  ExtName := '';
  PosDMA := Slot * 32;
  for I := 1 to 8 do
  begin
    C := DirDMA[PosDMA + I] and $7F;
    if C <> Ord(' ') then
      BaseName := BaseName + Chr(C);
  end;
  for I := 9 to 11 do
  begin
    C := DirDMA[PosDMA + I] and $7F;
    if C <> Ord(' ') then
      ExtName := ExtName + Chr(C);
  end;
  ResultName := BaseName;
  if Length(ExtName) > 0 then
    ResultName := ResultName + '.' + ExtName;
  MakeName := ResultName;
end;

function EntrySizeKB(Slot: Integer): Integer;
var
  PosDMA: Integer;
  ExtentNo: Real;
  Records, SizeKB: Real;
begin
  PosDMA := Slot * 32;
  ExtentNo := (DirDMA[PosDMA + 14] and $3F) * 32 + DirDMA[PosDMA + 12];
  Records := ExtentNo * 128.0 + DirDMA[PosDMA + 15];
  SizeKB := Records / 8.0;
  if CPM3 and (DirDMA[PosDMA + 13] > 0) and (Records > 0) then
    SizeKB := SizeKB - (128 - DirDMA[PosDMA + 13]) / 1024.0;
  if SizeKB > 32767.0 then
    EntrySizeKB := -1
  else
    EntrySizeKB := Round(SizeKB);
end;

procedure LoadDirectory(P: Integer);
var
  N, Slot, K, I, Index: Integer;
  ThisName: FileName;
  ThisSize: Integer;
begin
  FileCount[P] := 0;
  Truncated[P] := False;
  for K := 0 to 35 do
    SearchFCB[K] := 0;
  SearchFCB[0] := DriveNo[P];
  for K := 1 to 11 do
    SearchFCB[K] := Ord('?');
  SetDMA86(Ofs(DirDMA), Seg(DirDMA));
  N := Bdos86(17, Ofs(SearchFCB), Seg(SearchFCB));
  while (N <> 255) and (FileCount[P] < MaxFiles) do
  begin
    Slot := N;
    ThisName := MakeName(Slot);
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
      FileSizes[P, Index] := ThisSize;
    end
    else if (FileSizes[P, Index] >= 0) and
      ((ThisSize < 0) or (ThisSize > FileSizes[P, Index])) then
      FileSizes[P, Index] := ThisSize;
    N := Bdos86(18, 0, Dseg);
  end;
  if (FileCount[P] = MaxFiles) and (N <> 255) then
    Truncated[P] := True;
  if FileCount[P] = 0 then
  begin
    Selected[P] := 0;
    FirstLine[P] := 1;
  end
  else
  begin
    if Selected[P] < 1 then
      Selected[P] := 1;
    if Selected[P] > FileCount[P] then
      Selected[P] := FileCount[P];
    FirstLine[P] := 1;
  end;
end;

procedure EnsureVisible(P: Integer);
var
  MaxFirst: Integer;
begin
  if FileCount[P] = 0 then
  begin
    FirstLine[P] := 1;
    Selected[P] := 0;
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
      FirstLine[P] := MaxFirst;
  end;
end;

procedure GetFreeSpace(P: Integer; var Text: FreeString);
var
  Err: Integer;
  FreeKB: Real;
begin
  Text := '';
  SetDMA86(Ofs(DirDMA), Seg(DirDMA));
  Err := Bdos86(46, DriveNo[P] - 1, Dseg);
  if Err = 0 then
  begin
    FreeKB := DirDMA[2] * 8192.0 + DirDMA[1] * 32.0 + DirDMA[0] / 8.0;
    Str(FreeKB:7:0, Text);
    while (Length(Text) > 0) and (Text[1] = ' ') do
      Text := Copy(Text, 2, Length(Text) - 1);
  end
  else
    Text := 'n/a';
end;

procedure DrawBorderLine(X, Y: Integer; Title: LineString);
var
  K, SideLeft, SideRight: Integer;
begin
  AnsiGotoXY(X, Y);
  if Length(Title) = 0 then
  begin
    Write('+');
    for K := 1 to InnerWidth do
      Write('=');
    Write('+');
  end
  else
  begin
    SideLeft := (InnerWidth - Length(Title)) div 2;
    SideRight := InnerWidth - Length(Title) - SideLeft;
    Write('+');
    for K := 1 to SideLeft do
      Write('=');
    Write(ESC, '[1;37;44m', Title);
    Write(ESC, '[0m', ESC, '[37;44m');
    for K := 1 to SideRight do
      Write('=');
    Write('+');
  end;
end;

procedure BuildRowText(P, N: Integer; var RowText: LineString);
var
  K: Integer;
  NameText: FileName;
  SizeText: string[8];
  FreeText: FreeString;
begin
  RowText := '';
  for K := 1 to InnerWidth do
    RowText := RowText + ' ';
  RowText[ColSep1] := '|';
  NameText := Files[P, N];
  for K := 1 to Length(NameText) do
    RowText[K] := NameText[K];
  if FileSizes[P, N] < 0 then
    SizeText := '>32767KB'
  else
  begin
    Str(FileSizes[P, N]:5, FreeText);
    SizeText := Copy(FreeText, 1, 5) + ' KB';
  end;
  for K := 1 to 8 do
    RowText[ColSize + K - 1] := SizeText[K];
end;

procedure DrawPanelHeader(P: Integer);
var
  X, K, TitleLen: Integer;
  FreeText: FreeString;
begin
  if P = 1 then
    X := 1
  else
    X := PanelWidth + 1;
  AnsiGotoXY(X + 1, 2);
  Write(ESC, '[0m');
  if P = Active then
    Write(ESC, '[1;37;42m')
  else
    Write(ESC, '[1;37;43m');
  if P = Active then
    Write('>')
  else
    Write(' ');
  Write(DriveLetter(DriveNo[P]), ': ');
  Write(FileCount[P]:3);
  Write(' Files');
  TitleLen := 13;
  if CPM3 then
  begin
    GetFreeSpace(P, FreeText);
    Write(' ', FreeText, ' KB free');
    TitleLen := TitleLen + 1 + Length(FreeText) + 8;
  end;
  if Truncated[P] then
  begin
    Write('+');
    TitleLen := TitleLen + 1;
  end;
  for K := TitleLen + 1 to InnerWidth do
    Write(' ');
  Write(ESC, '[0m', ESC, '[37;44m');
end;


procedure DrawPanelFiles(P: Integer);
var
  X, Y, N, K: Integer;
  RowText: LineString;
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
      Write(ESC, '[1;37;44m');
      if (P = Active) and (N = Selected[P]) then
        Write(ESC, '[7m');
      BuildRowText(P, N, RowText);
      Write(RowText);
      Write(ESC, '[0m', ESC, '[37;44m');
    end
    else
    begin
      Write(ESC, '[0m', ESC, '[37;44m');
      for K := 1 to InnerWidth do
        Write(' ');
    end;
  end;
end;

procedure DrawPanel(P: Integer);
var
  X, Y, N, K, TitleLen: Integer;
  FreeText: FreeString;
  RowText: LineString;
begin
  if P = 1 then
    X := 1
  else
    X := PanelWidth + 1;
  Write(ESC, '[0m', ESC, '[37;44m');
  if P = 1 then
    DrawBorderLine(X, 1, ' TWIN v2.1 ')
  else
    DrawBorderLine(X, 1, ' V20-MBC CP/M-86 ');
  for Y := 2 to ScreenRows - 3 do
  begin
    AnsiGotoXY(X, Y);
    Write('|');
    for K := 1 to InnerWidth do
      Write(' ');
    Write('|');
  end;
  DrawBorderLine(X, ScreenRows - 2, '');
  AnsiGotoXY(X + 1, 2);
  Write(ESC, '[0m');
  if P = Active then
    Write(ESC, '[1;37;42m')
  else
    Write(ESC, '[1;37;43m');
  if P = Active then
    Write('>')
  else
    Write(' ');
  Write(DriveLetter(DriveNo[P]), ': ');
  Write(FileCount[P]:3);
  Write(' Files');
  TitleLen := 13;
  if CPM3 then
  begin
    GetFreeSpace(P, FreeText);
    Write(' ', FreeText, ' KB free');
    TitleLen := TitleLen + 1 + Length(FreeText) + 8;
  end;
  if Truncated[P] then
  begin
    Write('+');
    TitleLen := TitleLen + 1;
  end;
  for K := TitleLen + 1 to InnerWidth do
    Write(' ');
  Write(ESC, '[0m', ESC, '[37;44m');
  AnsiGotoXY(X + 1, 3);
  RowText := '';
  for K := 1 to InnerWidth do
    RowText := RowText + ' ';
  RowText[1] := 'N';
  RowText[2] := 'a';
  RowText[3] := 'm';
  RowText[4] := 'e';
  RowText[ColSep1] := '|';
  RowText[ColSize] := 'S';
  RowText[ColSize + 1] := 'i';
  RowText[ColSize + 2] := 'z';
  RowText[ColSize + 3] := 'e';
  Write(ESC, '[1;33;44m');
  Write(RowText);
  Write(ESC, '[0m', ESC, '[37;44m');
  for Y := 1 to Rows do
  begin
    N := FirstLine[P] + Y - 1;
    AnsiGotoXY(X + 1, Y + 3);
    if (N <= FileCount[P]) and (N >= 1) then
    begin
      Write(ESC, '[1;37;44m');
      if (P = Active) and (N = Selected[P]) then
        Write(ESC, '[7m');
      BuildRowText(P, N, RowText);
      Write(RowText);
      Write(ESC, '[0m', ESC, '[37;44m');
    end
    else
    begin
      for K := 1 to InnerWidth do
        Write(' ');
    end;
  end;
end;

procedure DrawCommandLine;
var
  K, VisibleLen: Integer;
begin
  AnsiGotoXY(1, ScreenRows);
  Write(ESC, '[0;30;47m');
  Write('Arrows Move | ');
  Write(ESC, '[1;4m', 'TAB', ESC, '[0;30;47m', ' Panel | ');
  Write(ESC, '[1;4m', 'C', ESC, '[0;30;47m', 'opy | ');
  Write(ESC, '[1;4m', 'D', ESC, '[0;30;47m', 'el | ');
  Write(ESC, '[1;4m', 'R', ESC, '[0;30;47m', 'ename | ');
  Write(ESC, '[1;4m', 'S', ESC, '[0;30;47m', 'how | ');
  Write(ESC, '[1;4m', 'L', ESC, '[0;30;47m', 'og Drive | ');
  Write(ESC, '[1;4m', 'H', ESC, '[0;30;47m', 'elp | ');
  Write(ESC, '[1;4m', 'Q', ESC, '[0;30;47m', 'uit');
  {VisibleLen := 78;
  for K := VisibleLen + 1 to ScreenCols - 1 do
    Write(' ');}
  ClrEol;
  Write(ESC, '[0m', ESC, '[37;40m');
end;


procedure DrawScreen;
begin
  NormVideo;
  Write(ESC, '[0m', ESC, '[37;44m');
  ClrScr;
  AnsiGotoXY(1, ScreenRows - 1);
  Write(ESC, '[0m', ESC, '[37;40m');
  Write(StatusText);
  ClrEol;
  DrawCommandLine;
  DrawPanel(1);
  DrawPanel(2);
end;

procedure DrawFileRow(P, N: Integer);
var
  X, Y: Integer;
  RowText: LineString;
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
      for X := 1 to InnerWidth do
        RowText := RowText + ' ';
      if P = 1 then
        X := 1
      else
        X := PanelWidth + 1;
    end;
    AnsiGotoXY(X + 1, Y);
    Write(ESC, '[1;37;44m');
    if (P = Active) and (N = Selected[P]) then
      Write(ESC, '[7m');
    Write(RowText);
    Write(ESC, '[0m', ESC, '[37;44m');
  end;
end;

procedure MoveSelection(P, Direction: Integer);
var
  OldSelected, OldFirst: Integer;
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
      DrawPanelFiles(P)
    else
    begin
      if OldSelected > 0 then
        DrawFileRow(P, OldSelected);
      DrawFileRow(P, Selected[P]);
    end;
  end;
  AnsiGotoXY(1, ScreenRows - 1);
  Write(ESC, '[37;40m');
  ClrEol;
end;

procedure SetStatus(Msg: LineString);
begin
  StatusText := Msg;
  AnsiGotoXY(1, ScreenRows - 1);
  Write(ESC, '[0m', ESC, '[37;40m');
  Write(StatusText);
  ClrEol;
end;

procedure ChangeDrive(P: Integer);
var
  Ch: Char;
  D: Integer;
begin
  AnsiGotoXY(1, ScreenRows - 1);
  Write(ESC, '[1;32;40m');
  Write('Drive A-P (ESC cancels): ');
  ClrEol;
  Read(Kbd, Ch);
  Write(ESC, '[0m', ESC, '[37;40m');
  if (Ch >= 'a') and (Ch <= 'z') then
    Ch := Chr(Ord(Ch) - Ord('a') + Ord('A'));
  if (Ch >= 'A') and (Ch <= 'P') then
  begin
    D := Ord(Ch) - Ord('A') + 1;
    DriveNo[P] := D;
    Selected[P] := 1;
    LoadDirectory(P);
    DrawPanelHeader(P);
    DrawPanelFiles(P);
    StatusText := 'Drive ' + DriveLetter(D) + ': loaded.';
  end
  else
    StatusText := 'Drive change cancelled.';
  SetStatus(StatusText);
end;

procedure CopySelected;
var
  SrcPanel, DstPanel, I, RecsRead, Err: Integer;
  SrcName, DstName: string[16];
  SourceFile, DestFile: file;
  Buffer: array[0..1023] of Byte;
  Ch: Char;
  SourceOpen, DestOpen, Proceed, CopyOK: Boolean;

begin
  SourceOpen := False;
  DestOpen := False;
  Proceed := False;
  CopyOK := False;
  if FileCount[Active] = 0 then
    StatusText := 'No file selected in active panel.'
  else
  begin
    SrcPanel := Active;
    if SrcPanel = 1 then
      DstPanel := 2
    else
      DstPanel := 1;
    SrcName := DriveLetter(DriveNo[SrcPanel]) + ':' +
      Files[SrcPanel, Selected[SrcPanel]];
    DstName := DriveLetter(DriveNo[DstPanel]) + ':' +
      Files[SrcPanel, Selected[SrcPanel]];
    if SrcName = DstName then
      StatusText := 'Source and destination are identical.'
    else
    begin
      Assign(SourceFile, SrcName);
      {$I-}
      Reset(SourceFile);
      {$I+}
      Err := IOresult;
      if Err <> 0 then
        StatusText := 'Cannot open source file.'
      else
      begin
        SourceOpen := True;
        Assign(DestFile, DstName);
        {$I-}
        Reset(DestFile);
        {$I+}
        Err := IOresult;
        if Err = 0 then
        begin
          {$I-}
          Close(DestFile);
          {$I+}
          Err := IOresult;
          if Err <> 0 then
            StatusText := 'Cannot check destination file.'
          else
          begin
            AnsiGotoXY(1, ScreenRows - 1);
            Write(ESC, '[1;32;40m');
            Write('Destination exists. Overwrite (Y/N)? ');
            ClrEol;
            Read(Kbd, Ch);
            Write(ESC, '[0m', ESC, '[37;40m');
            if (Ch = 'Y') or (Ch = 'y') then
              Proceed := True
            else
              StatusText := 'Copy cancelled.';
          end;
        end
        else
          Proceed := True;
        if Proceed then
        begin
          Assign(DestFile, DstName);
          {$I-}
          Rewrite(DestFile);
          {$I+}
          Err := IOresult;
          if Err <> 0 then
            StatusText := 'Cannot create destination file.'
          else
          begin
            DestOpen := True;
            CopyOK := True;
            repeat
              RecsRead := 0;
              {$I-}
              BlockRead(SourceFile, Buffer, BufRecs, RecsRead);
              {$I+}
              Err := IOresult;
              if Err <> 0 then
              begin
                CopyOK := False;
                StatusText := 'Error reading source file.';
              end
              else if RecsRead > 0 then
              begin
                {$I-}
                BlockWrite(DestFile, Buffer, RecsRead);
                {$I+}
                Err := IOresult;
                if Err <> 0 then
                begin
                  CopyOK := False;
                  StatusText := 'Error writing destination file.';
                end;
              end;
            until (not CopyOK) or (RecsRead < BufRecs);
          end;
        end;
      end;
    end;
    if SourceOpen then
    begin
      {$I-}
      Close(SourceFile);
      {$I+}
      Err := IOresult;
      if Err <> 0 then
      begin
        CopyOK := False;
        StatusText := 'Error closing source file.';
      end;
    end;
    if DestOpen then
    begin
      {$I-}
      Close(DestFile);
      {$I+}
      Err := IOresult;
      if Err <> 0 then
      begin
        CopyOK := False;
        StatusText := 'Error closing destination file.';
      end;
    end;
    if CopyOK then
    begin
      LoadDirectory(DstPanel);
      for I := 1 to FileCount[DstPanel] do
        if Files[DstPanel, I] = Files[SrcPanel, Selected[SrcPanel]] then
          Selected[DstPanel] := I;
      EnsureVisible(DstPanel);
      DrawPanelHeader(DstPanel);
      DrawPanelFiles(DstPanel);
      StatusText := 'File copied to ' + DriveLetter(DriveNo[DstPanel]) + ':';
    end;
  end;
  SetStatus(StatusText);
end;


procedure DeleteSelected;
var
  P, OldIndex, Err: Integer;
  DeleteName: FileName;
  DeleteSpec: string[16];
  DeleteFile: file;
  Ch: Char;
begin
  if FileCount[Active] = 0 then
    SetStatus('No file selected in active panel.')
  else
  begin
    P := Active;
    OldIndex := Selected[P];
    DeleteName := Files[P, OldIndex];
    DeleteSpec := DriveLetter(DriveNo[P]) + ':' + DeleteName;
    AnsiGotoXY(1, ScreenRows - 1);
    Write(ESC, '[1;32;40m');
    Write('Delete file ', DeleteName, ' (Y/N)? ');
    ClrEol;
    Read(Kbd, Ch);
    Write(ESC, '[0m', ESC, '[37;40m');
    if (Ch = 'Y') or (Ch = 'y') then
    begin
      Assign(DeleteFile, DeleteSpec);
      {$I-}
      Erase(DeleteFile);
      {$I+}
      Err := IOresult;
      if Err <> 0 then
        StatusText := 'Cannot delete file.'
      else
      begin
        LoadDirectory(P);
        if FileCount[P] > 0 then
        begin
          if OldIndex > FileCount[P] then
            OldIndex := FileCount[P];
          Selected[P] := OldIndex;
          EnsureVisible(P);
        end;
        DrawPanelHeader(P);
        DrawPanelFiles(P);
        StatusText := 'Deleted: ' + DeleteName;
      end;
    end
    else
      StatusText := 'Delete cancelled.';
    SetStatus(StatusText);
  end;
end;


procedure DrawViewerPage(Name: FileName);
begin
  ClrScr;
  AnsiGotoXY(1, 1);
  Write(ESC, '[7m', 'File: ', Name);
  ClrEol;
  Write(ESC, '[0m', ESC, '[37;44m');
  AnsiGotoXY(1, ScreenRows - 1);
  Write(ESC, '[1;32;40m');
  Write('Any key: next page  Q or ESC: quit');
  ClrEol;
  Write(ESC, '[0m', ESC, '[37;40m');
  DrawCommandLine;
end;

procedure AdvanceViewerLine(var Row, Col: Integer;
  var StopView: Boolean; Name: FileName);
begin
  Row := Row + 1;
  Col := 1;
  if Row > ScreenRows - 2 then
  begin
    AnsiGotoXY(1, ScreenRows - 1);
    Write(ESC, '[1;32;40m');
    Write('Any key: next page  Q or ESC: quit');
    ClrEol;
    Read(Kbd, Key);
    Write(ESC, '[0m', ESC, '[37;40m');
    if (Key = 'q') or (Key = 'Q') or (Key = ESC) then
      StopView := True
    else
    begin
      DrawViewerPage(Name);
      Row := 2;
      Col := 1;
    end;
  end;
end;

procedure ShowSelected;
var
  P, I, Err, RecsRead, Code, Row, Col: Integer;
  Name: FileName;
  ViewSpec: string[16];
  ViewFile: file;
  ViewBuffer: array[0..127] of Byte;
  StopView, ReadError, LastCR, EOFSeen, FirstBlock: Boolean;

begin
  if FileCount[Active] = 0 then
    StatusText := 'No file selected in active panel.'
  else
  begin
    P := Active;
    Name := Files[P, Selected[P]];
    if (Length(Name) >= 4) and
      ((Copy(Name, Length(Name) - 3, 4) = '.COM') or
       (Copy(Name, Length(Name) - 3, 4) = '.CMD')) then
      StatusText := 'COM, CMD or tokenized files cannot be displayed.'
    else
    begin
      ViewSpec := DriveLetter(DriveNo[P]) + ':' + Name;
      Assign(ViewFile, ViewSpec);
      {$I-}
      Reset(ViewFile);
      {$I+}
      Err := IOresult;
      if Err <> 0 then
        StatusText := 'Cannot open file.'
      else
      begin
        StopView := False;
        ReadError := False;
        LastCR := False;
        EOFSeen := False;
        FirstBlock := True;
        Row := 2;
        Col := 1;
        repeat
          RecsRead := 0;
          {$I-}
          BlockRead(ViewFile, ViewBuffer, 1, RecsRead);
          {$I+}
          Err := IOresult;
          if Err <> 0 then
          begin
            ReadError := True;
            StopView := True;
          end
          else if RecsRead > 0 then
          begin
            if FirstBlock then
            begin
              FirstBlock := False;
              if (Length(Name) >= 4) and
                 (Copy(Name, Length(Name) - 3, 4) = '.BAS') and
                 (ViewBuffer[0] = 255) then
              begin
                StopView := True;
                StatusText := 'COM, CMD or tokenized files cannot be displayed.';
              end
              else
                DrawViewerPage(Name);
            end;
            if not StopView then
            begin
              for I := 0 to 127 do
              begin
                if not EOFSeen and not StopView then
                begin
                  Code := ViewBuffer[I];
                  if Code = 26 then
                    EOFSeen := True
                  else if Code = 13 then
                  begin
                    LastCR := True;
                    AdvanceViewerLine(Row, Col, StopView, Name);
                  end
                  else if Code = 10 then
                  begin
                    if not LastCR then
                      AdvanceViewerLine(Row, Col, StopView, Name);
                    LastCR := False;
                  end
                  else
                  begin
                    LastCR := False;
                    if Col > ScreenCols then
                      AdvanceViewerLine(Row, Col, StopView, Name);
                    if not StopView then
                    begin
                      AnsiGotoXY(Col, Row);
                      if (Code >= 32) and (Code <> 127) then
                        Write(Chr(Code))
                      else if Code = 9 then
                        Write(' ')
                      else
                        Write('.');
                      Col := Col + 1;
                    end;
                  end;
                end;
              end;
            end;
          end;
        until (RecsRead = 0) or EOFSeen or StopView;
        {$I-}
        Close(ViewFile);
        {$I+}
        Err := IOresult;
        if ReadError then
          StatusText := 'Error reading file.'
        else if Err <> 0 then
          StatusText := 'Error closing file.'
        else
        begin
          if not StopView then
          begin
            AnsiGotoXY(1, ScreenRows - 1);
            Write(ESC, '[1;32;40m');
            Write('End of file. Press any key to return...');
            ClrEol;
            Read(Kbd, Key);
            Write(ESC, '[0m', ESC, '[37;40m');
          end;
		  if StatusText <> 'COM, CMD or tokenized files cannot be displayed.' then
            StatusText := 'View finished.';
        end;
      end;
    end;
  end;
end;

procedure PutFCBName(Offset: Integer; Name: FileName);
var
  I, BasePos, ExtPos: Integer;
  InExtension: Boolean;
begin
  for I := 1 to 11 do
    RenameFCB[Offset + I] := Ord(' ');
  BasePos := 1;
  ExtPos := 9;
  InExtension := False;
  for I := 1 to Length(Name) do
  begin
    if Name[I] = '.' then
      InExtension := True
    else if InExtension then
    begin
      RenameFCB[Offset + ExtPos] := Ord(Name[I]);
      ExtPos := ExtPos + 1;
    end
    else
    begin
      RenameFCB[Offset + BasePos] := Ord(Name[I]);
      BasePos := BasePos + 1;
    end;
  end;
end;

procedure RenameSelected;
var
  P, I, Err, BaseLen, ExtLen: Integer;
  NewName: FileName;
  Ch: Char;
  Cancelled, InExtension, ValidName: Boolean;
begin
  if FileCount[Active] = 0 then
    SetStatus('No file selected in active panel.')
  else
  begin
    P := Active;
    NewName := '';
    Cancelled := False;
    AnsiGotoXY(1, ScreenRows - 1);
    Write(ESC, '[1;32;40m');
    Write('New name 8.3, ESC cancels: ');
    ClrEol;
    Write(ESC, '[0m', ESC, '[37;40m');
    repeat
      Read(Kbd, Ch);
      if Ch = ESC then
        Cancelled := True
      else if Ch = #13 then
      begin
      end
      else if (Ch = #8) or (Ch = #127) then
      begin
        if Length(NewName) > 0 then
        begin
          NewName := Copy(NewName, 1, Length(NewName) - 1);
          Write(#8, ' ', #8);
        end;
      end
      else if Length(NewName) < 12 then
      begin
        if (Ch >= 'a') and (Ch <= 'z') then
          Ch := Chr(Ord(Ch) - Ord('a') + Ord('A'));
        NewName := NewName + Ch;
        Write(Ch);
      end;
    until (Ch = #13) or Cancelled;
    if Cancelled then
      StatusText := 'Rename cancelled.'
    else if Length(NewName) = 0 then
      StatusText := 'No new name entered.'
    else
    begin
      BaseLen := 0;
      ExtLen := 0;
      InExtension := False;
      ValidName := True;
      for I := 1 to Length(NewName) do
      begin
        Ch := NewName[I];
        if Ch = '.' then
        begin
          if InExtension or (BaseLen = 0) then
            ValidName := False;
          InExtension := True;
        end
        else
        begin
          if (Ch <= ' ') or (Ch = ':') or (Ch = '*') or
             (Ch = '?') or (Ch = ';') or (Ch = ',') or
             (Ch = '=') or (Ch = '[') or (Ch = ']') or
             (Ch = '<') or (Ch = '>') or (Ch = '/') or
             (Ch = '\') or (Ch = '|') then
            ValidName := False;
          if InExtension then
            ExtLen := ExtLen + 1
          else
            BaseLen := BaseLen + 1;
        end;
      end;
      if (BaseLen > 8) or (ExtLen > 3) then
        ValidName := False;
      if InExtension and (ExtLen = 0) then
        ValidName := False;
      if not ValidName then
        StatusText := 'Invalid file name (8.3).'
      else if NewName = Files[P, Selected[P]] then
        StatusText := 'The name is unchanged.'
      else
      begin
        for I := 0 to 35 do
          RenameFCB[I] := 0;
        RenameFCB[0] := DriveNo[P];
        RenameFCB[16] := DriveNo[P];
        PutFCBName(0, Files[P, Selected[P]]);
        PutFCBName(16, NewName);
        Err := Bdos86(23, Ofs(RenameFCB), Seg(RenameFCB));
        if Err <> 0 then
          StatusText := 'Rename failed.'
        else
        begin
          LoadDirectory(P);
          for I := 1 to FileCount[P] do
            if Files[P, I] = NewName then
              Selected[P] := I;
          EnsureVisible(P);
          DrawPanelFiles(P);
          StatusText := 'Renamed to ' + NewName;
        end;
      end;
    end;
    SetStatus(StatusText);
  end;
end;


procedure ShowHelp;
begin
  Write(ESC, '[0m');
  NormVideo;
  ClrScr;
  WriteLn('===========================================================');
  WriteLn(ESC, '[1;32m','               TWIN File Manager - HELP', ESC, '[0m');
  WriteLn('===========================================================');
  WriteLn;
  WriteLn('                 (c) 2026, Ralf Kammel');
  WriteLn;
  WriteLn('           Ported to CP/M-86 for the V20-MBC');
  WriteLn('                   Running 8086 mode');
  WriteLn;
  WriteLn('                 by X-Lent Electronics');
  WriteLn('                      Version v2.1');
  WriteLn;
  WriteLn(ESC, '[1m','Command line options:', ESC, '[0m');
  WriteLn('  /S           Terminal setup: choose Columns (80..132)');
  WriteLn('               and Rows (15..60). Default is 90x40.');
  WriteLn;
  WriteLn(ESC, '[1m','Navigation & Commands:', ESC, '[0m');
  WriteLn('  Arrows Move  Up / Down arrows move file selection bar');
  WriteLn('  TAB          Switch active panel (Left / Right)');
  WriteLn('  C            Copy selected file to the other panel');
  WriteLn('  D            Delete selected file');
  WriteLn('  R            Rename selected file (8.3 format)');
  WriteLn('  S            Show contents of Text or ASCII files');
  WriteLn('               COM, CMD or tokenized files not supported');
  WriteLn('  L            Log / Change drive (A-P) for active panel');
  WriteLn('  H            Show this help screen');
  WriteLn('  Q            Quit TWINV20 and return to CP/M-86');
  WriteLn;
  WriteLn('===========================================================');
  AnsiGotoXY(1, ScreenRows - 1);
  Write(ESC, '[1;32;40m');
  Write('Press any key to return to TWIN...');
  ClrEol;
  Read(Kbd, Key);
  Write(ESC, '[0m', ESC, '[37;40m');
  StatusText := 'Help closed.';
end;


{ Main program}
begin
  Active := 1;
  Quit := False;
  AskSize := False;

  for ParamIndex := 1 to ParamCount do
  begin
    if (ParamStr(ParamIndex) = '/s') or
       (ParamStr(ParamIndex) = '/S') then
      AskSize := True;
  end;

  ShowBanner;
  SetupScreen;

  ClearRegs;
  Regs.CX := 12;
  Bdos(Regs);
  CPM3 := Lo(Regs.BX) >= $30;
  if CPM3 then
    ParamIndex := Bdos86(45, 255, Dseg);

  DriveNo[1] := 1;
  DriveNo[2] := 2;
  FileCount[1] := 0;
  FileCount[2] := 0;
  Selected[1] := 0;
  Selected[2] := 0;
  FirstLine[1] := 1;
  FirstLine[2] := 1;
  Truncated[1] := False;
  Truncated[2] := False;

  StatusText := 'Loading drive A...';
  DrawScreen;
  LoadDirectory(1);
  DrawPanel(1);
  
  SetStatus('Loading drive B...');
  LoadDirectory(2);
  DrawPanel(2);
  
  SetStatus('Arrow keys Up/Down move selection');
  
  repeat
    Read(Kbd, Key);
    Redraw := False;
    if Key = #27 then
    begin
      Read(Kbd, Key2);
      if (Key2 = '[') or (Key2 = 'O') then
        Read(Kbd, Key3)
      else
        Key3 := Key2;
      if Key3 = 'A' then
        MoveSelection(Active, -1)
      else if Key3 = 'B' then
        MoveSelection(Active, 1);
    end
    else if Key = #9 then
    begin
      if Active = 1 then
      begin
        Active := 2;
        if FileCount[1] > 0 then
          DrawFileRow(1, Selected[1]);
        if FileCount[2] > 0 then
          DrawFileRow(2, Selected[2]);
      end
      else
      begin
        Active := 1;
        if FileCount[2] > 0 then
          DrawFileRow(2, Selected[2]);
        if FileCount[1] > 0 then
          DrawFileRow(1, Selected[1]);
      end;
      DrawPanelHeader(1);
      DrawPanelHeader(2);
      SetStatus('');
    end
    else if (Key = 'l') or (Key = 'L') then
      ChangeDrive(Active)
    else if (Key = 'c') or (Key = 'C') then
      CopySelected
    else if (Key = 'd') or (Key = 'D') then
      DeleteSelected
    else if (Key = 'r') or (Key = 'R') then
      RenameSelected
    else if (Key = 's') or (Key = 'S') then
    begin
      ShowSelected;
      Redraw := True;
    end
    else if (Key = 'h') or (Key = 'H') then
    begin
      ShowHelp;
      Redraw := True;
    end
    else if (Key = 'q') or (Key = 'Q') then
      Quit := True;
    if not Quit and Redraw then
      DrawScreen;
  until Quit;

  SetDMA86($0080, Dseg);
  if CPM3 then
    ParamIndex := Bdos86(45, 0, Dseg);

  Write(ESC, '[0m');
  NormVideo;
  ClrScr;
end.
