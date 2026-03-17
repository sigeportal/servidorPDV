unit UnitFunctions;

interface

uses
  UnitConnection.Model.Interfaces;

function GeraCodigo(Tabela, Campo: string): integer;
function IncrementaGenerator(Generator: string): integer;
function EnDecryptString(StrValue: String; Chave: Word): String;

implementation

uses
  UnitDatabase;

function GeraCodigo(Tabela, Campo: string): integer;
var Query: iQuery;
begin
	Query := TDatabase.Query;
  Query.Clear;
  Query.Open('SELECT MAX(' + Campo + ') FROM ' + Tabela);
  if Query.Dataset.IsEmpty then
    Result := 1
  else
    Result := Query.Dataset.Fields[0].AsInteger + 1;
end;

function IncrementaGenerator(Generator: string): integer;
var Query: iQuery;
begin
	Query := TDatabase.Query;
	Query.Clear;
	Query.Open('SELECT GEN_ID(' + Generator + ', 1) FROM RDB$DATABASE');
	if Query.DataSet.IsEmpty then
    Result := 1
  else
		Result := Query.DataSet.Fields[0].AsInteger;
end;

function EnDecryptString(StrValue: String; Chave: Word): String;
var
  i       : integer;
  OutValue: String;
begin
  OutValue   := '';
  for i      := 1 to Length(StrValue) do
    OutValue := OutValue + Char(Not(Ord(StrValue[i]) - Chave));
  Result     := OutValue;
end;

end.
