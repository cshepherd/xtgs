{ BENCH.INC: fixed work in floating point, each part timed by the BIOS's tick count.
  BENCHR is it with Turbo Pascal's 6-byte software Real ($N-), BENCHD with Double
  ($N+,E+: the 8087 when there is one, TP's emulator when there is not). }
{$IFDEF USE87}
type Float = Double;
{$ELSE}
type Float = Real;
{$ENDIF}
var
  i: Integer;
  a, s: Float;
  t0: LongInt;

procedure Mark(name: String; v: Float);
var t: LongInt;
begin
  t := MemL[$40:$6C];
  Writeln(name, ' ', t - t0, ' ', v:0:9);
  t0 := MemL[$40:$6C];
end;

begin
  Writeln('Test8087=', Test8087);
  t0 := MemL[$40:$6C];
  s := 0;
  for i := 1 to 400 do
  begin
    a := i * 0.001;
    s := s + ((((a * 0.5 + 1.5) * a + 2.5) * a + 3.5) * a + 4.5)
  end;
  Mark('POLY', s);
  s := 0;
  for i := 1 to 400 do
    s := s + 1.0 / i;
  Mark('DIV', s);
  s := 0;
  for i := 1 to 200 do
    s := s + Sqrt(i);
  Mark('SQRT', s);
  s := 0;
  for i := 1 to 20 do
    s := s + Sin(i * 0.1) + Exp(i * 0.05);
  Mark('SINEXP', s);
  s := 0;
  for i := 1 to 20 do
    s := s + Ln(i) + ArcTan(i * 0.1);
  Mark('LNATAN', s)
end.
