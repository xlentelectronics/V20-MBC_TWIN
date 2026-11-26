module TW22OPS2;

const
  MaxFiles = 150;

type
  Str12      = string[12];
  Str80      = string[80];
  ByteArr36  = array[0..35] of byte;
  ByteArr128 = array[0..127] of byte;

var
  Files      : external array[1..2, 1..MaxFiles] of Str12;
  FileCount  : external array[1..2] of integer;
  DriveNo    : external array[1..2] of integer;
  Selected   : external array[1..2] of integer;
  FileFCB    : external ByteArr36;
  DirDMA     : external ByteArr128;
  ScreenRows : external integer;
  ScreenCols : external integer;
  Active     : external integer;
  Key        : external char;
  StatusText : external Str80;
  ESC        : external char;
  Dummy      : external integer;

external function BDOS(func: integer; parm: integer): integer;
external procedure AnsiGotoXY(X, Y: integer);
external procedure ClrScr;
external procedure ClrEol;
external procedure ReadKbd(var ch: char);
external procedure FillFCB(var FCB: ByteArr36; Drive: integer; Name: Str12);
external procedure DrawCommandLine;

procedure DrawViewerPage(Name: Str12);
begin
  ClrScr;
  AnsiGotoXY(1, 1);
  write(ESC, '[7m', 'File: ', Name);
  ClrEol;
  write(ESC, '[0m', ESC, '[37;44m');
  AnsiGotoXY(1, ScreenRows - 1);
  write(ESC, '[1;32;40m');
  write('Any key: next page  Q or ESC: quit');
  ClrEol;
  write(ESC, '[0m', ESC, '[37;40m');
  DrawCommandLine
end;

procedure AdvanceViewerLine(var Row, Col: integer; var StopView: boolean; Name: Str12);
begin
  Row := Row + 1;
  Col := 1;
  if Row > ScreenRows - 2 then
  begin
    AnsiGotoXY(1, ScreenRows - 1);
    write(ESC, '[1;32;40m');
    write('Any key: next page  Q or ESC: quit');
    ClrEol;
    ReadKbd(Key);
    write(ESC, '[0m', ESC, '[37;40m');
    if (Key = 'q') or (Key = 'Q') or (Key = ESC) then
      StopView := true
    else
    begin
      DrawViewerPage(Name);
      Row := 2;
      Col := 1
    end
  end
end;

procedure ShowSelected;
var
  P, I, Code, Row, Col: integer;
  Name: Str12;
  StopView, LastCR, EOFSeen, FirstBlock, IsBin, IsBas: boolean;
begin
  if FileCount[Active] = 0 then
    StatusText := 'No file selected in active panel.'
  else
  begin
    P := Active;
    Name := Files[P, Selected[P]];
    FillFCB(FileFCB, DriveNo[P], Name);
    IsBin := false;
    IsBas := false;
    if FileFCB[9] = ord('C') then
      if FileFCB[10] = ord('O') then
        if FileFCB[11] = ord('M') then
          IsBin := true;
    if FileFCB[9] = ord('C') then
      if FileFCB[10] = ord('M') then
        if FileFCB[11] = ord('D') then
          IsBin := true;
    if FileFCB[9] = ord('B') then
      if FileFCB[10] = ord('A') then
        if FileFCB[11] = ord('S') then
          IsBas := true;

    if IsBin then
      StatusText := 'COM, CMD or tokenized files cannot be displayed.'
    else
    begin
      if BDOS(15, addr(FileFCB)) = 255 then
        StatusText := 'Cannot open file.'
      else
      begin
        StopView := false;
        LastCR := false;
        EOFSeen := false;
        FirstBlock := true;
        Row := 2;
        Col := 1;
        Dummy := BDOS(26, addr(DirDMA));
        while (not StopView) and (not EOFSeen) and (BDOS(20, addr(FileFCB)) = 0) do
        begin
          if FirstBlock then
          begin
            FirstBlock := false;
            if IsBas and (DirDMA[0] = 255) then
            begin
              StopView := true;
              StatusText := 'COM, CMD or tokenized files cannot be displayed.'
            end
            else
              DrawViewerPage(Name)
          end;
          I := 0;
          while (I < 128) and (not StopView) and (not EOFSeen) do
          begin
            Code := DirDMA[I];
            if Code = 26 then
              EOFSeen := true
            else if Code = 13 then
            begin
              LastCR := true;
              AdvanceViewerLine(Row, Col, StopView, Name)
            end
            else if Code = 10 then
            begin
              if not LastCR then
                AdvanceViewerLine(Row, Col, StopView, Name);
              LastCR := false
            end
            else
            begin
              LastCR := false;
              if Col > ScreenCols then
                AdvanceViewerLine(Row, Col, StopView, Name);
              if not StopView then
              begin
                AnsiGotoXY(Col, Row);
                if (Code >= 32) and (Code <> 127) then
                  write(chr(Code))
                else if Code = 9 then
                  write(' ')
                else
                  write('.');
                Col := Col + 1
              end
            end;
            I := I + 1
          end
        end;
        Dummy := BDOS(16, addr(FileFCB));
        Dummy := BDOS(26, 128);
        if not StopView then
        begin
          AnsiGotoXY(1, ScreenRows - 1);
          write(ESC, '[1;32;40m');
          write('End of file. Press any key to return...');
          ClrEol;
          ReadKbd(Key);
          write(ESC, '[0m', ESC, '[37;40m');
          StatusText := 'View finished.'
        end
        else if StatusText <> 'COM, CMD or tokenized files cannot be displayed.' then
          StatusText := 'View finished.'
      end
    end
  end
end;

modend.
