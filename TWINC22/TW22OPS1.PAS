module TW22OPS1;

const
  MaxFiles = 150;
  BufRecs  = 8;

type
  Str12      = string[12];
  Str80      = string[80];
  ByteArr36  = array[0..35] of byte;

var
  Files      : external array[1..2, 1..MaxFiles] of Str12;
  FileCount  : external array[1..2] of integer;
  DriveNo    : external array[1..2] of integer;
  Selected   : external array[1..2] of integer;
  FileFCB    : external ByteArr36;
  SrcFCB     : external ByteArr36;
  DstFCB     : external ByteArr36;
  CopyBuf    : external array[0..1023] of byte;
  ScreenRows : external integer;
  Active     : external integer;
  StatusText : external Str80;
  ESC        : external char;
  Dummy      : external integer;

external function BDOS(func: integer; parm: integer): integer;
external procedure AnsiGotoXY(X, Y: integer);
external procedure ClrEol;
external procedure ReadKbd(var ch: char);
external function DriveLetter(D: integer): char;
external procedure FillFCB(var FCB: ByteArr36; Drive: integer; Name: Str12);
external procedure LoadDirectory(P: integer);
external procedure EnsureVisible(P: integer);
external procedure DrawHdr(P: integer);
external procedure DrawList(P: integer);
external procedure SetStatus(Msg: Str80);

procedure ChangeDrive(P: integer);
var
  Ch: char;
  D: integer;
begin
  AnsiGotoXY(1, ScreenRows - 1);
  write(ESC, '[1;32;40m');
  write('Drive A-P (ESC cancels): ');
  ClrEol;
  ReadKbd(Ch);
  write(ESC, '[0m', ESC, '[37;40m');
  if (Ch >= 'a') and (Ch <= 'z') then
    Ch := chr(ord(Ch) - ord('a') + ord('A'));
  if (Ch >= 'A') and (Ch <= 'P') then
  begin
    D := ord(Ch) - ord('A') + 1;
    DriveNo[P] := D;
    Selected[P] := 1;
    LoadDirectory(P);
    DrawHdr(P);
    DrawList(P);
    StatusText := concat('Drive ', DriveLetter(D), ': loaded.')
  end
  else
    StatusText := 'Drive change cancelled.';
  SetStatus(StatusText)
end;

procedure CopySelected;
var
  SrcPanel, DstPanel, I, RecsRead, Err: integer;
  Ch: char;
  Proceed, CopyOK, EOFReached: boolean;
begin
  Proceed := false;
  CopyOK := false;
  if FileCount[Active] = 0 then
    StatusText := 'No file selected in active panel.'
  else
  begin
    SrcPanel := Active;
    if SrcPanel = 1 then
      DstPanel := 2
    else
      DstPanel := 1;
    if DriveNo[SrcPanel] = DriveNo[DstPanel] then
      StatusText := 'Source and destination drive are identical.'
    else
    begin
      FillFCB(SrcFCB, DriveNo[SrcPanel], Files[SrcPanel, Selected[SrcPanel]]);
      FillFCB(DstFCB, DriveNo[DstPanel], Files[SrcPanel, Selected[SrcPanel]]);
      if BDOS(15, addr(SrcFCB)) = 255 then
        StatusText := 'Cannot open source file.'
      else
      begin
        if BDOS(15, addr(DstFCB)) <> 255 then
        begin
          Dummy := BDOS(16, addr(DstFCB));
          AnsiGotoXY(1, ScreenRows - 1);
          write(ESC, '[1;32;40m');
          write('Destination exists. Overwrite (Y/N)? ');
          ClrEol;
          ReadKbd(Ch);
          write(ESC, '[0m', ESC, '[37;40m');
          if (Ch = 'Y') or (Ch = 'y') then
            Proceed := true
          else
            StatusText := 'Copy cancelled.'
        end
        else
          Proceed := true;

        if Proceed then
        begin
          FillFCB(DstFCB, DriveNo[DstPanel], Files[SrcPanel, Selected[SrcPanel]]);
          Dummy := BDOS(19, addr(DstFCB));
          if BDOS(22, addr(DstFCB)) = 255 then
            StatusText := 'Cannot create destination file.'
          else
          begin
            CopyOK := true;
            EOFReached := false;
            repeat
              RecsRead := 0;
              while (RecsRead < BufRecs) and (not EOFReached) do
              begin
                Dummy := BDOS(26, addr(CopyBuf) + RecsRead * 128);
                Err := BDOS(20, addr(SrcFCB));
                if Err = 0 then
                  RecsRead := RecsRead + 1
                else
                  EOFReached := true
              end;
              for I := 0 to RecsRead - 1 do
              begin
                Dummy := BDOS(26, addr(CopyBuf) + I * 128);
                if BDOS(21, addr(DstFCB)) <> 0 then
                begin
                  CopyOK := false;
                  StatusText := 'Error writing destination file.'
                end
              end
            until (not CopyOK) or EOFReached;
            Dummy := BDOS(16, addr(DstFCB))
          end
        end;
        Dummy := BDOS(16, addr(SrcFCB));
        Dummy := BDOS(26, 128)
      end;

      if CopyOK then
      begin
        LoadDirectory(DstPanel);
        for I := 1 to FileCount[DstPanel] do
          if Files[DstPanel, I] = Files[SrcPanel, Selected[SrcPanel]] then
            Selected[DstPanel] := I;
        EnsureVisible(DstPanel);
        DrawHdr(DstPanel);
        DrawList(DstPanel);
        StatusText := concat('File copied to ', DriveLetter(DriveNo[DstPanel]), ':.')
      end
    end
  end;
  SetStatus(StatusText)
end;

procedure DeleteSelected;
var
  P, OldIndex: integer;
  DeleteName: Str12;
  Ch: char;
begin
  if FileCount[Active] = 0 then
    SetStatus('No file selected in active panel.')
  else
  begin
    P := Active;
    OldIndex := Selected[P];
    DeleteName := Files[P, OldIndex];
    AnsiGotoXY(1, ScreenRows - 1);
    write(ESC, '[1;32;40m');
    write('Delete file ', DeleteName, ' (Y/N)? ');
    ClrEol;
    ReadKbd(Ch);
    write(ESC, '[0m', ESC, '[37;40m');
    if (Ch = 'Y') or (Ch = 'y') then
    begin
      FillFCB(FileFCB, DriveNo[P], DeleteName);
      if BDOS(19, addr(FileFCB)) = 255 then
        StatusText := 'Cannot delete file.'
      else
      begin
        LoadDirectory(P);
        if FileCount[P] > 0 then
        begin
          if OldIndex > FileCount[P] then
            OldIndex := FileCount[P];
          Selected[P] := OldIndex;
          EnsureVisible(P)
        end;
        DrawHdr(P);
        DrawList(P);
        StatusText := concat('Deleted: ', DeleteName)
      end
    end
    else
      StatusText := 'Delete cancelled.';
    SetStatus(StatusText)
  end
end;

modend.
