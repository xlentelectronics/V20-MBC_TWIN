module TW22OPS3;

const
  MaxFiles = 150;

type
  Str12      = string[12];
  Str80      = string[80];
  ByteArr36  = array[0..35] of byte;

var
  Files      : external array[1..2, 1..MaxFiles] of Str12;
  FileCount  : external array[1..2] of integer;
  DriveNo    : external array[1..2] of integer;
  Selected   : external array[1..2] of integer;
  RenameFCB  : external ByteArr36;
  ScreenRows : external integer;
  Active     : external integer;
  Key        : external char;
  StatusText : external Str80;
  ESC        : external char;

external function BDOS(func: integer; parm: integer): integer;
external procedure AnsiGotoXY(X, Y: integer);
external procedure ClrScr;
external procedure ClrEol;
external procedure NormVideo;
external procedure ReadKbd(var ch: char);
external procedure LoadDirectory(P: integer);
external procedure EnsureVisible(P: integer);
external procedure DrawList(P: integer);
external procedure SetStatus(Msg: Str80);

procedure PutFCBName(Offset: integer; Name: Str12);
var
  I, BasePos, ExtPos: integer;
  InExtension: boolean;
begin
  for I := 1 to 11 do
    RenameFCB[Offset + I] := ord(' ');
  BasePos := 1;
  ExtPos := 9;
  InExtension := false;
  for I := 1 to length(Name) do
  begin
    if Name[I] = '.' then
      InExtension := true
    else if InExtension then
    begin
      RenameFCB[Offset + ExtPos] := ord(Name[I]);
      ExtPos := ExtPos + 1
    end
    else
    begin
      RenameFCB[Offset + BasePos] := ord(Name[I]);
      BasePos := BasePos + 1
    end
  end
end;

procedure RenameSelected;
var
  P, I, Err, BaseLen, ExtLen: integer;
  NewName: Str12;
  Ch: char;
  Cancelled, InExtension, ValidName, DoneInput: boolean;
begin
  if FileCount[Active] = 0 then
    SetStatus('No file selected in active panel.')
  else
  begin
    P := Active;
    NewName := '';
    Cancelled := false;
    DoneInput := false;
    AnsiGotoXY(1, ScreenRows - 1);
    write(ESC, '[1;32;40m');
    write('New name 8.3, ESC cancels: ');
    ClrEol;
    write(ESC, '[0m', ESC, '[37;40m');
    repeat
      ReadKbd(Ch);
      if Ch = ESC then
      begin
        Cancelled := true;
        DoneInput := true
      end
      else if Ch = chr(13) then
        DoneInput := true
      else if (Ch = chr(8)) or (Ch = chr(127)) then
      begin
        if length(NewName) > 0 then
        begin
          NewName := copy(NewName, 1, length(NewName) - 1);
          write(chr(8), ' ', chr(8))
        end
      end
      else if length(NewName) < 12 then
      begin
        if (Ch >= 'a') and (Ch <= 'z') then
          Ch := chr(ord(Ch) - ord('a') + ord('A'));
        NewName := concat(NewName, Ch);
        write(Ch)
      end
    until DoneInput;

    if Cancelled then
      StatusText := 'Rename cancelled.'
    else if length(NewName) = 0 then
      StatusText := 'No new name entered.'
    else
    begin
      BaseLen := 0;
      ExtLen := 0;
      InExtension := false;
      ValidName := true;
      for I := 1 to length(NewName) do
      begin
        Ch := NewName[I];
        if Ch = '.' then
        begin
          if InExtension or (BaseLen = 0) then
            ValidName := false;
          InExtension := true
        end
        else
        begin
          if (Ch <= ' ') or (Ch = ':') or (Ch = '*') or
             (Ch = '?') or (Ch = ';') or (Ch = ',') or
             (Ch = '=') or (Ch = '[') or (Ch = ']') or
             (Ch = '<') or (Ch = '>') or (Ch = '/') or
             (Ch = chr(92)) or (Ch = '|') then
            ValidName := false;
          if InExtension then
            ExtLen := ExtLen + 1
          else
            BaseLen := BaseLen + 1
        end
      end;
      if (BaseLen > 8) or (ExtLen > 3) then
        ValidName := false;
      if InExtension and (ExtLen = 0) then
        ValidName := false;
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
        Err := BDOS(23, addr(RenameFCB));
        if Err < 0 then
          Err := Err + 256;
        if Err <> 0 then
          StatusText := 'Rename failed.'
        else
        begin
          LoadDirectory(P);
          for I := 1 to FileCount[P] do
            if Files[P, I] = NewName then
              Selected[P] := I;
          EnsureVisible(P);
          DrawList(P);
          StatusText := concat('Renamed to ', NewName)
        end
      end
    end;
    SetStatus(StatusText)
  end
end;

procedure ShowHelp;
begin
  write(ESC, '[0m');
  NormVideo;
  ClrScr;
  writeln('===========================================================');
  writeln(ESC, '[1;32m', '               TWIN File Manager - HELP', ESC, '[0m');
  writeln('===========================================================');
  writeln;
  writeln('                 (c) 2026, Ralf Kammel');
  writeln;
  writeln('           Ported to CP/M 2.2 for the V20-MBC');
  writeln('                   Running 8080 mode'); 
  writeln;                                           
  writeln('                 by X-Lent Electronics');
  writeln('                      Version v2.0');
  writeln;
  writeln(ESC, '[1m', 'Command line options:', ESC, '[0m');
  writeln('  /S           Terminal setup: choose Columns (80..132)');
  writeln('               and Rows (15..60). Default is 90x40.');
  writeln;
  writeln(ESC, '[1m', 'Navigation & Commands:', ESC, '[0m');
  writeln('  Arrows Move  Up / Down arrows move file selection bar');
  writeln('  TAB          Switch active panel (Left / Right)');
  writeln('  C            Copy selected file to the other panel');
  writeln('  D            Delete selected file');
  writeln('  R            Rename selected file (8.3 format)');
  writeln('  S            Show contents of Text or ASCII files');
  writeln('               COM, CMD or tokenized files not supported');
  writeln('  L            Log / Change drive (A-P) for active panel');
  writeln('  H            Show this help screen');
  writeln('  Q            Quit TWIN and return to CP/M 2.2');
  writeln;
  writeln('===========================================================');
  AnsiGotoXY(1, ScreenRows - 1);
  write(ESC, '[1;32;40m');
  write('Press any key to return to TWIN...');
  ClrEol;
  ReadKbd(Key);
  write(ESC, '[0m', ESC, '[37;40m');
  StatusText := 'Help closed.'
end;

modend.
