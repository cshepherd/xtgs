{$N+,E+}
program FpErr;
{ A floating-point division by zero: Turbo Pascal's run-time error 200, by way of
  the 8087's interrupt (INT 2) when there is an 8087, of its emulator when not. }
var x, y, z: Double;
begin
  Writeln('Test8087=', Test8087);
  x := 1.0;
  y := 0.0;
  z := x / y;
  Writeln('not reached: ', z)
end.
