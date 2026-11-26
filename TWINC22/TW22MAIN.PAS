program TWINC22;
(*
  TWIN - Two-panel file manager for TP 3.01B and CP/M-86
  Copyright (c) 2026 Ralf Kammel
  SPDX-License-Identifier: MIT
  See LICENSE for the full license text.

  Version v1.0 : Original version by Ralf Kammel

  Version v2.0 : by X-Lent Electronics, November 2026
  TWIN - Two-panel file manager for DRI Pascal/MT+ 5.6.1 and CP/M 2.2
  - Ported to CP/M 2.2 (8080 mode) for the V20-MBC
  - Modularized into 6 units (TW22MAIN, TW22MOD1..2, TW22OPS1..3)
    for Digital Research Pascal/MT+ (80) v5.6.1
  - Startup screen showing Copyright and system info
  - Partial panel redraws on file operations and selection movement
  - Display name in Right panel updated to V20-MBC CP/M 2.2
  - Startup switch /S or /s to configure terminal Columns and Rows
    (Default settings: 90x40)
  - S Show: blocks COM, CMD and tokenized BAS files, waits at EOF
  - Added H Help procedure in dedicated window
  - Removed /O option (file dates not supported in CP/M 2.2)
  - Updated startup banner and help screen to v2.1 / Running 8080 mode
*)

const
  MaxFiles = 150;
  BufRecs  = 8;

type
  Str2       = string[2];
  Str8       = string[8];
  Str12      = string[12];
  Str16      = string[16];
  Str38      = string[38];
  Str80      = string[80];
  ByteArr36  = array[0..35] of byte;
  ByteArr128 = array[0..127] of byte;

var
  Files      : array[1..2, 1..MaxFiles] of Str12;
  FileSizes  : array[1..2, 1..MaxFiles] of integer;
  FileCount  : array[1..2] of integer;
  DriveNo    : array[1..2] of integer;
  Selected   : array[1..2] of integer;
  FirstLine  : array[1..2] of integer;
  Truncated  : array[1..2] of boolean;

  SearchFCB  : ByteArr36;
  RenameFCB  : ByteArr36;
  FileFCB    : ByteArr36;
  SrcFCB     : ByteArr36;
  DstFCB     : ByteArr36;
  DirDMA     : ByteArr128;
  CopyBuf    : array[0..1023] of byte;
  CmdBuf     : absolute [128] ByteArr128;

  ScreenRows : integer;
  ScreenCols : integer;
  Rows       : integer;
  PanelWidth : integer;
  InnerWidth : integer;
  ColSep1    : integer;
  ColSize    : integer;

  Active          : integer;
  Key, Key2, Key3 : char;
  StatusText      : Str80;
  Quit            : boolean;
  Redraw          : boolean;
  AskSize         : boolean;
  ESC             : char;
  Dummy           : integer;
  CmdLen, CmdPos  : integer;
  CmdCh           : char;

external function @BDOS(func: integer; parm: integer): integer;
external procedure ClrScr;
external procedure NormVideo;
external procedure ReadKbd(var ch: char);
external procedure LoadDirectory(P: integer);
external procedure ShowBanner;
external procedure SetupScreen;
external procedure DrawHdr(P: integer);
external procedure DrawPanel(P: integer);
external procedure DrawScreen;
external procedure DrawFileRow(P, N: integer);
external procedure MoveSelection(P, Direction: integer);
external procedure SetStatus(Msg: Str80);
external procedure ChangeDrive(P: integer);
external procedure CopySelected;
external procedure DeleteSelected;
external procedure ShowSelected;
external procedure RenameSelected;
external procedure ShowHelp;

function BDOS(func: integer; parm: integer): integer;
begin
  BDOS := @BDOS(func, parm)
end;

begin
  ESC := chr(27);
  Active := 1;
  Quit := false;
 
  AskSize := false;

  CmdLen := CmdBuf[0];
  if CmdLen > 127 then
    CmdLen := 127;
  CmdPos := 1;
  while CmdPos <= CmdLen do
  begin
    CmdCh := chr(CmdBuf[CmdPos]);
    if CmdCh = '/' then
    begin
      if CmdPos < CmdLen then
      begin
        CmdPos := CmdPos + 1;
        CmdCh := chr(CmdBuf[CmdPos]);
        if (CmdCh = 's') or (CmdCh = 'S') then
          AskSize := true
      end
    end;
    CmdPos := CmdPos + 1
  end;

  ShowBanner;
  SetupScreen;

  DriveNo[1] := 1;
  DriveNo[2] := 2;
  FileCount[1] := 0;
  FileCount[2] := 0;
  Selected[1] := 0;
  Selected[2] := 0;
  FirstLine[1] := 1;
  FirstLine[2] := 1;
  Truncated[1] := false;
  Truncated[2] := false;

  StatusText := 'Loading drive A...';
  DrawScreen;
  LoadDirectory(1);
  DrawPanel(1);

  SetStatus('Loading drive B...');
  LoadDirectory(2);
  DrawPanel(2);

  SetStatus('Arrow keys Up/Down move selection');


  repeat
    ReadKbd(Key);
    Redraw := false;
    if Key = ESC then
    begin
      ReadKbd(Key2);
      if (Key2 = '[') or (Key2 = 'O') then
        ReadKbd(Key3)
      else
        Key3 := Key2;
      if Key3 = 'A' then
        MoveSelection(Active, -1)
      else if Key3 = 'B' then
        MoveSelection(Active, 1)
    end
    else if Key = chr(9) then
    begin
      if Active = 1 then
      begin
        Active := 2;
        if FileCount[1] > 0 then
          DrawFileRow(1, Selected[1]);
        if FileCount[2] > 0 then
          DrawFileRow(2, Selected[2])
      end
      else
      begin
        Active := 1;
        if FileCount[2] > 0 then
          DrawFileRow(2, Selected[2]);
        if FileCount[1] > 0 then
          DrawFileRow(1, Selected[1])
      end;
      DrawHdr(1);
      DrawHdr(2);
      SetStatus('')
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
      Redraw := true
    end
    else if (Key = 'h') or (Key = 'H') then
    begin
      ShowHelp;
      Redraw := true
    end
    else if (Key = 'q') or (Key = 'Q') then
      Quit := true;
    if not Quit and Redraw then
      DrawScreen
  until Quit;

  Dummy := BDOS(26, 128);
  write(ESC, '[0m');
  NormVideo;
  ClrScr
end.
